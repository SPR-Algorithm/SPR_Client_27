import QtQuick

Rectangle {
    id: root

    property string title
    property string icon
    property string subtitle
    property string trailing
    property int titleSize: 13
    property color tint: "#e2eaf0"
    property color topColor: "#2d3943"
    property color bottomColor: "#212d37"

    height: 25
    gradient: Gradient {
        GradientStop { position: 0; color: root.topColor }
        GradientStop { position: 1; color: root.bottomColor }
    }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#57717f" }
    Row {
        x: 9
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        DashboardGlyph {
            visible: root.icon !== ""
            kind: root.icon
            tint: root.tint
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: root.title
            anchors.verticalCenter: parent.verticalCenter
            color: root.tint
            font.pixelSize: root.titleSize
            font.bold: true
        }
        Rectangle {
            visible: root.subtitle !== ""
            width: 1
            height: 12
            color: "#627785"
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            visible: root.subtitle !== ""
            text: root.subtitle
            anchors.verticalCenter: parent.verticalCenter
            color: "#aebecb"
            font.pixelSize: 11
        }
    }
    Text {
        text: root.trailing
        anchors.right: parent.right
        anchors.rightMargin: 9
        anchors.verticalCenter: parent.verticalCenter
        color: "#b9cddc"
        font.pixelSize: 11
    }
}
