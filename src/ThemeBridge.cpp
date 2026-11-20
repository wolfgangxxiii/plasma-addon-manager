#include "ThemeBridge.h"

#include <KColorSchemeManager>
#include <KConfigGroup>
#include <KSharedConfig>
#include <QDebug>
#include <QGuiApplication>
#include <QModelIndex>
#include <QSettings>

ThemeBridge::ThemeBridge(bool testMode, QObject *parent)
    : QObject(parent)
    , m_nativePalette(QGuiApplication::palette())
    , m_nativeSchemePath(qApp->property("KDE_COLOR_SCHEME_PATH"))
    , m_testMode(testMode) {
    // Do not construct KColorSchemeManager for Auto: on an AppImage with no
    // KDE Qt platform theme, its initialization can replace Plasma's accent
    // with the stock Breeze blue before the window is even created.
    refreshSystemAccent();
    const QString saved = m_testMode ? QStringLiteral("auto")
                                     : QSettings().value(QStringLiteral("Appearance/theme"),
                                                         QStringLiteral("auto")).toString();
    if (!applyChoice(saved)) {
        qWarning() << "Stored appearance is unavailable, following Plasma instead:" << saved;
        applyChoice(QStringLiteral("auto"));
    } else {
        m_choice = saved;
    }
}

void ThemeBridge::refreshSystemAccent() {
    QColor next = m_nativePalette.color(QPalette::Active, QPalette::Highlight);
    if (!m_testMode) {
        // Plasma applies the user's accent to kdeglobals' selection colors.
        // Unlike the bundled Breeze presets, this includes custom accents.
        const auto config = KSharedConfig::openConfig(QStringLiteral("kdeglobals"), KConfig::SimpleConfig);
        config->reparseConfiguration();
        const QColor kdeAccent = KConfigGroup(config, QStringLiteral("Colors:Selection"))
                                     .readEntry("BackgroundNormal", QColor());
        if (kdeAccent.isValid()) next = kdeAccent;
    }
    if (next != m_accentColor) {
        m_accentColor = next;
        emit accentColorChanged();
    }
}

bool ThemeBridge::applyChoice(const QString &choice) {
    if (choice == QStringLiteral("auto")) {
        // Restore the untouched Qt/Kirigami system palette and any native
        // color-scheme hint. Auto must not install a generic Breeze palette.
        if (m_manager) {
            m_manager->activateScheme(QModelIndex());
            qApp->setProperty("KDE_COLOR_SCHEME_PATH", m_nativeSchemePath);
            QGuiApplication::setPalette(m_nativePalette);
        }
        return true;
    }
    const QString schemeId = choice == QStringLiteral("light") ? QStringLiteral("BreezeLight")
                             : choice == QStringLiteral("dark") ? QStringLiteral("BreezeDark")
                             : QString();
    if (schemeId.isEmpty()) return false;
    if (!m_manager) {
        m_manager = KColorSchemeManager::instance();
        // App-only preferences are handled by QSettings, never KDE globals.
        m_manager->setAutosaveChanges(false);
    }
    const QModelIndex schemeIndex = m_manager->indexForSchemeId(schemeId);
    if (!schemeIndex.isValid()) {
        qWarning() << "Cannot find KDE color scheme" << schemeId;
        return false;
    }
    m_manager->activateScheme(schemeIndex);
    // Preserve the Plasma-selected accent even while forcing light/dark
    // backgrounds. The QML highlight uses the same color as these controls.
    QPalette palette = QGuiApplication::palette();
    for (const auto group : {QPalette::Active, QPalette::Inactive, QPalette::Disabled}) {
        palette.setColor(group, QPalette::Highlight, m_accentColor);
#if QT_VERSION >= QT_VERSION_CHECK(6, 6, 0)
        palette.setColor(group, QPalette::Accent, m_accentColor);
#endif
    }
    QGuiApplication::setPalette(palette);
    return true;
}

bool ThemeBridge::setChoice(const QString &choice) {
    if (choice == m_choice) return true;
    if (m_choice == QStringLiteral("auto")) {
        // The native palette may have changed while the app followed Plasma.
        m_nativePalette = QGuiApplication::palette();
        m_nativeSchemePath = qApp->property("KDE_COLOR_SCHEME_PATH");
    }
    refreshSystemAccent();
    if (!applyChoice(choice)) return false;
    m_choice = choice;
    if (!m_testMode) {
        QSettings().setValue(QStringLiteral("Appearance/theme"), m_choice);
    }
    emit choiceChanged();
    return true;
}
