#include "BackendBridge.h"

#include <QCoreApplication>
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
        appendOutput(QString::fromUtf8(m_process.readAllStandardError()));
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
                appendOutput(QString::fromUtf8(m_process.readAllStandardError()));
                bool success = exitStatus == QProcess::NormalExit && exitCode == 0;
                if (success && structured) {
                    QJsonParseError error;
                    const QJsonDocument document = QJsonDocument::fromJson(m_jsonOutput.toUtf8(), &error);
                    if (error.error != QJsonParseError::NoError || document.isNull()) {
                        success = false;
                        appendOutput(QStringLiteral("Invalid backend JSON: %1\n").arg(error.errorString()));
                    } else if (action == QStringLiteral("settings-show") && document.isObject()) {
                        emit settingsLoaded(m_jsonOutput.trimmed());
                    } else if (action == QStringLiteral("status-json") && document.isObject()) {
                        emit dashboardLoaded(m_jsonOutput.trimmed());
                    } else if (action == QStringLiteral("inventory-json") && document.isArray()) {
                        emit inventoryLoaded(m_jsonOutput.trimmed());
                    } else if (action == QStringLiteral("updates-json") && document.isObject()) {
                        emit updatesLoaded(m_jsonOutput.trimmed());
                    } else {
                        success = false;
                        appendOutput(QStringLiteral("Unexpected backend data structure.\n"));
                    }
                }
                if (success && action == QStringLiteral("settings-save")) {
                    emit settingsSaved();
                }
                setStatus(success
                              ? QStringLiteral("Completed")
                              : QStringLiteral("Failed (exit %1)").arg(exitCode));
                m_pendingAction.clear();
                emit runningChanged();
                if (action == QStringLiteral("settings-show")
                        || action == QStringLiteral("settings-save")
                        || action == QStringLiteral("install")
                        || action == QStringLiteral("update")
                        || action == QStringLiteral("repair-agent")
                        || action == QStringLiteral("run-service")
                        || action == QStringLiteral("test-config")) {
                    QTimer::singleShot(0, this, [this] { runAction(QStringLiteral("status-json")); });
                }
            });
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            appendOutput(m_process.errorString() + QLatin1Char('\n'));
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
    // Avoid unbounded GUI memory usage when a CLI prints extensive logs.
    constexpr int maxCharacters = 160000;
    if (m_output.size() > maxCharacters) {
        m_output = QStringLiteral("[… earlier output truncated …]\n")
                       + m_output.right(maxCharacters - 36);
    }
    emit outputChanged();
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
    if (running() || json.size() > 16000) {
        return;
    }
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(json.toUtf8(), &error);
    if (error.error != QJsonParseError::NoError || !document.isObject()) {
        appendOutput(QStringLiteral("Invalid automation settings: %1\n").arg(error.errorString()));
        setStatus(QStringLiteral("Invalid settings"));
        return;
    }
    startAction(QStringLiteral("settings-save"),
                {QStringLiteral("settings-save"), json,
                 migrateLegacy ? QStringLiteral("migrate") : QStringLiteral("keep")});
}

void BackendBridge::startAction(const QString &action, const QStringList &arguments) {
    m_output.clear();
    m_jsonOutput.clear();
    emit outputChanged();
    const QString helper = helperPath();
    if (helper.isEmpty()) {
        appendOutput(QStringLiteral("Backend helper is missing. Reinstall the complete application.\n"));
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
