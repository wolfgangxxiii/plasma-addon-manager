#pragma once

#include <QObject>
#include <QProcess>
#include <QString>
#include <QStringList>

class BackendBridge final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString output READ output NOTIFY outputChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(QString currentAction READ currentAction NOTIFY currentActionChanged)
    Q_PROPERTY(QString progressDetail READ progressDetail NOTIFY progressDetailChanged)
    Q_PROPERTY(QString lastOperation READ lastOperation NOTIFY operationResultChanged)
    Q_PROPERTY(QString lastOperationError READ lastOperationError NOTIFY operationResultChanged)
    Q_PROPERTY(bool lastOperationSucceeded READ lastOperationSucceeded NOTIFY operationResultChanged)

public:
    explicit BackendBridge(QObject *parent = nullptr);

    QString output() const { return m_output; }
    QString status() const { return m_status; }
    bool running() const { return m_process.state() != QProcess::NotRunning; }
    QString currentAction() const { return m_pendingAction; }
    QString progressDetail() const { return m_progressDetail; }
    QString lastOperation() const { return m_lastOperation; }
    QString lastOperationError() const { return m_lastOperationError; }
    bool lastOperationSucceeded() const { return m_lastOperationSucceeded; }

    Q_INVOKABLE void runAction(const QString &action);
    Q_INVOKABLE void saveSettings(const QString &json, bool migrateLegacy);
    Q_INVOKABLE void cancel();

signals:
    void outputChanged();
    void statusChanged();
    void runningChanged();
    void currentActionChanged();
    void progressDetailChanged();
    void operationResultChanged();
    void settingsLoaded(const QString &json);
    void settingsSaved();
    void dashboardLoaded(const QString &json);
    void inventoryLoaded(const QString &json);
    void updatesLoaded(const QString &json);

private:
    QString helperPath() const;
    void appendOutput(const QString &text);
    void setStatus(const QString &text);
    void setProgressDetail(const QString &text);
    void readProgressDetail(const QString &chunk);
    void setOperationResult(const QString &action, bool succeeded, const QString &error = {});
    void startAction(const QString &action, const QStringList &arguments, bool silent = false);

    QProcess m_process;
    QString m_output;
    QString m_jsonOutput;
    QString m_status = QStringLiteral("Ready");
    QString m_pendingAction;
    QString m_pendingError;
    QString m_progressDetail;
    QString m_lastOperation;
    QString m_lastOperationError;
    bool m_lastOperationSucceeded = false;
    bool m_pendingSilent = false;
    bool m_cancelRequested = false;
};
