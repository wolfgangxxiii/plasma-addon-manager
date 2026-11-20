#pragma once

#include <QString>
#include <QStringList>

namespace DesktopIconIntegration {

// KDE/Wayland resolves an app_id through an installed, same-named .desktop
// entry. An icon embedded inside an AppImage alone is not visible to KWin.
QString desktopId();

// Register a hidden desktop identity for direct AppImage launches. This does
// not replace desktop entries created by package managers or Gear Lever.
bool ensureAppImageIcon(const QString &appImagePath, const QString &dataHome,
                        const QStringList &systemDataLocations, QString *error);

} // namespace DesktopIconIntegration
