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
    readonly property bool polish: languageChoice === "pl"
                                   || (languageChoice === "auto"
                                       && Qt.locale().name.toLowerCase().startsWith("pl"))
    function loc(pl, en) { return polish ? pl : en }
    readonly property string currentSection: {
        switch (section) {
        case 0: return loc("Pulpit", "Dashboard")
        case 1: return loc("Dodatki Plasma", "Plasma add-ons")
        case 2: return loc("Automatyzacja", "Automation")
        case 3: return loc("Dziennik", "Journal")
        default: return loc("O programie", "About")
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
                "Zostaną zaktualizowane dodatki KDE Store bieżącego użytkownika przez plasmoid-updater. Nie zostanie zmodyfikowany system Bazzite ani uruchomiony ponownie pulpit Plasma. Operacja wymaga zainstalowanego plasmoid-updater.",
                "plasmoid-updater will update KDE Store add-ons for your user. The Bazzite system image and Plasma session will not be restarted. A working plasmoid-updater installation is required.")
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
                    "Wersja testowa 0.1.1: odczyt, symulacja i ręczna aktualizacja dodatków po potwierdzeniu. Instalator i harmonogram pozostają bez zmian.",
                    "Preview 0.1.1: inspection, preview and confirmed manual updates. Installer and schedule management are not yet available.")
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
                            enabled: !backend.running
                            onClicked: backend.runAction("check")
                        }
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
                            onClicked: backend.runAction("inventory")
                        }
                        Controls.Button {
                            text: window.loc("Dostępne aktualizacje", "Available updates")
                            icon.name: "view-refresh"
                            enabled: !backend.running
                            onClicked: backend.runAction("check")
                        }
                        Controls.Button {
                            text: window.loc("Symulacja aktualizacji", "Preview update")
                            icon.name: "document-preview"
                            enabled: !backend.running
                            onClicked: backend.runAction("dry-run")
                        }
                        Controls.Button {
                            text: window.loc("Aktualizuj dodatki…", "Update add-ons…")
                            icon.name: "software-update-available"
                            enabled: !backend.running
                            onClicked: confirmUpdate.open()
                        }
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
                        text: window.loc("Harmonogram systemd", "systemd schedule")
                        level: 2
                    }
                    Controls.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: window.loc("Sprawdź istniejący timer. Zarządzanie interwałem i agentem zostanie dodane później.",
                                         "Inspect the existing timer. Scheduler and agent management will be added later.")
                    }
                    Controls.Button {
                        text: window.loc("Pokaż stan timera", "Show timer status")
                        icon.name: "chronometer"
                        enabled: !backend.running
                        onClicked: backend.runAction("timer")
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
                        text: window.loc("Ostatnie uruchomienia", "Recent runs")
                        level: 2
                    }
                    Controls.Button {
                        text: window.loc("Odczytaj dziennik", "Read journal")
                        icon.name: "view-list-text"
                        enabled: !backend.running
                        onClicked: backend.runAction("journal")
                    }
                }
            }

            Controls.Frame {
                visible: window.section === 4
                Layout.fillWidth: true
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    Kirigami.Heading { text: "Plasma Addon Manager 0.1.1"; level: 2 }
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

            Controls.ScrollView {
                visible: window.section !== 4
                Layout.fillWidth: true
                Layout.preferredHeight: 310
                Controls.TextArea {
                    text: backend.output.length > 0 ? backend.output
                                                     : window.loc("Wybierz działanie, aby zobaczyć wynik.",
                                                                  "Choose an action to see its output.")
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.WrapAnywhere
                    font.family: "monospace"
                    font.pixelSize: 12
                }
            }
        }
    }
}
