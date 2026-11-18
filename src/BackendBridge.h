#pragma once

#include <QObject>
#include <QProcess>
#include <QString>

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
    Q_INVOKABLE void cancel();

signals:
    void outputChanged();
    void statusChanged();
    void runningChanged();

private:
    QString helperPath() const;
    void appendOutput(const QString &text);
    void setStatus(const QString &text);

    QProcess m_process;
    QString m_output;
    QString m_status = QStringLiteral("Ready");
};
