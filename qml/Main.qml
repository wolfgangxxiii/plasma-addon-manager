import QtQuick
import QtQml
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: window
    width: 1180
    height: 780
    minimumWidth: 690
    minimumHeight: 540
    title: "Plasma Addon Manager"

    // In Auto, leave Kirigami's system palette alone so Plasma's accent and
    // live color changes keep working. Only override highlights when forcing
    // one of the bundled light/dark Breeze backgrounds.
    Binding {
        target: window.Kirigami.Theme
        property: "highlightColor"
        value: themeBridge.accentColor
        when: themeBridge.choice !== "auto"
    }

    readonly property color effectiveAccentColor: Kirigami.Theme.highlightColor

    property int section: 0
    property string languageChoice: "auto"
    property bool automationConfigLoaded: false
    property string automationLoadError: ""
    property bool automaticEnabled: true
    property bool updateToolEnabled: true
    property int updateFrequency: 24
    property bool restartPlasma: false
    property bool notifySuccess: false
    property bool notifyError: true
    property string excludedPackages: ""
    property var dashboard: ({})
    property var installedAddons: []
    property string inventoryWarning: ""
    property var availableUpdates: []
    property var updateIssues: []
    property var cleanupPreview: ({ items: [], preserved_pl: [], preserved_en: [] })
    property int skippedUpdates: 0
    property int unmatchedUpdates: 0
    property int addonView: 0
    property bool addonListExpanded: true
    property bool inventoryReady: false
    property bool updatesReady: false
    property var notifications: []
    property int notificationSequence: 0
    property int elapsedSeconds: 0
    readonly property bool showNotificationSidebar: width >= 980
    readonly property bool bsdtarMissing: dashboard.bsdtar_available === false
    readonly property bool polish: languageChoice === "pl"
                                   || (languageChoice === "auto"
                                       && Qt.locale().name.toLowerCase().startsWith("pl"))
    function loc(pl, en) { return polish ? pl : en }
    function noticeColor(kind) {
        if (kind === "success") return Kirigami.Theme.positiveTextColor
        if (kind === "error") return Kirigami.Theme.negativeTextColor
        if (kind === "warning") return Kirigami.Theme.neutralTextColor
        return Kirigami.Theme.highlightColor
    }
    function noticeBackground(kind) {
        const base = noticeColor(kind)
        return Qt.rgba(base.r, base.g, base.b, 0.10)
    }
    function addNotification(kind, heading, detail) {
        const next = notifications.slice()
        next.unshift({
            key: ++notificationSequence,
            kind: kind,
            heading: heading,
            detail: detail,
            time: Qt.formatTime(new Date(), "HH:mm:ss")
        })
        // Notifications are short-lived UI summaries. The session journal
        // remains complete and is never cleared by this panel.
        notifications = next.slice(0, 20)
    }
    function elapsedLabel() {
        const minutes = Math.floor(elapsedSeconds / 60)
        const seconds = elapsedSeconds % 60
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
    }
    function cleanupItemsText() {
        const lines = []
        const items = cleanupPreview.items || []
        for (let i = 0; i < items.length; i++) {
            const item = items[i]
            lines.push("• " + (polish ? item.label_pl : item.label_en)
                       + (item.optional ? loc(" (opcjonalnie)", " (optional)") : "")
                       + "\n  " + item.path)
        }
        return lines.length > 0 ? lines.join("\n\n")
            : loc("Nie znaleziono elementów do usunięcia.", "No removable items were found.")
    }
    function actionName(action) {
        switch (action) {
        case "diagnose": return loc("Diagnostyka środowiska", "Environment diagnostics")
        case "install": return loc("Instalacja aktualizatora", "Updater installation")
        case "inventory":
        case "inventory-json": return loc("Lista dodatków", "Add-on inventory")
        case "check":
        case "updates-json": return loc("Sprawdzanie aktualizacji", "Update check")
        case "dry-run": return loc("Symulacja aktualizacji", "Update preview")
        case "update": return loc("Aktualizacja dodatków", "Add-on update")
        case "settings-show": return loc("Odczyt ustawień", "Load settings")
        case "settings-save": return loc("Zapis automatyzacji", "Save automation")
        case "status-json": return loc("Odświeżenie stanu", "Status refresh")
        case "timer": return loc("Sprawdzenie harmonogramu", "Schedule status")
        case "journal": return loc("Odczyt dziennika systemd", "Read systemd journal")
        case "repair-agent": return loc("Naprawa agenta", "Repair agent")
        case "run-service": return loc("Uruchomienie aktualizacji w tle", "Run background update")
        case "test-config": return loc("Test konfiguracji", "Configuration test")
        case "cleanup-preview": return loc("Podgląd przywracania", "Cleanup preview")
        case "cleanup": return loc("Usuwanie zmian aplikacji", "Remove application changes")
        default: return action
        }
    }
    readonly property string currentSection: {
        switch (section) {
        case 0: return loc("Pulpit", "Dashboard")
        case 1: return loc("Dodatki Plasma", "Plasma add-ons")
        case 2: return loc("Automatyzacja", "Automation")
        case 3: return loc("Dziennik", "Journal")
        default: return loc("O programie", "About")
        }
    }

    function saveAutomation() {
        const names = []
        const raw = excludedPackages.split(",")
        for (let i = 0; i < raw.length; i++) {
            const name = raw[i].trim()
            if (name.length > 0 && names.indexOf(name) === -1) names.push(name)
        }
        backend.saveSettings(JSON.stringify({
            automatic: automaticEnabled,
            auto_update_tool: updateToolEnabled,
            frequency_hours: updateFrequency,
            restart_plasma: restartPlasma,
            notify_on_success: notifySuccess,
            notify_on_error: notifyError,
            excluded_packages: names
        }), migrationConsent.checked)
    }

    Connections {
        target: backend
        function onRunningChanged() {
            if (backend.running) window.elapsedSeconds = 0
        }
        function onOperationResultChanged() {
            if (!backend.lastOperation.length) return
            const ok = backend.lastOperationSucceeded
            if (ok && backend.lastOperation === "cleanup") {
                window.automationConfigLoaded = false
                window.automationLoadError = window.loc(
                    "Ustawienia zostały usunięte. Zamknij aplikację i usuń jej AppImage, jeśli nie chcesz już z niej korzystać.",
                    "Settings were removed. Close the app and delete its AppImage if you no longer need it.")
                window.automaticEnabled = false
            }
            window.addNotification(
                ok ? "success" : "error",
                (ok ? window.loc("Zakończono", "Completed") : window.loc("Błąd działania", "Action failed"))
                    + " · " + window.actionName(backend.lastOperation),
                ok ? window.loc("Operacja zakończona pomyślnie.", "The operation finished successfully.")
                   : (backend.lastOperationError || window.loc("Szczegóły znajdziesz w dzienniku sesji.",
                                                              "See the session journal for details.")))
        }
        function onDashboardLoaded(json) {
            try { window.dashboard = JSON.parse(json) }
            catch (error) { console.warn("Invalid dashboard data:", error) }
        }
        function onInventoryLoaded(json) {
            try {
                const response = JSON.parse(json)
                window.installedAddons = response.addons
                window.inventoryWarning = response.system_warning || ""
                window.inventoryReady = true
                window.addonView = 0
                if (window.inventoryWarning.length > 0) {
                    window.addNotification("warning",
                        window.loc("Niepełna lista systemowa", "Partial system inventory"),
                        window.loc("Dodatki użytkownika są dostępne; odczyt dodatków systemowych pominięto.",
                                   "User add-ons are available; system-wide add-ons were omitted."))
                }
            } catch (error) { console.warn("Invalid inventory data:", error) }
        }
        function onUpdatesLoaded(json) {
            try {
                const response = JSON.parse(json)
                window.availableUpdates = response.available
                window.updateIssues = response.issues
                window.skippedUpdates = response.skipped
                window.unmatchedUpdates = response.unmatched
                window.updatesReady = true
                window.addonView = 1
                if (window.updateIssues.length > 0) {
                    window.addNotification("warning", window.loc("Niektóre dodatki wymagają uwagi", "Some add-ons need attention"),
                        window.loc("Szczegóły znajdziesz na karcie Dodatki Plasma.", "See the Plasma add-ons page for details."))
                }
            } catch (error) { console.warn("Invalid updates data:", error) }
        }
        function onCleanupPreviewLoaded(json) {
            try {
                window.cleanupPreview = JSON.parse(json)
                removeUserTools.checked = false
                confirmCleanup.open()
            } catch (error) {
                console.warn("Invalid cleanup preview:", error)
            }
        }
        function onSettingsLoaded(json) {
            try {
                const data = JSON.parse(json)
                window.automaticEnabled = data.automatic
                window.updateToolEnabled = data.auto_update_tool
                window.updateFrequency = data.frequency_hours
                window.restartPlasma = data.restart_plasma
                window.notifySuccess = data.notify_on_success
                window.notifyError = data.notify_on_error
                window.excludedPackages = data.excluded_packages.join(", ")
                window.automationConfigLoaded = true
                window.automationLoadError = ""
            } catch (error) {
                window.automationLoadError = String(error)
            }
        }
        function onSettingsSaved() {
            migrationConsent.checked = false
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: backend.running
        onTriggered: window.elapsedSeconds += 1
    }

    Controls.Dialog {
        id: confirmUpdate
        parent: Controls.Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent.width - 32, 480)
        modal: true
        focus: true
        title: window.loc("Zainstalować aktualizacje dodatków?", "Install add-on updates?")
        standardButtons: Controls.Dialog.Ok | Controls.Dialog.Cancel
        onAccepted: backend.runAction("update")
        contentItem: Controls.Label {
            wrapMode: Text.WordWrap
            text: window.loc(
                "Zostaną zaktualizowane dodatki KDE Store bieżącego użytkownika przez plasmoid-updater. Nie zostaną zmienione pakiety systemowe ani uruchomiony ponownie pulpit Plasma. Operacja wymaga zainstalowanego plasmoid-updater.",
                "plasmoid-updater will update KDE Store add-ons for your user. System packages and the Plasma session will not be changed. A working plasmoid-updater installation is required.")
        }
    }

    Controls.Dialog {
        id: confirmInstall
        parent: Controls.Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent.width - 32, 480)
        modal: true
        focus: true
        title: window.loc("Zainstalować aktualizator i jego zależności?", "Install updater and prerequisites?")
        standardButtons: Controls.Dialog.Ok | Controls.Dialog.Cancel
        onAccepted: backend.runAction("install")
        contentItem: Controls.Label {
            wrapMode: Text.WordWrap
            text: window.loc(
                "Program zainstaluje lub sprawdzi plasmoid-updater w ~/.local/bin (SHA-256) i zapewni wymagane bsdtar. Na Bazzite wykorzysta Homebrew w katalogu użytkownika. Na openSUSE, Debianie, Fedorze lub Arch/CachyOS może doinstalować jeden pakiet przez menedżer systemowy, wyświetlając standardowe okno autoryzacji administratora. Nie aktualizuje całego systemu ani nie zmienia harmonogramu.",
                "The app installs or checks plasmoid-updater in ~/.local/bin (SHA-256) and ensures bsdtar. On Bazzite it uses user-local Homebrew. On openSUSE, Debian, Fedora or Arch/CachyOS it may install one system package via the native package manager with a normal graphical administrator prompt. It does not upgrade the entire OS or change your schedule.")
        }
    }

    Controls.Dialog {
        id: confirmCleanup
        parent: Controls.Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent.width - 32, 600)
        modal: true
        focus: true
        title: window.loc("Usunąć zmiany Plasma Addon Manager?", "Remove Plasma Addon Manager changes?")
        standardButtons: Controls.Dialog.Ok | Controls.Dialog.Cancel
        onAccepted: backend.runCleanup(removeUserTools.checked)
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            Controls.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: window.loc(
                    "Zostaną zatrzymane automatyczne aktualizacje i usunięte tylko rozpoznane pliki aplikacji. Sprawdź listę przed potwierdzeniem.",
                    "Automatic updates will be stopped and only recognized app files will be removed. Review the list before confirming.")
            }
            Controls.ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 210
                Controls.Label {
                    width: parent.width
                    wrapMode: Text.WrapAnywhere
                    text: window.cleanupItemsText()
                    font.pixelSize: 12
                }
            }
            Controls.CheckBox {
                id: removeUserTools
                Layout.fillWidth: true
                visible: (window.cleanupPreview.items || []).some(function(item) { return item.optional })
                checked: false
                text: window.loc("Usuń także lokalny plasmoid-updater i dowiązanie bsdtar (mogły istnieć wcześniej)",
                                 "Also remove local plasmoid-updater and bsdtar symlink (they may predate this app)")
            }
            Controls.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.pixelSize: 11
                opacity: 0.8
                text: (window.polish ? window.cleanupPreview.preserved_pl
                                     : window.cleanupPreview.preserved_en).join("\n")
            }
            NoticeBanner {
                Layout.fillWidth: true
                kind: "warning"
                text: window.loc(
                    "Dodatki KDE, pakiety systemowe i kopie migracji pozostaną nietknięte. AppImage lub pakiet aplikacji usuń osobno. Nie da się automatycznie odtworzyć wszystkich zmian wprowadzonych przez starsze wersje.",
                    "KDE add-ons, OS packages and migration backups will remain untouched. Remove the AppImage or app package separately. Not every change made by older versions can be safely reversed.")
            }
        }
    }

    // Reused below the desktop notification panel and at the bottom of the
    // content on narrow windows, where the right column is replaced by a drawer.
    Component {
        id: appIdentityContent
        ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Image {
                    source: "qrc:/images/app.png"
                    sourceSize: Qt.size(96, 96)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    Layout.preferredWidth: 42
                    Layout.preferredHeight: 42
                    Layout.alignment: Qt.AlignTop
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Kirigami.Heading {
                        Layout.fillWidth: true
                        level: 3
                        text: "Plasma Addon Manager"
                        wrapMode: Text.WordWrap
                    }
                    Controls.Label {
                        Layout.fillWidth: true
                        text: window.loc("Menedżer dodatków KDE Plasma 6",
                                         "KDE Plasma 6 add-on manager")
                        wrapMode: Text.WordWrap
                        font.pixelSize: 11
                        opacity: 0.75
                    }
                }
            }
            Controls.Label {
                Layout.fillWidth: true
                font.pixelSize: 11
                opacity: 0.65
                text: window.loc("Wersja 0.4.5 · Bez terminala", "Version 0.4.5 · No terminal")
            }
            RowLayout {
                Layout.fillWidth: true
                Controls.Label {
                    text: window.loc("Język", "Language")
                    font.pixelSize: 12
                }
                Item { Layout.fillWidth: true }
                Controls.ComboBox {
                    objectName: "interfaceLanguageSelector"
                    Layout.preferredWidth: 120
                    model: ["Auto", "Polski", "English"]
                    currentIndex: ["auto", "pl", "en"].indexOf(window.languageChoice)
                    Accessible.name: window.loc("Język interfejsu", "Interface language")
                    onActivated: function(index) {
                        window.languageChoice = ["auto", "pl", "en"][index]
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Controls.Label {
                    text: window.loc("Motyw", "Theme")
                    font.pixelSize: 12
                }
                Item { Layout.fillWidth: true }
                Controls.ComboBox {
                    objectName: "interfaceThemeSelector"
                    Layout.preferredWidth: 120
                    model: ["Auto", window.loc("Jasny", "Light"), window.loc("Ciemny", "Dark")]
                    currentIndex: Math.max(0, ["auto", "light", "dark"].indexOf(themeBridge.choice))
                    Accessible.name: window.loc("Motyw interfejsu", "Interface theme")
                    onActivated: function(index) {
                        if (!themeBridge.setChoice(["auto", "light", "dark"][index])) {
                            console.warn("Cannot activate requested color scheme")
                        }
                    }
                }
            }
        }
    }

    // One reusable notification center: a fixed right column on desktop,
    // and a right-side drawer when the window is narrow.
    Component {
        id: notificationPanelContent
        ColumnLayout {
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Image {
                    objectName: "notificationHeaderIcon"
                    source: "qrc:/images/nav-notifications.png"
                    sourceSize: Qt.size(64, 64)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                }
                Kirigami.Heading {
                    level: 2
                    Layout.fillWidth: true
                    text: window.loc("Powiadomienia", "Notifications")
                }
                Controls.ToolButton {
                    id: clearNotificationsButton
                    objectName: "clearNotificationsButton"
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    Layout.minimumWidth: 32
                    Layout.maximumWidth: 32
                    implicitWidth: 32
                    implicitHeight: 32
                    padding: 4
                    enabled: window.notifications.length > 0
                    display: Controls.AbstractButton.IconOnly
                    contentItem: Item {
                        implicitWidth: 20
                        implicitHeight: 20
                        Image {
                            objectName: "clearNotificationIcon"
                            anchors.centerIn: parent
                            width: 20
                            height: 20
                            source: "qrc:/images/ui-clear.png"
                            sourceSize: Qt.size(64, 64)
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            opacity: clearNotificationsButton.enabled ? 1 : 0.45
                        }
                    }
                    Controls.ToolTip.visible: hovered
                    Controls.ToolTip.text: window.loc("Wyczyść powiadomienia (dziennik zostanie zachowany)",
                                                      "Clear notifications (keep the journal)")
                    Accessible.name: window.loc("Wyczyść powiadomienia", "Clear notifications")
                    onClicked: window.notifications = []
                }
            }

            Controls.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: 0.7
                font.pixelSize: 12
                text: window.loc("Wyniki działań pojawiają się tutaj. Pełna historia pozostaje w dzienniku.",
                                 "Action results appear here. The complete history stays in the journal.")
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Kirigami.Theme.textColor
                opacity: 0.12
            }

            ListView {
                id: notificationList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Kirigami.Units.smallSpacing
                boundsBehavior: Flickable.StopAtBounds
                model: window.notifications

                Controls.Label {
                    anchors.centerIn: parent
                    width: parent.width - 24
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    opacity: 0.65
                    visible: window.notifications.length === 0
                    text: window.loc("Na razie brak powiadomień. Uruchom dowolne działanie.",
                                     "No notifications yet. Start any action.")
                }

                delegate: Rectangle {
                    required property var modelData
                    width: notificationList.width - 10
                    height: Math.max(76, notificationBody.implicitHeight + 22)
                    radius: 10
                    color: window.noticeBackground(modelData.kind)
                    border.color: window.noticeColor(modelData.kind)
                    border.width: 1

                    RowLayout {
                        id: notificationBody
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 11
                        spacing: Kirigami.Units.smallSpacing

                        Image {
                            objectName: "notificationStatusIcon"
                            source: modelData.kind === "success" ? "qrc:/images/ui-success.png"
                                    : modelData.kind === "error" ? "qrc:/images/ui-error.png"
                                    : modelData.kind === "warning" ? "qrc:/images/ui-warning.png"
                                    : "qrc:/images/nav-notifications.png"
                            sourceSize: Qt.size(64, 64)
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            Layout.preferredWidth: 22
                            Layout.preferredHeight: 22
                            Layout.alignment: Qt.AlignTop
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Controls.Label {
                                Layout.fillWidth: true
                                font.bold: true
                                wrapMode: Text.WordWrap
                                textFormat: Text.PlainText
                                color: window.noticeColor(modelData.kind)
                                text: modelData.heading
                            }
                            Controls.Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                textFormat: Text.PlainText
                                font.pixelSize: 12
                                text: modelData.detail
                            }
                            Controls.Label {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignRight
                                font.pixelSize: 11
                                opacity: 0.6
                                text: modelData.time
                            }
                        }
                    }
                }
            }

            Controls.Button {
                Layout.fillWidth: true
                icon.source: "qrc:/images/nav-journal.png"
                text: window.loc("Otwórz pełny dziennik", "Open full journal")
                onClicked: {
                    window.section = 3
                    notificationDrawer.close()
                }
            }
        }
    }

    Controls.Drawer {
        id: notificationDrawer
        parent: Controls.Overlay.overlay
        edge: Qt.RightEdge
        width: Math.min(window.width - 40, 340)
        height: window.height
        modal: true
        Loader {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            sourceComponent: notificationPanelContent
        }
    }

    footer: Controls.ToolBar {
        padding: Kirigami.Units.smallSpacing
        background: Rectangle {
            color: Kirigami.Theme.backgroundColor
            Rectangle {
                objectName: "statusSeparator"
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 1
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                               Kirigami.Theme.textColor.b, 0.25)
            }
        }
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                Rectangle {
                    Layout.preferredWidth: 4
                    Layout.preferredHeight: 36
                    radius: 2
                    color: backend.running ? Kirigami.Theme.highlightColor
                           : !backend.lastOperation.length ? Kirigami.Theme.textColor
                           : backend.lastOperationSucceeded ? Kirigami.Theme.positiveTextColor
                           : Kirigami.Theme.negativeTextColor
                }

                Controls.BusyIndicator {
                    running: backend.running
                    visible: running
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Controls.Label {
                        Layout.fillWidth: true
                        font.bold: true
                        elide: Text.ElideRight
                        text: backend.running
                              ? window.loc("Trwa: ", "Running: ") + window.actionName(backend.currentAction)
                              : !backend.lastOperation.length
                                ? window.loc("Gotowy do pracy", "Ready to go")
                                : (backend.lastOperationSucceeded
                                   ? window.loc("✓ Zakończono: ", "✓ Completed: ")
                                   : window.loc("✗ Błąd: ", "✗ Failed: "))
                                   + window.actionName(backend.lastOperation)
                    }
                    Controls.Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        opacity: 0.75
                        font.pixelSize: 12
                        text: backend.running
                              ? (backend.progressDetail.length > 0 ? backend.progressDetail
                                 : window.loc("Czekaj, operacja jest wykonywana…", "Please wait, the action is running…"))
                                + "  ·  " + window.elapsedLabel()
                              : window.loc("Szczegóły i wszystkie działania znajdziesz w dzienniku sesji.",
                                           "Details and all actions are available in the session journal.")
                    }
                }

                Controls.Button {
                    visible: backend.running
                    icon.source: "qrc:/images/ui-error.png"
                    text: window.loc("Anuluj", "Cancel")
                    onClicked: backend.cancel()
                }
            }

            Controls.ProgressBar {
                id: operationProgress
                Layout.fillWidth: true
                Layout.preferredHeight: 9
                from: 0
                to: 1
                // The helper does not publish percentages. Animate while
                // running and show completion only after its exit status.
                indeterminate: backend.running
                value: backend.running ? 0 : (backend.lastOperation.length > 0 ? 1 : 0)
                palette.highlight: backend.running ? Kirigami.Theme.highlightColor
                                   : backend.lastOperationSucceeded ? Kirigami.Theme.positiveTextColor
                                   : Kirigami.Theme.negativeTextColor
                Accessible.name: backend.running
                                 ? window.loc("Trwa operacja", "Operation in progress")
                                 : window.loc("Stan ostatniego działania", "Last action status")
            }
        }
    }

    pageStack.initialPage: Kirigami.Page {
        title: window.currentSection
        padding: 0

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // Navigation belongs to the fixed window shell, not to the
            // Flickable. Long pages (especially About) scroll beneath it.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 0
                Layout.minimumWidth: 0
                spacing: 0

            Rectangle {
                objectName: "horizontalNavigation"
                Layout.fillWidth: true
                Layout.preferredHeight: 82
                Layout.margins: Kirigami.Units.largeSpacing
                radius: 12
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                               Kirigami.Theme.textColor.b, 0.035)
                border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                      Kirigami.Theme.textColor.b, 0.10)

                Row {
                    id: navRow
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 6
                    readonly property int tileCount: window.showNotificationSidebar ? 5 : 6
                    readonly property real tileWidth: (width - spacing * (tileCount - 1)) / tileCount

                    NavTile {
                        objectName: "navDashboard"
                        width: navRow.tileWidth
                        height: navRow.height
                        text: window.loc("Pulpit", "Dashboard")
                        imageSource: "qrc:/images/nav-dashboard.png"
                        selected: window.section === 0
                        onClicked: window.section = 0
                    }
                    NavTile {
                        objectName: "navAddons"
                        width: navRow.tileWidth
                        height: navRow.height
                        text: window.loc("Dodatki Plasma", "Plasma add-ons")
                        imageSource: "qrc:/images/nav-addons.png"
                        selected: window.section === 1
                        onClicked: window.section = 1
                    }
                    NavTile {
                        objectName: "navAutomation"
                        width: navRow.tileWidth
                        height: navRow.height
                        text: window.loc("Automatyzacja", "Automation")
                        imageSource: "qrc:/images/nav-automation.png"
                        selected: window.section === 2
                        onClicked: window.section = 2
                    }
                    NavTile {
                        objectName: "navJournal"
                        width: navRow.tileWidth
                        height: navRow.height
                        text: window.loc("Dziennik", "Journal")
                        imageSource: "qrc:/images/nav-journal.png"
                        selected: window.section === 3
                        onClicked: window.section = 3
                    }
                    NavTile {
                        objectName: "navAbout"
                        width: navRow.tileWidth
                        height: navRow.height
                        text: window.loc("O programie", "About")
                        imageSource: "qrc:/images/nav-about.png"
                        selected: window.section === 4
                        onClicked: window.section = 4
                    }
                    NavTile {
                        visible: !window.showNotificationSidebar
                        width: navRow.tileWidth
                        height: navRow.height
                        text: window.loc("Alerty", "Alerts")
                              + (window.notifications.length ? " (" + window.notifications.length + ")" : "")
                        imageSource: "qrc:/images/nav-notifications.png"
                        selected: false
                        onClicked: notificationDrawer.open()
                    }
                }
            }

            Controls.ScrollView {
                id: mainScroll
                objectName: "mainContentScroll"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 0
                Layout.minimumWidth: 0
                clip: true
                leftPadding: Kirigami.Units.largeSpacing
                rightPadding: Kirigami.Units.largeSpacing
                topPadding: 0
                bottomPadding: Kirigami.Units.largeSpacing
                Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
                Controls.ScrollBar.vertical.policy: Controls.ScrollBar.AlwaysOn

                ColumnLayout {
                    width: mainScroll.availableWidth
                    spacing: Kirigami.Units.largeSpacing

            NoticeBanner {
                Layout.fillWidth: true
                visible: window.section <= 2 && window.bsdtarMissing
                kind: "warning"
                text: window.loc("Brakuje bsdtar. Przejdź do Pulpitu i kliknij «Zainstaluj / sprawdź wersję». Program doinstaluje potrzebną zależność razem z aktualizatorem; na niektórych dystrybucjach poprosi o autoryzację administratora.",
                                 "bsdtar is missing. Open Dashboard and choose Install / check version. The app will install the required utility as part of the same action; some distributions require graphical administrator authorization.")
            }

            Controls.Frame {
                visible: window.section === 0
                Layout.fillWidth: true
                padding: Kirigami.Units.largeSpacing
                background: Rectangle {
                    color: window.noticeBackground("info")
                    border.color: Kirigami.Theme.highlightColor
                    border.width: 1
                    radius: 12
                }

                ColumnLayout {
                    width: parent.width
                    spacing: Kirigami.Units.largeSpacing

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.largeSpacing
                        Image {
                            objectName: "dashboardStatusIcon"
                            source: window.dashboard.updater_version && !window.bsdtarMissing
                                    ? "qrc:/images/ui-success.png" : "qrc:/images/ui-warning.png"
                            sourceSize: Qt.size(64, 64)
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Kirigami.Heading {
                                level: 2
                                Layout.fillWidth: true
                                text: window.dashboard.updater_version && !window.bsdtarMissing
                                      ? window.loc("Wszystko gotowe do aktualizacji", "Ready to check for updates")
                                      : window.loc("Przygotuj menedżer dodatków", "Set up the add-on manager")
                            }
                            Controls.Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: window.dashboard.updater_version && !window.bsdtarMissing
                                      ? window.loc("Twoje narzędzia są gotowe. Sprawdź nowe wersje dodatków KDE Store.",
                                                   "Your tools are ready. Check KDE Store add-ons for new versions.")
                                      : window.loc("Jednym przyciskiem przygotujesz plasmoid-updater i potrzebne zależności.",
                                                   "Prepare plasmoid-updater and its prerequisites in one step.")
                            }
                        }
                    }
                    Controls.Button {
                        highlighted: true
                        enabled: !backend.running
                        icon.source: window.dashboard.updater_version && !window.bsdtarMissing
                                     ? "qrc:/images/ui-refresh.png" : "qrc:/images/nav-addons.png"
                        text: window.dashboard.updater_version && !window.bsdtarMissing
                              ? window.loc("Sprawdź aktualizacje", "Check for updates")
                              : window.loc("Przygotuj narzędzia…", "Set up tools…")
                        onClicked: {
                            if (window.dashboard.updater_version && !window.bsdtarMissing) {
                                window.section = 1
                                backend.runAction("updates-json")
                            } else {
                                confirmInstall.open()
                            }
                        }
                    }
                }
            }

            GridLayout {
                visible: window.section === 0
                Layout.fillWidth: true
                columns: width > 760 ? 4 : 2
                rowSpacing: Kirigami.Units.smallSpacing
                columnSpacing: Kirigami.Units.smallSpacing

                Controls.Frame {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    Layout.minimumWidth: 0
                    ColumnLayout {
                        width: parent.width
                        RowLayout {
                            Image { objectName: "systemStatusIcon"; source: "qrc:/images/nav-dashboard.png"; sourceSize: Qt.size(64, 64); fillMode: Image.PreserveAspectFit; Layout.preferredWidth: 20; Layout.preferredHeight: 20 }
                            Kirigami.Heading { Layout.fillWidth: true; level: 3; wrapMode: Text.WordWrap; text: window.loc("System", "System") }
                        }
                        Controls.Label {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: window.dashboard.distribution || window.loc("Sprawdzanie…", "Checking…")
                        }
                    }
                }
                Controls.Frame {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    Layout.minimumWidth: 0
                    ColumnLayout {
                        width: parent.width
                        RowLayout {
                            Image { objectName: "updaterStatusIcon"; source: "qrc:/images/nav-addons.png"; sourceSize: Qt.size(64, 64); fillMode: Image.PreserveAspectFit; Layout.preferredWidth: 20; Layout.preferredHeight: 20 }
                            Kirigami.Heading { Layout.fillWidth: true; level: 3; wrapMode: Text.WrapAnywhere; text: "plasmoid-updater" }
                        }
                        Controls.Label {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: window.dashboard.updater_version
                                  ? "✓ v" + window.dashboard.updater_version
                                  : window.loc("✕ Nie zainstalowano", "✕ Not installed")
                            color: window.dashboard.updater_version
                                   ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                        }
                    }
                }
                Controls.Frame {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    Layout.minimumWidth: 0
                    ColumnLayout {
                        width: parent.width
                        RowLayout {
                            Image { objectName: "agentStatusIcon"; source: "qrc:/images/nav-automation.png"; sourceSize: Qt.size(64, 64); fillMode: Image.PreserveAspectFit; Layout.preferredWidth: 20; Layout.preferredHeight: 20 }
                            Kirigami.Heading { Layout.fillWidth: true; level: 3; wrapMode: Text.WordWrap; text: window.loc("Agent", "Agent") }
                        }
                        Controls.Label {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: window.dashboard.agent_needs_repair
                                  ? window.loc("! Wymaga naprawy", "! Repair needed")
                                  : window.dashboard.agent_version
                                    ? "✓ v" + window.dashboard.agent_version
                                    : window.loc("✕ Brak agenta", "✕ Agent missing")
                            color: window.dashboard.agent_version && !window.dashboard.agent_needs_repair
                                   ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                        }
                    }
                }
                Controls.Frame {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    Layout.minimumWidth: 0
                    ColumnLayout {
                        width: parent.width
                        RowLayout {
                            Image { objectName: "timerStatusIcon"; source: "qrc:/images/nav-automation.png"; sourceSize: Qt.size(64, 64); fillMode: Image.PreserveAspectFit; Layout.preferredWidth: 20; Layout.preferredHeight: 20 }
                            Kirigami.Heading { Layout.fillWidth: true; level: 3; wrapMode: Text.WordWrap; text: window.loc("Harmonogram", "Schedule") }
                        }
                        Controls.Label {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: window.dashboard.last_failed
                                  ? window.loc("! Ostatni cykl nieudany", "! Last cycle failed")
                                  : window.dashboard.timer_active
                                    ? window.loc("✓ Aktywny", "✓ Active")
                                    : window.loc("Nieaktywny", "Inactive")
                            color: window.dashboard.last_failed ? Kirigami.Theme.negativeTextColor
                                   : window.dashboard.timer_active ? Kirigami.Theme.positiveTextColor
                                   : Kirigami.Theme.textColor
                        }
                    }
                }
            }

            NoticeBanner {
                visible: window.section === 0 && window.dashboard.agent_needs_repair === true
                Layout.fillWidth: true
                kind: "warning"
                text: window.loc("Wykryto nieaktualnego lub uszkodzonego agenta. Możesz naprawić go jednym przyciskiem.",
                                 "The update agent is outdated or broken. You can repair it with one click.")
            }
            RowLayout {
                visible: window.section === 0
                Layout.fillWidth: true
                Controls.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: window.loc("Następna aktualizacja: ", "Next update: ")
                          + (window.dashboard.next_run || "—")
                }
                Controls.Button {
                    text: window.loc("Odśwież stan", "Refresh status")
                    icon.source: "qrc:/images/ui-refresh.png"
                    enabled: !backend.running
                    onClicked: backend.runAction("status-json")
                }
                Controls.Button {
                    visible: window.dashboard.agent_needs_repair === true
                    text: window.loc("Napraw agenta", "Repair agent")
                    enabled: !backend.running
                    onClicked: backend.runAction("repair-agent")
                }
            }

            GridLayout {
                visible: window.section === 0
                Layout.fillWidth: true
                columns: width > 720 ? 2 : 1
                columnSpacing: Kirigami.Units.largeSpacing
                rowSpacing: Kirigami.Units.largeSpacing

                Controls.Frame {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    Layout.minimumWidth: 0
                    ColumnLayout {
                        width: parent.width
                        spacing: Kirigami.Units.smallSpacing
                        Kirigami.Heading {
                            text: window.loc("Stan środowiska", "Environment status")
                            level: 2
                        }
                        Controls.Label {
                            text: window.loc("Sprawdź dystrybucję, Plasma 6 i wymagane narzędzia.",
                                             "Check your distribution, Plasma 6 and prerequisites.")
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                        Controls.Button {
                            text: window.loc("Sprawdź środowisko", "Run diagnostics")
                            icon.source: "qrc:/images/nav-dashboard.png"
                            enabled: !backend.running
                            onClicked: backend.runAction("diagnose")
                        }
                    }
                }
                Controls.Frame {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    Layout.minimumWidth: 0
                    ColumnLayout {
                        width: parent.width
                        spacing: Kirigami.Units.smallSpacing
                        Kirigami.Heading {
                            text: window.loc("Sprawdź aktualizacje", "Check for updates")
                            level: 2
                        }
                        Controls.Label {
                            text: window.loc("Wyszukaj dostępne aktualizacje bez ich instalowania.",
                                             "Find available updates without installing them.")
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                        Controls.Button {
                            text: window.loc("Sprawdź dostępność", "Check availability")
                            icon.source: "qrc:/images/ui-refresh.png"
                            enabled: !backend.running && !window.bsdtarMissing
                            onClicked: {
                                window.section = 1
                                backend.runAction("updates-json")
                            }
                        }
                    }
                }
            }

            Controls.Frame {
                visible: window.section === 0
                Layout.fillWidth: true
                ColumnLayout {
                    width: parent.width
                    spacing: Kirigami.Units.smallSpacing
                    Kirigami.Heading {
                        text: window.loc("Instalacja narzędzia", "Install the updater")
                        level: 2
                    }
                    Controls.Label {
                        text: window.loc("Zainstaluj lub sprawdź plasmoid-updater oraz wymagane bsdtar jednym przyciskiem. Bez terminala; system może poprosić o zgodę administratora na doinstalowanie pakietu.",
                                         "Install or check plasmoid-updater and the required bsdtar utility with one button. No terminal; your OS may ask for administrator authorization to install the prerequisite package.")
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Controls.Button {
                        text: window.loc("Zainstaluj / sprawdź wersję…", "Install / check version…")
                        icon.source: "qrc:/images/nav-addons.png"
                        enabled: !backend.running
                        onClicked: confirmInstall.open()
                    }
                }
            }

            Controls.Frame {
                objectName: "cleanupDashboardFrame"
                visible: window.section === 0
                Layout.fillWidth: true
                ColumnLayout {
                    width: parent.width
                    spacing: Kirigami.Units.smallSpacing
                    Kirigami.Heading {
                        level: 3
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: window.loc("Usuń instalacje i zmiany programu", "Remove application installations and changes")
                    }
                    Controls.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: window.loc(
                            "Wyłącz harmonogram i usuń pliki utworzone przez Plasma Addon Manager. Przed usunięciem sprawdzisz dokładną listę i zdecydujesz, czy uwzględnić także współdzielone narzędzia.",
                            "Disable the schedule and remove Plasma Addon Manager files. Review the exact items and optionally include shared tools before confirming.")
                    }
                    Controls.Button {
                        objectName: "cleanupButton"
                        text: window.loc("Usuń instalacje i zmiany…", "Remove installations and changes…")
                        icon.source: "qrc:/images/ui-error.png"
                        enabled: !backend.running
                        onClicked: backend.runAction("cleanup-preview")
                    }
                }
            }

            Controls.Frame {
                objectName: "addonsSectionFrame"
                visible: window.section === 1
                Layout.fillWidth: true
                ColumnLayout {
                    objectName: "addonsSectionLayout"
                    width: parent.width
                    spacing: Kirigami.Units.largeSpacing
                    Kirigami.Heading {
                        text: window.loc("Dodatki KDE Store", "KDE Store add-ons")
                        level: 2
                    }
                    Controls.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: window.loc("Sprawdź dodatki, zasymuluj lub ręcznie zastosuj aktualizacje. Zmiany wymagają potwierdzenia.",
                                         "Inspect add-ons, preview or manually install updates. Changes require confirmation.")
                    }
                    Row {
                        id: addonsActionRow
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        readonly property real buttonWidth: (width - spacing * 3) / 4
                        Controls.Button {
                            objectName: "actionInstalled"
                            width: addonsActionRow.buttonWidth
                            icon.source: "qrc:/images/nav-addons.png"
                            icon.width: 16
                            icon.height: 16
                            text: window.loc("Zainstalowane dodatki", "Installed add-ons")
                            Controls.ToolTip.text: text
                            Controls.ToolTip.visible: hovered
                            enabled: !backend.running
                            onClicked: backend.runAction("inventory-json")
                        }
                        Controls.Button {
                            objectName: "actionUpdates"
                            width: addonsActionRow.buttonWidth
                            icon.source: "qrc:/images/ui-refresh.png"
                            icon.width: 16
                            icon.height: 16
                            text: window.loc("Dostępne aktualizacje", "Available updates")
                            Controls.ToolTip.text: text
                            Controls.ToolTip.visible: hovered
                            enabled: !backend.running && !window.bsdtarMissing
                            onClicked: backend.runAction("updates-json")
                        }
                        Controls.Button {
                            objectName: "actionPreview"
                            width: addonsActionRow.buttonWidth
                            icon.source: "qrc:/images/nav-automation.png"
                            icon.width: 16
                            icon.height: 16
                            text: window.loc("Symulacja aktualizacji", "Preview update")
                            Controls.ToolTip.text: text
                            Controls.ToolTip.visible: hovered
                            enabled: !backend.running && !window.bsdtarMissing
                            onClicked: backend.runAction("dry-run")
                        }
                        Controls.Button {
                            objectName: "actionApply"
                            width: addonsActionRow.buttonWidth
                            icon.source: "qrc:/images/ui-success.png"
                            icon.width: 16
                            icon.height: 16
                            text: window.loc("Aktualizuj dodatki…", "Update add-ons…")
                            Controls.ToolTip.text: text
                            Controls.ToolTip.visible: hovered
                            enabled: !backend.running && !window.bsdtarMissing
                            onClicked: confirmUpdate.open()
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Controls.Button {
                            text: window.loc("Zainstalowane", "Installed")
                            checkable: true
                            checked: window.addonView === 0
                            onClicked: window.addonView = 0
                        }
                        Controls.Button {
                            text: window.loc("Aktualizacje", "Updates")
                            checkable: true
                            checked: window.addonView === 1
                            onClicked: window.addonView = 1
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Controls.Label {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: window.addonView === 0
                                  ? window.inventoryReady
                                    ? window.loc("Znaleziono dodatków: ", "Installed add-ons: ") + window.installedAddons.length
                                    : window.loc("Kliknij «Zainstalowane dodatki», aby wczytać listę.", "Click Installed add-ons to load the list.")
                                  : window.updatesReady
                                    ? window.loc("Dostępne aktualizacje: ", "Available updates: ") + window.availableUpdates.length
                                      + window.loc(" · Pominięte: ", " · Skipped: ") + window.skippedUpdates
                                    : window.loc("Kliknij «Dostępne aktualizacje», aby sprawdzić KDE Store.", "Click Available updates to check KDE Store.")
                        }
                        Controls.ToolButton {
                            objectName: "toggleAddonList"
                            text: window.addonListExpanded
                                  ? window.loc("Zwiń listę", "Collapse list")
                                  : window.loc("Rozwiń listę", "Expand list")
                            onClicked: window.addonListExpanded = !window.addonListExpanded
                        }
                    }
                    NoticeBanner {
                        Layout.fillWidth: true
                        visible: window.inventoryReady && window.inventoryWarning.length > 0 && window.addonView === 0
                        kind: "information"
                        text: window.loc("Wyświetlono dodatki użytkownika. Dodatki systemowe pominięto, ponieważ nie można ich bezpiecznie odczytać bez dodatkowych uprawnień.",
                                         "User add-ons are shown. System add-ons were omitted because they cannot be read safely without additional permissions.")
                    }
                    // Keep the action row above a bounded, independently
                    // scrollable list. A large inventory no longer pushes
                    // update controls out of view or grows the whole page.
                    Controls.ScrollView {
                        id: addonItemsScroll
                        objectName: "addonItemsScroll"
                        Layout.fillWidth: true
                        // Also account for the visible page height, so the
                        // fixed action controls remain above the inner list.
                        Layout.preferredHeight: Math.min(328,
                                                         Math.max(96, mainScroll.height - 265),
                                                         Math.max(88, addonItemsContent.implicitHeight + 12))
                        visible: window.addonListExpanded
                        clip: true
                        Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
                        Controls.ScrollBar.vertical.policy: Controls.ScrollBar.AsNeeded

                        ColumnLayout {
                            id: addonItemsContent
                            objectName: "addonItemsContent"
                            width: addonItemsScroll.availableWidth
                            spacing: Kirigami.Units.smallSpacing

                            Repeater {
                                objectName: "addonItemsRepeater"
                                model: window.addonView === 0 ? window.installedAddons : window.availableUpdates
                                delegate: Controls.Frame {
                                    id: addonFrame
                                    Layout.fillWidth: true
                                    // Resolve both the inventory and update data shapes.
                                    readonly property var addon: modelData && modelData.installed
                                                                 ? modelData.installed : modelData
                                    ColumnLayout {
                                        width: parent.width
                                        spacing: Kirigami.Units.smallSpacing
                                        Controls.Label {
                                            Layout.fillWidth: true
                                            wrapMode: Text.WrapAnywhere
                                            font.bold: true
                                            text: addonFrame.addon ? addonFrame.addon.name : ""
                                        }
                                        Controls.Label {
                                            Layout.fillWidth: true
                                            wrapMode: Text.WordWrap
                                            opacity: 0.75
                                            text: addonFrame.addon ? addonFrame.addon.component_type
                                                  + (addonFrame.addon.is_system
                                                     ? window.loc(" · Systemowy (tylko odczyt)", " · System (read-only)")
                                                     : window.loc(" · Użytkownik", " · User")) : ""
                                        }
                                        Controls.Label {
                                            Layout.fillWidth: true
                                            wrapMode: Text.WrapAnywhere
                                            text: !addonFrame.addon ? "" : window.addonView === 0
                                                  ? window.loc("Wersja: ", "Version: ") + addonFrame.addon.version
                                                  : addonFrame.addon.version + "  →  " + (modelData.latest_version || "—")
                                        }
                                    }
                                }
                            }
                            Repeater {
                                model: window.addonView === 1 ? window.updateIssues : []
                                delegate: NoticeBanner {
                                    Layout.fillWidth: true
                                    visible: true
                                    kind: "warning"
                                    text: modelData.name + ": " + modelData.reason
                                }
                            }
                            Controls.Label {
                                visible: window.addonView === 0
                                         ? window.inventoryReady && window.installedAddons.length === 0
                                         : window.updatesReady && window.availableUpdates.length === 0
                                            && window.updateIssues.length === 0
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: window.addonView === 0
                                      ? window.loc("Nie znaleziono dodatków.", "No installed add-ons found.")
                                      : window.loc("Wszystkie dodatki są aktualne.", "All add-ons are up to date.")
                            }
                        }
                    }
                }
            }

            Controls.Frame {
                visible: window.section === 2
                Layout.fillWidth: true
                ColumnLayout {
                    width: parent.width
                    spacing: Kirigami.Units.largeSpacing
                    Kirigami.Heading {
                        text: window.loc("Automatyczne aktualizacje", "Automatic updates")
                        level: 2
                    }
                    NoticeBanner {
                        Layout.fillWidth: true
                        visible: !window.automationConfigLoaded
                        kind: "warning"
                        text: window.automationLoadError.length > 0 ? window.automationLoadError
                              : window.loc("Wczytywanie ustawień automatyzacji…", "Loading automation settings…")
                    }
                    Controls.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: window.loc("Agent działa bez otwierania programu. Dodatki użytkownika są aktualizowane przez systemd --user, niezależnie od menedżera pakietów systemowych.",
                                         "The background agent runs without opening the GUI. It updates your KDE Store add-ons through systemd --user, independently of OS package updates.")
                    }
                    Controls.CheckBox {
                        text: window.loc("Włącz automatyczne aktualizacje", "Enable automatic updates")
                        checked: window.automaticEnabled
                        enabled: window.automationConfigLoaded && !backend.running
                        onToggled: window.automaticEnabled = checked
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Controls.Label { text: window.loc("Częstotliwość:", "Frequency:") }
                        Controls.ComboBox {
                            model: ["6 h", "12 h", "24 h"]
                            currentIndex: [6, 12, 24].indexOf(window.updateFrequency)
                            enabled: window.automationConfigLoaded && !backend.running && window.automaticEnabled
                            onActivated: function(index) { window.updateFrequency = [6, 12, 24][index] }
                        }
                    }
                    Controls.CheckBox {
                        text: window.loc("Aktualizuj także plasmoid-updater", "Also update the plasmoid-updater tool")
                        checked: window.updateToolEnabled
                        enabled: window.automationConfigLoaded && !backend.running && window.automaticEnabled
                        onToggled: window.updateToolEnabled = checked
                    }
                    Controls.CheckBox {
                        text: window.loc("Restartuj Plasma po aktualizacji (opcjonalnie)", "Restart Plasma after updating (optional)")
                        checked: window.restartPlasma
                        enabled: window.automationConfigLoaded && !backend.running && window.automaticEnabled
                        onToggled: window.restartPlasma = checked
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.largeSpacing
                        Controls.CheckBox {
                            text: window.loc("Powiadom o sukcesie", "Notify on success")
                            checked: window.notifySuccess
                            enabled: window.automationConfigLoaded && !backend.running
                            onToggled: window.notifySuccess = checked
                        }
                        Controls.CheckBox {
                            text: window.loc("Powiadom o błędzie", "Notify on error")
                            checked: window.notifyError
                            enabled: window.automationConfigLoaded && !backend.running
                            onToggled: window.notifyError = checked
                        }
                    }
                    Controls.Label {
                        Layout.fillWidth: true
                        text: window.loc("Wykluczone dodatki (oddziel przecinkami)", "Excluded add-ons (comma separated)")
                    }
                    Controls.TextField {
                        Layout.fillWidth: true
                        enabled: window.automationConfigLoaded && !backend.running
                        placeholderText: "weather, clock"
                        text: window.excludedPackages
                        onTextChanged: window.excludedPackages = text
                    }
                    NoticeBanner {
                        Layout.fillWidth: true
                        visible: true
                        kind: "warning"
                        text: window.loc("Jeśli masz harmonogram z wcześniejszego programu Bazzite/Debian, domyślnie pozostanie nietknięty. Przejęcie wymaga zaznaczenia poniższej zgody; stare jednostki zostaną zachowane w kopii.",
                                         "An older Bazzite/Debian schedule is preserved by default. Taking it over requires the checkbox below; existing unit files will be backed up.")
                    }
                    Controls.CheckBox {
                        id: migrationConsent
                        text: window.loc("Zgadzam się przejąć starszy harmonogram (z kopią zapasową)",
                                         "I agree to migrate an older schedule (with backup)")
                        checked: false
                        enabled: window.automationConfigLoaded && !backend.running
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        Controls.Button {
                            text: window.loc("Zapisz i zastosuj", "Save and apply")
                            icon.source: "qrc:/images/ui-success.png"
                            enabled: window.automationConfigLoaded && !backend.running && !window.bsdtarMissing
                            onClicked: window.saveAutomation()
                        }
                        Controls.Button {
                            text: window.loc("Pokaż stan timera", "Show timer status")
                            icon.source: "qrc:/images/nav-automation.png"
                            enabled: !backend.running
                            onClicked: backend.runAction("timer")
                        }
                        Controls.Button {
                            text: window.loc("Uruchom teraz", "Run now")
                            icon.source: "qrc:/images/ui-success.png"
                            enabled: !backend.running && window.dashboard.agent_managed === true
                            onClicked: backend.runAction("run-service")
                        }
                        Controls.Button {
                            text: window.loc("Napraw agenta", "Repair agent")
                            icon.source: "qrc:/images/ui-refresh.png"
                            enabled: !backend.running && window.dashboard.agent_managed === true
                            onClicked: backend.runAction("repair-agent")
                        }
                        Controls.Button {
                            text: window.loc("Testuj zapisaną konfigurację", "Test saved configuration")
                            icon.source: "qrc:/images/nav-dashboard.png"
                            enabled: !backend.running && window.dashboard.automatic_configured === true
                                     && !window.bsdtarMissing
                            onClicked: backend.runAction("test-config")
                        }
                    }
                }
            }

            Controls.Frame {
                objectName: "journalSectionFrame"
                visible: window.section === 3
                Layout.fillWidth: true
                ColumnLayout {
                    objectName: "journalSectionLayout"
                    width: parent.width
                    spacing: Kirigami.Units.largeSpacing
                    Kirigami.Heading {
                        text: window.loc("Dziennik bieżącej sesji", "Current session log")
                        level: 2
                    }
                    Controls.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: window.loc(
                            "Wszystkie operacje i ich wyniki od uruchomienia aplikacji. Wpisy pozostają na liście podczas przechodzenia między ekranami oraz wykonywania następnych działań.",
                            "Every action and its result since the app was launched. Entries remain visible when switching pages and running new operations.")
                    }
                    Controls.Button {
                        text: window.loc("Dołącz historię agenta systemd", "Append systemd agent history")
                        icon.source: "qrc:/images/nav-journal.png"
                        enabled: !backend.running
                        onClicked: backend.runAction("journal")
                    }
                    Controls.ScrollView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 430
                        Controls.TextArea {
                            text: backend.output
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.WrapAnywhere
                            font.family: "monospace"
                            font.pixelSize: 12
                        }
                    }
                }
            }

            AboutPage {
                visible: window.section === 4
                Layout.fillWidth: true
                Layout.maximumWidth: 840
                Layout.alignment: Qt.AlignHCenter
                polish: window.polish
            }

            Controls.Frame {
                visible: !window.showNotificationSidebar
                Layout.fillWidth: true
                Layout.preferredHeight: 194
                padding: Kirigami.Units.largeSpacing
                Loader {
                    anchors.fill: parent
                    sourceComponent: appIdentityContent
                }
            }

                }
            }
            }

            Rectangle {
                visible: window.showNotificationSidebar
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                color: Kirigami.Theme.textColor
                opacity: 0.12
            }

            ColumnLayout {
                objectName: "notificationSidebar"
                visible: window.showNotificationSidebar
                Layout.preferredWidth: 304
                Layout.minimumWidth: 304
                Layout.maximumWidth: 304
                Layout.fillHeight: true
                Layout.margins: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing

                Controls.Frame {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    padding: Kirigami.Units.largeSpacing
                    Loader {
                        anchors.fill: parent
                        sourceComponent: notificationPanelContent
                    }
                }
                Controls.Frame {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 194
                    padding: Kirigami.Units.largeSpacing
                    Loader {
                        anchors.fill: parent
                        sourceComponent: appIdentityContent
                    }
                }
            }
        }
    }
}
