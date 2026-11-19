#include "BackendBridge.h"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QTimer>

int main(int argc, char *argv[]) {
    QGuiApplication app(argc, argv);
    QCoreApplication::setOrganizationName(QStringLiteral("wolfgangxxiii"));
    QCoreApplication::setApplicationName(QStringLiteral("Plasma Addon Manager"));
    QGuiApplication::setDesktopFileName(
        QStringLiteral("io.github.wolfgangxxiii.PlasmaAddonManager"));
    if (qEnvironmentVariableIsEmpty("QT_QUICK_CONTROLS_STYLE")) {
        QQuickStyle::setStyle(QStringLiteral("org.kde.desktop"));
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
    if (QCoreApplication::arguments().contains(QStringLiteral("--self-test"))) {
        QTimer::singleShot(0, &app, &QCoreApplication::quit);
        return app.exec();
    }
    QTimer::singleShot(0, &backend, [&backend] { backend.runAction(QStringLiteral("diagnose")); });
    return app.exec();
}
