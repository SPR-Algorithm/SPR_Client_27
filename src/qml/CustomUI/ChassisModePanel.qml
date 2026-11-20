import QtQuick 2.15

Rectangle {
    id: root
    width: root.currentTheme ? 116 : 140
    height: root.currentTheme ? 42 : 90
    color: root.currentTheme ? "#dd192832" : "#CC1A1A1A"
    radius: root.currentTheme ? 2 : 5
    border.color: root.currentTheme ? "#6d8797" : "#55FF4444"
    border.width: 1

    property var customData: ({})
    property bool currentTheme: false
    property int chassisMode: customData.chassisMode !== undefined ? customData.chassisMode : -1
    property bool followMode: customData.chassisMode === 1
    property bool spinMode: customData.chassisMode === 2
    property bool protectMode: customData.chassisMode === 3
    visible: customData.chassisMode !== undefined

    function modeName(mode) {
        switch(mode) {
            case 0: return "NORMAL"
            case 1: return "FOLLOW"
            case 2: return "SPIN"
            case 3: return "PROTECT"
            default: return "--"
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 5

        Text {
            text: root.currentTheme ? "底盘模式" : "CHASSIS MODE"
            color: root.currentTheme ? "#b5cbd8" : "#FF4444"
            font.pixelSize: 10
            font.bold: true
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Text {
            text: root.currentTheme
                ? (["普通", "跟随", "旋转", "保护"][root.chassisMode] || "—")
                : root.modeName(root.chassisMode)
            color: root.currentTheme ? (root.protectMode ? "#ffd190" : "#eaf4fa")
                 : root.chassisMode === 0 ? "#888888"
                 : root.chassisMode === 3 ? "#FF4444"
                 : "#00FF00"
            font.pixelSize: root.currentTheme ? 12 : 16
            font.bold: true
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
}
