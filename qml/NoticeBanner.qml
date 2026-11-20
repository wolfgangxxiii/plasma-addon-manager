import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// A message banner with a bundled icon. Do not use theme icon names: some
// KDE desktop styles in AppImage reserve icon space but render no image.
Controls.Frame {
    id: banner
    property string kind: "warning"
    property string text: ""
    readonly property color tone: kind === "error" ? Kirigami.Theme.negativeTextColor
                                  : kind === "success" ? Kirigami.Theme.positiveTextColor
                                  : kind === "warning" ? Kirigami.Theme.neutralTextColor
                                  : Kirigami.Theme.highlightColor

    padding: Kirigami.Units.smallSpacing
    background: Rectangle {
        radius: 7
        color: Qt.rgba(banner.tone.r, banner.tone.g, banner.tone.b, 0.12)
        border.width: 1
        border.color: banner.tone
    }

    RowLayout {
        width: parent.width
        spacing: Kirigami.Units.smallSpacing

        Image {
            objectName: "noticeBannerIcon"
            source: banner.kind === "error" ? "qrc:/images/ui-error.png"
                    : banner.kind === "success" ? "qrc:/images/ui-success.png"
                    : banner.kind === "warning" ? "qrc:/images/ui-warning.png"
                    : "qrc:/images/nav-notifications.png"
            sourceSize: Qt.size(64, 64)
            fillMode: Image.PreserveAspectFit
            smooth: true
            Layout.preferredWidth: 24
            Layout.preferredHeight: 24
            Layout.alignment: Qt.AlignTop
        }
        Controls.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: banner.text
            font.pixelSize: 12
            color: Kirigami.Theme.textColor
        }
    }
}
