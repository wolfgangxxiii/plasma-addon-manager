#include "BackendBridge.h"

#include <QDir>
#include <QEventLoop>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QPluginLoader>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QTimer>
#include <QTemporaryDir>
#include <QDebug>
#include <QVariantList>
#include <QVariantMap>

// Exercise the real asynchronous bridge with a local fake helper. No system
// settings or KDE add-ons are touched: this is a pure session-log regression test.
static int sessionLogTest() {
    QTemporaryDir directory;
    if (!directory.isValid()) {
        qCritical() << "Cannot create session log test directory";
        return 4;
    }
    const QString helperPath = directory.filePath(QStringLiteral("fake-plasma-addon-helper"));
    QFile helper(helperPath);
    const QByteArray script =
        "#!/bin/sh\n"
        "case \"$1\" in\n"
        "  diagnose) printf 'diagnostic output\\n' ;;\n"
        "  check) printf 'network unavailable\\n' >&2; exit 23 ;;\n"
        "  timer) printf 'timer output\\n' ;;\n"
        "  *) exit 42 ;;\n"
        "esac\n";
    if (!helper.open(QIODevice::WriteOnly) || helper.write(script) != script.size()) {
        qCritical() << "Cannot create fake helper";
        return 4;
    }
    helper.close();
    if (!helper.setPermissions(QFileDevice::ReadUser | QFileDevice::WriteUser
                               | QFileDevice::ExeUser)) {
        qCritical() << "Cannot make fake helper executable";
        return 4;
    }
    qputenv("PLASMA_ADDON_HELPER", QFile::encodeName(helperPath));
    BackendBridge backend;
    const auto run = [&backend](const QString &action) {
        QEventLoop loop;
        QTimer timeout;
        timeout.setSingleShot(true);
        bool timedOut = false;
        QObject::connect(&timeout, &QTimer::timeout, &loop, [&] {
            timedOut = true;
            loop.quit();
        });
        QObject::connect(&backend, &BackendBridge::runningChanged, &loop, [&] {
            if (!backend.running()) {
                loop.quit();
            }
        });
        backend.runAction(action);
        if (backend.running()) {
            timeout.start(10000);
            loop.exec();
        }
        return !timedOut && !backend.running();
    };
    if (!run(QStringLiteral("diagnose")) || !backend.lastOperationSucceeded()
            || !run(QStringLiteral("check")) || backend.lastOperationSucceeded()
            || !backend.lastOperationError().contains(QStringLiteral("network unavailable"))
            || !run(QStringLiteral("timer")) || !backend.lastOperationSucceeded()) {
        qCritical() << "Session log test: operation status did not follow success/failure";
        return 4;
    }
    const QString log = backend.output();
    const int first = log.indexOf(QStringLiteral("▶ diagnose"));
    const int second = log.indexOf(QStringLiteral("▶ check"));
    const int third = log.indexOf(QStringLiteral("▶ timer"));
    if (first < 0 || second <= first || third <= second
            || !log.contains(QStringLiteral("diagnostic output"))
            || !log.contains(QStringLiteral("network unavailable"))
            || !log.contains(QStringLiteral("timer output"))
            || !log.contains(QStringLiteral("✓ diagnose"))
            || !log.contains(QStringLiteral("✗ check"))
            || !log.contains(QStringLiteral("✓ timer"))) {
        qCritical() << "Session log test: earlier actions or their output went missing" << log;
        return 4;
    }
    qInfo() << "Session log test passed: successful and failed actions are preserved";
    return 0;
}

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
    if (QCoreApplication::arguments().contains(QStringLiteral("--self-test-session-log"))) {
        return sessionLogTest();
    }
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
    bool qmlBindingError = false;
    if (smokeTest) {
        QObject::connect(&engine, &QQmlEngine::warnings, &app,
                         [&qmlBindingError](const QList<QQmlError> &warnings) {
            for (const QQmlError &warning : warnings) {
                const QString message = warning.toString();
                if (message.contains(QStringLiteral("ReferenceError"))
                        || message.contains(QStringLiteral("TypeError"))) {
                    qCritical() << "QML smoke test binding error:" << message;
                    qmlBindingError = true;
                }
            }
        });
    }
    engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);
    engine.load(QUrl(QStringLiteral("qrc:/qml/Main.qml")));
    if (engine.rootObjects().isEmpty()) {
        return 1;
    }
    // Package smoke tests verify that all QML imports and the window load.
    // No host state is changed, and the diagnostic helper is not started.
    if (smokeTest) {
        // Create the repeated add-on cards too; merely loading the initial
        // empty window never instantiates their QML delegates.
        QObject *root = engine.rootObjects().first();
        QVariantMap addon;
        addon.insert(QStringLiteral("name"), QStringLiteral("Test Plasma Widget"));
        addon.insert(QStringLiteral("directory_name"), QStringLiteral("test-widget"));
        addon.insert(QStringLiteral("version"), QStringLiteral("1.0"));
        addon.insert(QStringLiteral("component_type"), QStringLiteral("Plasma Widget"));
        addon.insert(QStringLiteral("is_system"), false);
        QVariantMap update;
        update.insert(QStringLiteral("installed"), addon);
        update.insert(QStringLiteral("latest_version"), QStringLiteral("1.1"));
        root->setProperty("installedAddons", QVariantList{addon});
        root->setProperty("inventoryReady", true);
        root->setProperty("section", 1);
        QCoreApplication::processEvents();
        root->setProperty("availableUpdates", QVariantList{update});
        root->setProperty("updatesReady", true);
        root->setProperty("addonView", 1);
        QCoreApplication::processEvents();
        root->setProperty("section", 2);
        QCoreApplication::processEvents();
        if (qmlBindingError) {
            return 3;
        }
        QTimer::singleShot(0, &app, &QCoreApplication::quit);
        return app.exec();
    }
    QTimer::singleShot(0, &backend, [&backend] { backend.runAction(QStringLiteral("settings-show")); });
    return app.exec();
}
