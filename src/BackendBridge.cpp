#include "BackendBridge.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonParseError>
#include <QStandardPaths>
#include <QStringList>
#include <QTimer>

#ifdef Q_OS_UNIX
#include <csignal>
#include <unistd.h>
#endif

BackendBridge::BackendBridge(QObject *parent) : QObject(parent) {
    appendOutput(QStringLiteral("[%1] Plasma Addon Manager — session started\n")
                     .arg(QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd HH:mm:ss"))));
#ifdef Q_OS_UNIX
    // The Rust helper starts plasmoid-updater as a child. Put both in a
    // separate process group so Cancel cannot leave a background update alive.
    m_process.setChildProcessModifier([] { ::setpgid(0, 0); });
#endif
    connect(&m_process, &QProcess::readyReadStandardOutput, this, [this] {
        const QString chunk = QString::fromUtf8(m_process.readAllStandardOutput());
        if (m_pendingAction.endsWith(QStringLiteral("-json"))
                || m_pendingAction == QStringLiteral("settings-show")) {
            m_jsonOutput += chunk;
        } else {
            appendOutput(chunk);
        }
    });
    connect(&m_process, &QProcess::readyReadStandardError, this, [this] {
        const QString chunk = QString::fromUtf8(m_process.readAllStandardError());
        m_pendingError += chunk;
        appendOutput(chunk);
    });
    connect(&m_process, &QProcess::finished, this,
            [this](int exitCode, QProcess::ExitStatus exitStatus) {
                const QString tail = QString::fromUtf8(m_process.readAllStandardOutput());
                const QString action = m_pendingAction;
                const bool structured = action.endsWith(QStringLiteral("-json"))
                        || action == QStringLiteral("settings-show");
                if (structured) {
                    m_jsonOutput += tail;
                } else {
                    appendOutput(tail);
                }
                const QString errorTail = QString::fromUtf8(m_process.readAllStandardError());
                m_pendingError += errorTail;
                appendOutput(errorTail);
                bool success = exitStatus == QProcess::NormalExit && exitCode == 0;
                if (success && structured) {
                    QJsonParseError error;
                    const QJsonDocument document = QJsonDocument::fromJson(m_jsonOutput.toUtf8(), &error);
                    if (error.error != QJsonParseError::NoError || document.isNull()) {
                        success = false;
                        m_pendingError = QStringLiteral("Invalid backend JSON: %1").arg(error.errorString());
                        appendOutput(m_pendingError + QLatin1Char('\n'));
                    } else if (action == QStringLiteral("settings-show") && document.isObject()) {
                        emit settingsLoaded(m_jsonOutput.trimmed());
                    } else if (action == QStringLiteral("status-json") && document.isObject()) {
                        emit dashboardLoaded(m_jsonOutput.trimmed());
                    } else if (action == QStringLiteral("inventory-json") && document.isObject()) {
                        emit inventoryLoaded(m_jsonOutput.trimmed());
                    } else if (action == QStringLiteral("updates-json") && document.isObject()) {
                        emit updatesLoaded(m_jsonOutput.trimmed());
                    } else {
                        success = false;
                        m_pendingError = QStringLiteral("Unexpected backend data structure.");
                        appendOutput(m_pendingError + QLatin1Char('\n'));
                    }
                }
                success = success && !m_cancelRequested;
                if (success && action == QStringLiteral("settings-save")) {
                    emit settingsSaved();
                }
                setStatus(success
                              ? QStringLiteral("Completed")
                              : QStringLiteral("Failed (exit %1)").arg(exitCode));
                const QString error = m_cancelRequested
                                          ? QStringLiteral("Cancelled by the user")
                                          : m_pendingError.trimmed();
                appendOutput(QStringLiteral("\n[%1] %2 %3 (exit %4)\n\n")
                                 .arg(QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss")),
                                      success ? QStringLiteral("✓") : QStringLiteral("✗"),
                                      action, QString::number(exitCode)));
                if (!m_pendingSilent) {
                    setOperationResult(action, success, error);
                }
                m_pendingAction.clear();
                m_pendingError.clear();
                emit runningChanged();
                if (action == QStringLiteral("settings-show")
                        || action == QStringLiteral("settings-save")
                        || action == QStringLiteral("install")
                        || action == QStringLiteral("update")
                        || action == QStringLiteral("repair-agent")
                        || action == QStringLiteral("run-service")
                        || action == QStringLiteral("test-config")) {
                    QTimer::singleShot(0, this, [this] {
                        if (!running()) {
                            startAction(QStringLiteral("status-json"),
                                        {QStringLiteral("status-json")}, true);
                        }
                    });
                }
            });
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            const QString reason = m_process.errorString();
            appendOutput(reason + QLatin1Char('\n'));
            appendOutput(QStringLiteral("[%1] ✗ %2 (could not start)\n\n")
                             .arg(QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss")),
                                  m_pendingAction));
            if (!m_pendingSilent) {
                setOperationResult(m_pendingAction, false, reason);
            }
            m_pendingAction.clear();
            m_pendingError.clear();
            setStatus(QStringLiteral("Cannot start backend"));
            emit runningChanged();
        }
    });
}

