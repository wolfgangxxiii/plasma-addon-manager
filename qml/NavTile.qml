import QtQuick
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

// Render a bundled PNG directly. KDE icon theme lookups can return a valid
// name while drawing nothing in an AppImage, so navigation never depends on it.
Controls.ToolButton {
    id: tile
    property url imageSource: ""
    property bool selected: false

    implicitHeight: 70
    Accessible.name: text

    contentItem: Item {
        Column {
            width: parent.width
            anchors.centerIn: parent
            spacing: 5
            Item {
                width: parent.width
                height: 34
                Image {
                    objectName: "navigationImage"
                    anchors.centerIn: parent
                    width: 34
                    height: 34
                    source: tile.imageSource
                    sourceSize: Qt.size(64, 64)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: false
                }
            }
            Controls.Label {
                objectName: "navigationLabel"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                maximumLineCount: 2
                text: tile.text
                font.pixelSize: 12
                color: Kirigami.Theme.textColor
            }
        }
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
