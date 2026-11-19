#include "BackendBridge.h"

#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QPluginLoader>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QTimer>
#include <QDebug>

int main(int argc, char *argv[]) {
    // AppImages combine bundled Qt with graphics drivers from the host. On
    // Bazzite (including NVIDIA laptops), the software Qt Quick renderer
    // avoids the fatal QRhi OpenGL context failure seen in the first preview.
    // Users may explicitly override QT_QUICK_BACKEND to opt into GPU rendering.
    if (!qEnvironmentVariableIsEmpty("APPIMAGE") && qEnvironmentVariableIsEmpty("QT_QUICK_BACKEND")) {
        qputenv("QT_QUICK_BACKEND", "software");
    }
    QGuiApplication app(argc, argv);
    QCoreApplication::setOrganizationName(QStringLiteral("wolfgangxxiii"));
    QCoreApplication::setApplicationName(QStringLiteral("Plasma Addon Manager"));
    QGuiApplication::setDesktopFileName(
        QStringLiteral("io.github.wolfgangxxiii.PlasmaAddonManager"));
    // Make plugins bundled outside Qt's system prefix visible to Kirigami's
    // platform factory, which also loads plugins under kf6/kirigami/platform.
    const QDir appDirectory(QCoreApplication::applicationDirPath());
    const QString appPlugins = QDir::cleanPath(appDirectory.filePath(QStringLiteral("../plugins")));
    if (QDir(appPlugins).exists()) {
        QCoreApplication::addLibraryPath(appPlugins);
    }
    if (qEnvironmentVariableIsEmpty("QT_QUICK_CONTROLS_STYLE")) {
        QQuickStyle::setStyle(QStringLiteral("org.kde.desktop"));
    }

    const bool smokeTest = QCoreApplication::arguments().contains(QStringLiteral("--self-test"));
    const QString bundledKirigami = QDir(appPlugins).filePath(
        QStringLiteral("kf6/kirigami/platform/org.kde.desktop.so"));
    if (smokeTest && QFileInfo::exists(bundledKirigami)) {
        QPluginLoader loader(bundledKirigami);
        if (!loader.load()) {
            qCritical() << "Bundled Kirigami KDE platform plugin cannot load:" << loader.errorString();
            return 2;
        }
        qInfo() << "Kirigami KDE platform plugin verified:" << bundledKirigami;
    }

    BackendBridge backend;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);
    engine.load(QUrl(QStringLiteral("qrc:/qml/Main.qml")));
    if (engine.rootObjects().isEmpty()) {
        return 1;
    }
    // Package smoke tests verify that all QML imports and the window load.
    // No host state is changed, and the diagnostic helper is not started.
    if (smokeTest) {
        QTimer::singleShot(0, &app, &QCoreApplication::quit);
        return app.exec();
    }
    QTimer::singleShot(0, &backend, [&backend] { backend.runAction(QStringLiteral("diagnose")); });
    return app.exec();
}
