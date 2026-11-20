#pragma once

#include <QObject>
#include <QString>

class KColorSchemeManager;

// The user's choice is local to Plasma Addon Manager. It must never change
// Plasma's global color scheme or the color preference of another app.
class ThemeBridge final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString choice READ choice NOTIFY choiceChanged)

public:
    explicit ThemeBridge(bool testMode = false, QObject *parent = nullptr);

    QString choice() const { return m_choice; }
    Q_INVOKABLE bool setChoice(const QString &choice);

signals:
    void choiceChanged();

private:
    bool applyChoice(const QString &choice);

    KColorSchemeManager *m_manager = nullptr;
    QString m_choice = QStringLiteral("auto");
    bool m_testMode = false;
};
