import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    required property var effect
    property int labelSize: 10
    readonly property color tone: effect.vulnerable ? "#ffd996"
        : effect.type === 5 ? "#afd58c" : effect.type === 2 ? "#a4e4f7" : "#a1e3cc"

    implicitHeight: 15
    color: "#d414222b"
    border.color: "#4d6676"
    radius: 1
    Rectangle {
        x: 1
        y: 1
        width: (parent.width - 2) * Math.max(0, Math.min(1, Number(root.effect.left) / Math.max(1, root.effect.total)))
        height: parent.height - 2
        color: Qt.alpha(root.tone, 0.31)
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Qt.alpha(root.tone, 0.64) }
    }
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 3
        anchors.rightMargin: 3
        spacing: 3
        DashboardGlyph {
            kind: root.effect.type === 5 ? "recovery" : "shield"
            tint: root.tone
            Layout.preferredWidth: root.labelSize
            Layout.preferredHeight: root.labelSize
        }
        Text {
            Layout.fillWidth: true
            text: root.effect.label
            font.pixelSize: root.labelSize
            color: root.tone
            elide: Text.ElideRight
        }
        Text {
            text: root.effect.left + "s"
            font.pixelSize: root.labelSize
            font.bold: true
            color: root.tone
        }
    }
}
