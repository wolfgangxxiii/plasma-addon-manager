import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Mirrors the structure of Bazzite Plasmoid Updater GUI's About page while
// retaining the Qt/Kirigami appearance and this project's own destinations.
ColumnLayout {
    id: about
    property bool polish: false
    spacing: Kirigami.Units.largeSpacing

    function loc(pl, en) { return polish ? pl : en }

    Kirigami.Heading {
        Layout.fillWidth: true
        level: 1
        text: about.loc("O programie", "About")
    }

    Controls.Label {
        Layout.fillWidth: true
        opacity: 0.75
        wrapMode: Text.WordWrap
        text: about.loc("Informacje o aplikacji, jej autorze, wykorzystanym narzędziu i licencji.",
                        "Application information, its author, the underlying tool and license.")
    }

    Controls.Frame {
        Layout.fillWidth: true
        padding: Kirigami.Units.largeSpacing
        RowLayout {
            width: parent.width
            spacing: Kirigami.Units.largeSpacing

            Rectangle {
                Layout.preferredWidth: 88
                Layout.preferredHeight: 88
                Layout.alignment: Qt.AlignTop
                radius: 16
                color: Qt.rgba(Kirigami.Theme.highlightColor.r,
                               Kirigami.Theme.highlightColor.g,
                               Kirigami.Theme.highlightColor.b, 0.10)

                Image {
                    id: aboutLogo
                    objectName: "aboutBrandIcon"
                    anchors.fill: parent
                    anchors.margins: 10
                    source: "qrc:/images/app.png"
                    fillMode: Image.PreserveAspectFit
                    sourceSize: Qt.size(128, 128)
                    smooth: true
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Kirigami.Heading {
                    Layout.fillWidth: true
                    level: 2
                    text: "Plasma Addon Manager"
                }
                Controls.Label {
                    Layout.fillWidth: true
                    opacity: 0.7
                    text: "v0.4.5 · Qt 6 / Kirigami · Rust"
                }
                Controls.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: about.loc(
                        "Graficzne zarządzanie dodatkami KDE Plasma 6 na wielu dystrybucjach Linuksa. Automatyczne aktualizacje działają w tle również po zamknięciu okna programu.",
                        "Graphical management of KDE Plasma 6 add-ons across Linux distributions. Scheduled updates can run in the background after the application window closes.")
                }
            }
        }
    }

    Controls.Frame {
        Layout.fillWidth: true
        ColumnLayout {
            width: parent.width
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Heading {
                level: 3
                text: about.loc("Strona internetowa", "Website")
            }
            Controls.Button {
                highlighted: true
                icon.name: "go-jump"
                Layout.alignment: Qt.AlignLeft
                text: about.loc("Repozytorium projektu na GitHub", "Project repository on GitHub")
                onClicked: Qt.openUrlExternally("https://github.com/wolfgangxxiii/plasma-addon-manager")
            }
            Controls.Button {
                highlighted: true
                icon.name: "go-jump"
                Layout.alignment: Qt.AlignLeft
                text: about.loc("Wydania i pliki AppImage", "Releases and AppImage downloads")
                onClicked: Qt.openUrlExternally("https://github.com/wolfgangxxiii/plasma-addon-manager/releases")
            }
        }
    }

    Controls.Frame {
        Layout.fillWidth: true
        ColumnLayout {
            width: parent.width
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Heading {
                level: 3
                text: about.loc("Uzyskaj pomoc", "Get help")
            }
            Controls.Button {
                highlighted: true
                icon.name: "go-jump"
                Layout.alignment: Qt.AlignLeft
                text: about.loc("Zgłoś błąd lub zaproponuj funkcję", "Report an issue or request a feature")
                onClicked: Qt.openUrlExternally("https://github.com/wolfgangxxiii/plasma-addon-manager/issues")
            }
        }
    }

    Controls.Frame {
        Layout.fillWidth: true
        ColumnLayout {
            width: parent.width
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Heading {
                level: 3
                text: about.loc("Prawa autorskie", "Copyright")
            }
            Controls.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "Copyright © 2026 Szymon Bławat (wolfgangxxiii)\nGNU GPL-3.0-or-later"
            }
            Controls.Button {
                highlighted: true
                icon.name: "go-jump"
                Layout.alignment: Qt.AlignLeft
                text: about.loc("Przeczytaj licencję", "Read the license")
                onClicked: Qt.openUrlExternally("https://github.com/wolfgangxxiii/plasma-addon-manager/blob/main/LICENSE")
            }
        }
    }

    Controls.Frame {
        Layout.fillWidth: true
        ColumnLayout {
            width: parent.width
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Heading {
                level: 3
                text: about.loc("Autor programu", "Application author")
            }
            Controls.Button {
                highlighted: true
                icon.name: "go-jump"
                Layout.alignment: Qt.AlignLeft
                text: about.loc("wolfgangxxiii · autor aplikacji", "wolfgangxxiii · application author")
                onClicked: Qt.openUrlExternally("https://github.com/wolfgangxxiii")
            }
        }
    }

    Controls.Frame {
        Layout.fillWidth: true
        ColumnLayout {
            width: parent.width
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Heading {
                level: 3
                text: about.loc("Wykorzystane narzędzie", "Underlying tool")
            }
            Controls.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: about.loc(
                    "Aplikacja korzysta z niezależnego projektu plasmoid-updater do aktualizowania dodatków KDE Store.",
                    "The application uses the independent plasmoid-updater project for KDE Store add-on updates.")
            }
            Controls.Button {
                highlighted: true
                icon.name: "go-jump"
                Layout.alignment: Qt.AlignLeft
                text: about.loc("uwuclxdy · autor narzędzia plasmoid-updater",
                                "uwuclxdy · author of the plasmoid-updater tool")
                onClicked: Qt.openUrlExternally("https://github.com/uwuclxdy/plasmoid-updater")
            }
            Controls.Label {
                Layout.fillWidth: true
                opacity: 0.7
                wrapMode: Text.WordWrap
                text: about.loc(
                    "Projekt niezależny, niepowiązany oficjalnie z KDE ani twórcą plasmoid-updater.",
                    "Independent project, not officially affiliated with KDE or the plasmoid-updater author.")
            }
        }
    }
}