QString BackendBridge::helperPath() const {
    // Explicit override is useful for local development and CI.
    const QString overridePath = qEnvironmentVariable("PLASMA_ADDON_HELPER");
    if (!overridePath.isEmpty()) {
        return overridePath;
    }
    const QDir appDirectory(QCoreApplication::applicationDirPath());
    const QStringList paths = {
        appDirectory.filePath(QStringLiteral("plasma-addon-helper")),
        appDirectory.filePath(QStringLiteral("../libexec/plasma-addon-manager/plasma-addon-helper")),
        appDirectory.filePath(QStringLiteral("../lib/plasma-addon-manager/plasma-addon-helper"))
    };
    for (const QString &path : paths) {
        if (QFileInfo(path).isExecutable()) {
            return QDir::cleanPath(path);
        }
    }
    return QStandardPaths::findExecutable(QStringLiteral("plasma-addon-helper"));
}

void BackendBridge::appendOutput(const QString &text) {
    if (text.isEmpty()) {
        return;
    }
    m_output += text;
    // Keep every entry for the lifetime of this application session.
    // The log resets only when the application is launched again.
    emit outputChanged();
}

void BackendBridge::setOperationResult(const QString &action, bool succeeded, const QString &error) {
    m_lastOperation = action;
    m_lastOperationSucceeded = succeeded;
    // Keep error banners brief; the full diagnostic remains in the session log.
    m_lastOperationError = error.simplified().left(360);
    emit operationResultChanged();
}

void BackendBridge::setStatus(const QString &text) {
    if (m_status == text) {
        return;
    }
    m_status = text;
    emit statusChanged();
}

void BackendBridge::runAction(const QString &action) {
    static const QStringList allowedActions = {
        QStringLiteral("diagnose"), QStringLiteral("inventory"),
        QStringLiteral("check"), QStringLiteral("dry-run"), QStringLiteral("update"),
        QStringLiteral("install"), QStringLiteral("settings-show"),
        QStringLiteral("status-json"), QStringLiteral("inventory-json"),
        QStringLiteral("updates-json"), QStringLiteral("test-config"),
        QStringLiteral("timer"), QStringLiteral("journal"),
        QStringLiteral("repair-agent"), QStringLiteral("run-service")
    };
    if (running() || !allowedActions.contains(action)) {
        return;
    }
    startAction(action, {action});
}

void BackendBridge::saveSettings(const QString &json, bool migrateLegacy) {
    if (running()) {
        return;
    }
    if (json.size() > 16000) {
        appendOutput(QStringLiteral("Settings are too large to save.\n"));
        setOperationResult(QStringLiteral("settings-save"), false,
                           QStringLiteral("Settings are too large to save"));
        return;
    }
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(json.toUtf8(), &error);
    if (error.error != QJsonParseError::NoError || !document.isObject()) {
        appendOutput(QStringLiteral("Invalid automation settings: %1\n").arg(error.errorString()));
        setStatus(QStringLiteral("Invalid settings"));
        setOperationResult(QStringLiteral("settings-save"), false,
                           QStringLiteral("Invalid automation settings: %1").arg(error.errorString()));
        return;
    }
    startAction(QStringLiteral("settings-save"),
                {QStringLiteral("settings-save"), json,
                 migrateLegacy ? QStringLiteral("migrate") : QStringLiteral("keep")});
}

void BackendBridge::startAction(const QString &action, const QStringList &arguments, bool silent) {
    // Every action, including background refreshes, becomes a separate entry
    // in the one session log. Nothing clears earlier operations.
    appendOutput(QStringLiteral("\n[%1] ▶ %2\n")
                     .arg(QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss")), action));
    m_jsonOutput.clear();
    m_pendingError.clear();
    m_pendingSilent = silent || action == QStringLiteral("settings-show");
    m_cancelRequested = false;
    const QString helper = helperPath();
    if (helper.isEmpty()) {
        const QString reason = QStringLiteral("Backend helper is missing. Reinstall the complete application.");
        appendOutput(reason + QLatin1Char('\n'));
        appendOutput(QStringLiteral("[%1] ✗ %2 (helper missing)\n\n")
                         .arg(QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss")), action));
        if (!m_pendingSilent) {
            setOperationResult(action, false, reason);
        }
        setStatus(QStringLiteral("Backend missing"));
        return;
    }
    setStatus(QStringLiteral("Running %1…").arg(action));
    m_pendingAction = action;
    m_process.setProgram(helper);
    m_process.setArguments(arguments);
    m_process.start();
    emit runningChanged();
}

void BackendBridge::cancel() {
    if (!running()) {
        return;
    }
    m_cancelRequested = true;
    appendOutput(QStringLiteral("[%1] User requested cancellation of %2\n")
                     .arg(QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss")),
                          m_pendingAction));
#ifdef Q_OS_UNIX
    const qint64 pid = m_process.processId();
    if (pid > 1 && ::getpgid(static_cast<pid_t>(pid)) == pid) {
        ::kill(-static_cast<pid_t>(pid), SIGTERM);
        QTimer::singleShot(1500, this, [this, pid] {
            if (running() && m_process.processId() == pid) {
                if (::getpgid(static_cast<pid_t>(pid)) == pid) {
                    ::kill(-static_cast<pid_t>(pid), SIGKILL);
                }
                m_process.kill();
            }
        });
    } else {
        m_process.kill();
    }
#else
    m_process.kill();
#endif
    setStatus(QStringLiteral("Cancelling…"));
}
