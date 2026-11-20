import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Explicit content instead of ToolButton's platform-specific TextUnderIcon
// rendering, which can produce blank buttons with the bundled KDE style.
Controls.ToolButton {
    id: tile
    property string iconName: ""
    property string fallbackGlyph: "•"
    property bool selected: false

    implicitHeight: 70
    Accessible.name: text

    contentItem: ColumnLayout {
        spacing: 3
        Item { Layout.fillHeight: true }

        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28

            Kirigami.Icon {
                id: tileIcon
                anchors.fill: parent
                source: tile.iconName
                fallback: "applications-system"
                active: tile.hovered
                selected: tile.selected
            }
            Controls.Label {
                anchors.centerIn: parent
                visible: !tileIcon.valid
                text: tile.fallbackGlyph
                font.pixelSize: 23
                font.bold: true
                color: Kirigami.Theme.textColor
            }
        }

        Controls.Label {
            objectName: "navigationLabel"
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            text: tile.text
            font.pixelSize: 12
            color: Kirigami.Theme.textColor
        }
        Item { Layout.fillHeight: true }
    }

    background: Rectangle {
        radius: 8
        color: tile.selected
               ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g,
                         Kirigami.Theme.highlightColor.b, 0.28)
               : tile.hovered
                 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                           Kirigami.Theme.textColor.b, 0.08)
                 : "transparent"
        border.width: tile.selected ? 1 : 0
        border.color: Kirigami.Theme.highlightColor
    }
}
