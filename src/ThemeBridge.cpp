#include "ThemeBridge.h"

#include <KColorSchemeManager>
#include <QDebug>
#include <QModelIndex>
#include <QSettings>

ThemeBridge::ThemeBridge(bool testMode, QObject *parent)
    : QObject(parent)
    , m_manager(KColorSchemeManager::instance())
    , m_testMode(testMode) {
    // KColorSchemeManager normally writes to KDE's app config. We maintain one
    // explicit preference instead and never change desktop-wide settings.
    m_manager->setAutosaveChanges(false);
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

bool ThemeBridge::applyChoice(const QString &choice) {
    if (choice == QStringLiteral("auto")) {
        // An invalid index is the documented "follow system colors" setting.
        m_manager->activateScheme(QModelIndex());
        return true;
    }
    const QString schemeId = choice == QStringLiteral("light") ? QStringLiteral("BreezeLight")
                             : choice == QStringLiteral("dark") ? QStringLiteral("BreezeDark")
                             : QString();
    if (schemeId.isEmpty()) return false;
    const QModelIndex schemeIndex = m_manager->indexForSchemeId(schemeId);
    if (!schemeIndex.isValid()) {
        qWarning() << "Cannot find KDE color scheme" << schemeId;
        return false;
    }
    m_manager->activateScheme(schemeIndex);
    return true;
}

bool ThemeBridge::setChoice(const QString &choice) {
    if (choice == m_choice) return true;
    if (!applyChoice(choice)) return false;
    m_choice = choice;
    if (!m_testMode) {
        QSettings().setValue(QStringLiteral("Appearance/theme"), m_choice);
    }
    emit choiceChanged();
    return true;
}
