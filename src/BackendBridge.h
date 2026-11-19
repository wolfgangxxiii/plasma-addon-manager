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

public:
    explicit BackendBridge(QObject *parent = nullptr);

    QString output() const { return m_output; }
    QString status() const { return m_status; }
    bool running() const { return m_process.state() != QProcess::NotRunning; }

    Q_INVOKABLE void runAction(const QString &action);
    Q_INVOKABLE void saveSettings(const QString &json, bool migrateLegacy);
    Q_INVOKABLE void cancel();

signals:
    void outputChanged();
    void statusChanged();
    void runningChanged();
    void settingsLoaded(const QString &json);
    void settingsSaved();

private:
    QString helperPath() const;
    void appendOutput(const QString &text);
    void setStatus(const QString &text);
    void startAction(const QString &action, const QStringList &arguments);

    QProcess m_process;
    QString m_output;
    QString m_status = QStringLiteral("Ready");
    QString m_pendingAction;
};
