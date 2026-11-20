import QtQuick 2.15

Rectangle {
    id: root
    width: 130
    height: root.currentTheme ? 42 : 60
    color: root.currentTheme ? "#dd192832" : "#CC1A1A1A"
    radius: root.currentTheme ? 2 : 5
    border.color: root.currentTheme ? "#6d8797" : "#55FF4444"
    border.width: 1

    property var customData: ({})
    property bool currentTheme: false
    property bool fricOn: customData.fricEnabled !== undefined ? customData.fricEnabled : false
    property bool rammerOn: customData.rammerEnabled !== undefined ? customData.rammerEnabled : false
    visible: customData.fricEnabled !== undefined

    Column {
        anchors.centerIn: parent
        spacing: 4

        Text {
            text: root.currentTheme ? "发射机构状态" : "FRICTION STATUS"
            color: root.currentTheme ? "#d9e8f2" : "#FF4444"
            font.pixelSize: 10
            font.bold: true
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12

            Row {
                spacing: 4
                Text { text: root.currentTheme ? "摩擦轮" : "FRIC"; color: root.currentTheme ? "#abc1cf" : "#00CED1"; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
                Rectangle {
                    width: 10; height: 10; radius: 5; anchors.verticalCenter: parent.verticalCenter
                    color: root.fricOn ? (root.currentTheme ? "#91ddbd" : "#00FF00") : "#555555"
                }
            }

            Row {
                spacing: 4
                Text { text: root.currentTheme ? "拨弹" : "RAM"; color: root.currentTheme ? "#abc1cf" : "#00CED1"; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
                Rectangle {
                    width: 10; height: 10; radius: 5; anchors.verticalCenter: parent.verticalCenter
                    color: root.rammerOn ? (root.currentTheme ? "#91ddbd" : "#00FF00") : "#555555"
                }
            }
        }
    }
}
