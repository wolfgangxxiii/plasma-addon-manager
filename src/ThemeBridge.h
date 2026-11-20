#pragma once

#include <QColor>
#include <QObject>
#include <QPalette>
#include <QString>
#include <QVariant>

class KColorSchemeManager;

// The user's choice is local to Plasma Addon Manager. It must never change
// Plasma's global color scheme or the color preference of another app.
class ThemeBridge final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString choice READ choice NOTIFY choiceChanged)
    Q_PROPERTY(QColor accentColor READ accentColor NOTIFY accentColorChanged)

public:
    explicit ThemeBridge(bool testMode = false, QObject *parent = nullptr);

    QString choice() const { return m_choice; }
    QColor accentColor() const { return m_accentColor; }
    Q_INVOKABLE bool setChoice(const QString &choice);

signals:
    void choiceChanged();
    void accentColorChanged();

private:
    bool applyChoice(const QString &choice);
    void refreshSystemAccent();

    KColorSchemeManager *m_manager = nullptr;
    QPalette m_nativePalette;
    QVariant m_nativeSchemePath;
    QColor m_accentColor;
    QString m_choice = QStringLiteral("auto");
    bool m_testMode = false;
};
