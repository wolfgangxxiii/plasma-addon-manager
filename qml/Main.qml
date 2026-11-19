import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: window
    width: 1080
    height: 740
    minimumWidth: 640
    minimumHeight: 500
    title: "Plasma Addon Manager"

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
    property int skippedUpdates: 0
    property int unmatchedUpdates: 0
    property int addonView: 0
    property bool inventoryReady: false
    property bool updatesReady: false
    readonly property bool bsdtarMissing: dashboard.bsdtar_available === false
    function isOpenSuse() {
        return (dashboard.distribution || "").toLowerCase().startsWith("opensuse")
    }
    readonly property bool polish: languageChoice === "pl"
                                   || (languageChoice === "auto"
                                       && Qt.locale().name.toLowerCase().startsWith("pl"))
    function loc(pl, en) { return polish ? pl : en }
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
            } catch (error) { console.warn("Invalid updates data:", error) }
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
        title: window.loc("Zainstalować plasmoid-updater?", "Install plasmoid-updater?")
        standardButtons: Controls.Dialog.Ok | Controls.Dialog.Cancel
        onAccepted: backend.runAction("install")
        contentItem: Controls.Label {
            wrapMode: Text.WordWrap
            text: window.loc(
                "Program pobierze oryginalny plasmoid-updater z GitHub, zweryfikuje SHA-256 i zainstaluje go w ~/.local/bin. Na Bazzite w razie potrzeby doinstaluje też libarchive przez Homebrew w katalogu użytkownika. Obraz Bazzite i harmonogram systemd pozostaną bez zmian.",
                "The app downloads plasmoid-updater from GitHub, verifies SHA-256, and installs it to ~/.local/bin. On Bazzite it can also install libarchive via user-local Homebrew if needed. The OS image and systemd schedule remain unchanged.")
        }
    }

    globalDrawer: Kirigami.GlobalDrawer {
        title: "Plasma Addon Manager"
        titleIcon: "preferences-desktop-plasma"
        actions: [
            Kirigami.Action {
                text: window.loc("Pulpit", "Dashboard")
                icon.name: "view-dashboard"
                onTriggered: window.section = 0
            },
            Kirigami.Action {
                text: window.loc("Dodatki Plasma", "Plasma add-ons")
                icon.name: "preferences-desktop-plasma"
                onTriggered: window.section = 1
            },
            Kirigami.Action {
                text: window.loc("Automatyzacja", "Automation")
                icon.name: "chronometer"
                onTriggered: window.section = 2
            },
            Kirigami.Action {
                text: window.loc("Dziennik", "Journal")
                icon.name: "view-list-text"
                onTriggered: window.section = 3
            },
            Kirigami.Action {
                text: window.loc("O programie", "About")
                icon.name: "help-about"
                onTriggered: window.section = 4
            }
        ]
    }

    pageStack.initialPage: Kirigami.ScrollablePage {
        title: window.currentSection

        ColumnLayout {
            width: parent.width
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Icon {
                    source: "preferences-desktop-plasma"
                    Layout.preferredWidth: 46
                    Layout.preferredHeight: 46
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Kirigami.Heading {
                        text: "Plasma Addon Manager"
                        level: 1
                        Layout.fillWidth: true
                    }
                    Controls.Label {
                        text: window.loc("Uniwersalny menedżer dodatków KDE Plasma 6",
                                         "Universal KDE Plasma 6 add-on manager")
                        wrapMode: Text.WordWrap
                        opacity: 0.75
                        Layout.fillWidth: true
                    }
                }
                Controls.ComboBox {
                    id: languageSelector
                    model: ["Auto", "Polski", "English"]
                    implicitWidth: 115
                    Accessible.name: window.loc("Język interfejsu", "Interface language")
                    onActivated: function(index) {
                        window.languageChoice = ["auto", "pl", "en"][index]
                    }
                }
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: true
                type: Kirigami.MessageType.Information
                text: window.loc(
                    "Wersja 0.4.2: poprawki zgodności z openSUSE, diagnostyka brakujących narzędzi i bezpieczny odczyt dodatków systemowych.",
                    "Version 0.4.2: openSUSE compatibility fixes, missing-prerequisite diagnostics and safe system add-on inventory.")
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: window.section !== 4 && backend.lastOperation.length > 0
                type: backend.lastOperationSucceeded
                      ? Kirigami.MessageType.Positive : Kirigami.MessageType.Error
                text: (backend.lastOperationSucceeded
                       ? window.loc("✓ Wykonano: ", "✓ Completed: ")
                       : window.loc("✗ Niepowodzenie: ", "✗ Failed: "))
                      + window.actionName(backend.lastOperation)
                      + (!backend.lastOperationSucceeded && backend.lastOperationError.length > 0
                         ? "\n" + backend.lastOperationError : "")
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: window.section <= 2 && window.bsdtarMissing
                type: Kirigami.MessageType.Warning
                text: window.isOpenSuse()
                      ? window.loc("Brakuje narzędzia bsdtar. W openSUSE Tumbleweed zainstaluj pakiet «bsdtar» przez YaST lub Discover, a następnie kliknij «Odśwież stan». Do tego czasu sprawdzanie i aktualizacja dodatków są niedostępne.",
                                   "bsdtar is missing. On openSUSE install the 'bsdtar' package using YaST or Discover, then refresh status. Update checks are unavailable until then.")
                      : window.loc("Brakuje narzędzia bsdtar. Zainstaluj je przez menedżer oprogramowania swojej dystrybucji (na Bazzite użyj przycisku instalacji), a następnie odśwież stan.",
                                   "bsdtar is missing. Install it through your distribution's software manager (on Bazzite use the installer), then refresh status.")
            }
            Controls.Button {
                visible: window.section <= 2 && window.bsdtarMissing && window.isOpenSuse()
                text: window.loc("Otwórz pakiet bsdtar dla openSUSE", "Open openSUSE bsdtar package")
                icon.name: "download"
                onClicked: Qt.openUrlExternally("https://software.opensuse.org/package/bsdtar")
            }
            Controls.Button {
                visible: window.section <= 2 && window.bsdtarMissing
                text: window.loc("Sprawdź ponownie zależności", "Check dependencies again")
                icon.name: "view-refresh"
                enabled: !backend.running
                onClicked: backend.runAction("status-json")
            }

            GridLayout {
                visible: window.section === 0
                Layout.fillWidth: true
                columns: width > 760 ? 4 : 2
                rowSpacing: Kirigami.Units.smallSpacing
                columnSpacing: Kirigami.Units.smallSpacing

                Controls.Frame {
                    Layout.fillWidth: true
                    ColumnLayout {
                        Kirigami.Heading { level: 3; text: window.loc("System", "System") }
                        Controls.Label {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: window.dashboard.distribution || window.loc("Sprawdzanie…", "Checking…")
                        }
                    }
                }
                Controls.Frame {
                    Layout.fillWidth: true
                    ColumnLayout {
                        Kirigami.Heading { level: 3; text: "plasmoid-updater" }
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
                    ColumnLayout {
                        Kirigami.Heading { level: 3; text: window.loc("Agent", "Agent") }
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
                    ColumnLayout {
                        Kirigami.Heading { level: 3; text: window.loc("Harmonogram", "Schedule") }
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

            Kirigami.InlineMessage {
                visible: window.section === 0 && window.dashboard.agent_needs_repair === true
                Layout.fillWidth: true
                type: Kirigami.MessageType.Warning
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
                    icon.name: "view-refresh"
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
                    ColumnLayout {
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
                            icon.name: "system-search"
                            enabled: !backend.running
                            onClicked: backend.runAction("diagnose")
                        }
                    }
                }
                Controls.Frame {
                    Layout.fillWidth: true
                    ColumnLayout {
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
                            icon.name: "view-refresh"
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
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    Kirigami.Heading {
                        text: window.loc("Instalacja narzędzia", "Install the updater")
                        level: 2
                    }
                    Controls.Label {
                        text: window.loc("Pobierz i zainstaluj plasmoid-updater w katalogu użytkownika. Bez terminala, sudo i zmiany pakietów systemowych.",
                                         "Download and install plasmoid-updater into your user directory. No terminal, sudo or system package changes.")
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Controls.Button {
                        text: window.loc("Zainstaluj / sprawdź wersję…", "Install / check version…")
                        icon.name: "download"
                        enabled: !backend.running
                        onClicked: confirmInstall.open()
                    }
                }
            }

            Controls.Frame {
                visible: window.section === 1
                Layout.fillWidth: true
                ColumnLayout {
                    Layout.fillWidth: true
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
                    Flow {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        Controls.Button {
                            text: window.loc("Zainstalowane dodatki", "Installed add-ons")
                            icon.name: "view-list-details"
                            enabled: !backend.running
                            onClicked: backend.runAction("inventory-json")
                        }
                        Controls.Button {
                            text: window.loc("Dostępne aktualizacje", "Available updates")
                            icon.name: "view-refresh"
                            enabled: !backend.running && !window.bsdtarMissing
                            onClicked: backend.runAction("updates-json")
                        }
                        Controls.Button {
                            text: window.loc("Symulacja aktualizacji", "Preview update")
                            icon.name: "document-preview"
                            enabled: !backend.running && !window.bsdtarMissing
                            onClicked: backend.runAction("dry-run")
                        }
                        Controls.Button {
                            text: window.loc("Aktualizuj dodatki…", "Update add-ons…")
                            icon.name: "software-update-available"
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
                    Kirigami.InlineMessage {
                        Layout.fillWidth: true
                        visible: window.inventoryReady && window.inventoryWarning.length > 0 && window.addonView === 0
                        type: Kirigami.MessageType.Information
                        text: window.loc("Wyświetlono dodatki użytkownika. Dodatki systemowe pominięto, ponieważ nie można ich bezpiecznie odczytać bez dodatkowych uprawnień.",
                                         "User add-ons are shown. System add-ons were omitted because they cannot be read safely without additional permissions.")
                    }
                    Repeater {
                        model: window.addonView === 0 ? window.installedAddons : window.availableUpdates
                        delegate: Controls.Frame {
                            id: addonFrame
                            Layout.fillWidth: true
                            // Repeater may briefly reuse a delegate while tabs switch.
                            // Resolve by data shape so its binding never dereferences undefined.
                            readonly property var addon: modelData && modelData.installed
                                                         ? modelData.installed : modelData
                            ColumnLayout {
                                width: parent.width
                                spacing: Kirigami.Units.smallSpacing
                                Controls.Label {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
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
                                    wrapMode: Text.WordWrap
                                    text: !addonFrame.addon ? "" : window.addonView === 0
                                          ? window.loc("Wersja: ", "Version: ") + addonFrame.addon.version
                                          : addonFrame.addon.version + "  →  " + (modelData.latest_version || "—")
                                }
                            }
                        }
                    }
                    Repeater {
                        model: window.addonView === 1 ? window.updateIssues : []
                        delegate: Kirigami.InlineMessage {
                            Layout.fillWidth: true
                            visible: true
                            type: Kirigami.MessageType.Warning
                            text: modelData.name + ": " + modelData.reason
                        }
                    }
                    Controls.Label {
                        visible: window.addonView === 0
                                 ? window.inventoryReady && window.installedAddons.length === 0
                                 : window.updatesReady && window.availableUpdates.length === 0
                                    && window.updateIssues.length === 0
                        Layout.fillWidth: true
                        text: window.addonView === 0
                              ? window.loc("Nie znaleziono dodatków.", "No installed add-ons found.")
                              : window.loc("Wszystkie dodatki są aktualne.", "All add-ons are up to date.")
                    }
                }
            }

            Controls.Frame {
                visible: window.section === 2
                Layout.fillWidth: true
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing
                    Kirigami.Heading {
                        text: window.loc("Automatyczne aktualizacje", "Automatic updates")
                        level: 2
                    }
                    Kirigami.InlineMessage {
                        Layout.fillWidth: true
                        visible: !window.automationConfigLoaded
                        type: Kirigami.MessageType.Warning
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
                    Kirigami.InlineMessage {
                        Layout.fillWidth: true
                        visible: true
                        type: Kirigami.MessageType.Warning
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
                            icon.name: "document-save"
                            enabled: window.automationConfigLoaded && !backend.running && !window.bsdtarMissing
                            onClicked: window.saveAutomation()
                        }
                        Controls.Button {
                            text: window.loc("Pokaż stan timera", "Show timer status")
                            icon.name: "chronometer"
                            enabled: !backend.running
                            onClicked: backend.runAction("timer")
                        }
                        Controls.Button {
                            text: window.loc("Uruchom teraz", "Run now")
                            icon.name: "media-playback-start"
                            enabled: !backend.running && window.dashboard.agent_managed === true
                            onClicked: backend.runAction("run-service")
                        }
                        Controls.Button {
                            text: window.loc("Napraw agenta", "Repair agent")
                            icon.name: "tools-wizard"
                            enabled: !backend.running && window.dashboard.agent_managed === true
                            onClicked: backend.runAction("repair-agent")
                        }
                        Controls.Button {
                            text: window.loc("Testuj zapisaną konfigurację", "Test saved configuration")
                            icon.name: "system-search"
                            enabled: !backend.running && window.dashboard.automatic_configured === true
                                     && !window.bsdtarMissing
                            onClicked: backend.runAction("test-config")
                        }
                    }
                }
            }

            Controls.Frame {
                visible: window.section === 3
                Layout.fillWidth: true
                ColumnLayout {
                    Layout.fillWidth: true
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
                        icon.name: "view-list-text"
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

            Controls.Frame {
                visible: window.section === 4
                Layout.fillWidth: true
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    Kirigami.Heading { text: "Plasma Addon Manager 0.4.2"; level: 2 }
                    Controls.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: window.loc("Wielodystrybucyjny interfejs Qt6/Kirigami z backendem Rust.",
                                         "Cross-distribution Qt6/Kirigami frontend with a Rust backend.")
                    }
                    Controls.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "Copyright © 2026 Szymon Bławat (wolfgangxxiii)\nGPL-3.0-or-later"
                    }
                    Controls.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: window.loc("Wykorzystuje narzędzie plasmoid-updater autorstwa uwuclxdy.",
                                         "Works with the plasmoid-updater tool by uwuclxdy.")
                    }
                }
            }

            RowLayout {
                visible: window.section !== 4
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Controls.BusyIndicator {
                    running: backend.running
                    visible: running
                    implicitWidth: 26
                    implicitHeight: 26
                }
                Controls.Label {
                    text: backend.status
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Controls.Button {
                    text: window.loc("Anuluj", "Cancel")
                    icon.name: "process-stop"
                    enabled: backend.running
                    onClicked: backend.cancel()
                }
            }

        }
    }
}
