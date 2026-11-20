import QtQuick 2.15

Item {
    id: root

    required property bool isBase
    required property color teamColor
    property var hp
    property int maxHp: 1
    property string status: ""
    property real visualScale: 1
    property bool compact: false
    property real viewportWidth: parent ? parent.width : 0
    // The map can parent the plate alongside robot health bars in the same coordinates.
    property Item statusLayer: null

    readonly property bool receivedHp: root.hp !== undefined && root.hp !== null
    readonly property bool destroyed: root.receivedHp && root.hp === 0
    readonly property real hpRatio: root.receivedHp
        ? Math.max(0, Math.min(1, root.hp / Math.max(1, root.maxHp))) : 0
    readonly property string stateText: root.destroyed ? qsTr("已摧毁") : root.status

    onTeamColorChanged: {
        if (symbol)
            symbol.requestPaint()
    }
    width: 0
    height: 0

    Canvas {
        id: symbol

        anchors.centerIn: parent
        width: (root.compact ? 12 : 17) * root.visualScale
        height: width
        opacity: root.destroyed ? 0.60 : 1

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.scale(width / 32, height / 32)
            ctx.lineJoin = "round"
            ctx.lineWidth = 1.6
            ctx.strokeStyle = root.teamColor
            ctx.fillStyle = "#8720282e"
            ctx.beginPath()
            if (root.isBase) {
                // Closed plates around the base core.
                ctx.moveTo(16, 2)
                ctx.lineTo(28, 8)
                ctx.lineTo(28, 24)
                ctx.lineTo(16, 30)
                ctx.lineTo(4, 24)
                ctx.lineTo(4, 8)
                ctx.closePath()
                ctx.fill()
                ctx.stroke()
                ctx.beginPath()
                ctx.moveTo(16, 7)
                ctx.lineTo(23, 11)
                ctx.lineTo(23, 21)
                ctx.lineTo(16, 25)
                ctx.lineTo(9, 21)
                ctx.lineTo(9, 11)
                ctx.closePath()
                ctx.stroke()
                ctx.fillStyle = root.teamColor
                ctx.fillRect(13, 13, 6, 6)
            } else {
                // Three plates around the outpost mast.
                ctx.arc(16, 16, 13.5, 0, 2 * Math.PI)
                ctx.fill()
                ctx.stroke()
                ctx.fillStyle = root.teamColor
                for (let arm = 0; arm < 3; ++arm) {
                    ctx.save()
                    ctx.translate(16, 16)
                    ctx.rotate(arm * 2 * Math.PI / 3)
                    ctx.fillRect(-3.25, -9.5, 6.5, 4.4)
                    ctx.restore()
                }
                ctx.beginPath()
                ctx.arc(16, 16, 3, 0, 2 * Math.PI)
                ctx.fill()
            }
        }
    }

    Rectangle {
        id: statusPlate

        parent: root.statusLayer || root
        objectName: root.objectName + "Plate"
        readonly property real offsetX: Math.max(2 - root.x,
            Math.min(-width / 2, root.viewportWidth - root.x - width - 2))
        x: (root.statusLayer ? root.x : 0) + offsetX
        y: (root.statusLayer ? root.y : 0) + symbol.height / 2 + 1
        z: root.statusLayer ? 2 : 0
        visible: root.visible
        width: Math.max(hpLabel.implicitWidth, stateLabel.visible ? stateLabel.implicitWidth : 0)
               + 10 * root.visualScale
        height: readout.implicitHeight + 4 * root.visualScale
        radius: 2 * root.visualScale
        clip: true
        color: Qt.rgba(root.teamColor.r, root.teamColor.g, root.teamColor.b, 0.07)
        border.color: Qt.rgba(root.teamColor.r, root.teamColor.g, root.teamColor.b, 0.30)
        border.width: 1

        Rectangle {
            objectName: root.objectName + "Fill"
            anchors.left: parent.left
            height: parent.height
            width: parent.width * root.hpRatio
            radius: statusPlate.radius
            color: Qt.rgba(root.teamColor.r, root.teamColor.g, root.teamColor.b, 0.23)
        }

        Column {
            id: readout

            anchors.centerIn: parent
            spacing: 0

            Text {
                id: hpLabel

                objectName: root.objectName + "Hp"
                anchors.horizontalCenter: parent.horizontalCenter
                text: (root.receivedHp ? root.hp : "—") + " / " + root.maxHp
                font.pixelSize: Math.max(10, (root.compact ? 9 : 11) * root.visualScale)
                font.weight: Font.Bold
                color: "#f7f8f4"
                style: Text.Outline
                styleColor: "#95303a3f"
            }

            Text {
                id: stateLabel

                objectName: root.objectName + "Status"
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.stateText.length > 0
                text: root.stateText
                font.pixelSize: Math.max(8, (root.compact ? 8 : 9) * root.visualScale)
                color: "#f0f2ed"
                style: Text.Outline
                styleColor: "#9520292e"
            }
        }
    }
}
