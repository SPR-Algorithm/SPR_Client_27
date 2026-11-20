import QtQuick 2.15

Item {
    id: root

    required property color captureColor
    property bool temporarilyControlled: false
    property int remainingSec: 0
    property real visualScale: 1

    readonly property int activationDurationSec: 10
    readonly property bool timing: root.remainingSec > 0
    readonly property real progress: root.timing
        ? 1 - Math.min(1, root.remainingSec / root.activationDurationSec) : 0

    visible: root.timing || root.temporarilyControlled

    Canvas {
        id: coverage

        anchors.fill: parent
        property real fillRatio: root.progress
        onFillRatioChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onVisibleChanged: { if (visible) requestPaint() }

        Behavior on fillRatio {
            NumberAnimation { duration: 220 }
        }

        Connections {
            target: root
            function onCaptureColorChanged() { coverage.requestPaint() }
            function onTemporarilyControlledChanged() { coverage.requestPaint() }
        }

        onPaint: {
            const ctx = getContext("2d")
            const w = width
            const h = height
            ctx.reset()
            ctx.beginPath()
            ctx.moveTo(1, h / 2)
            ctx.lineTo(w * 0.25, 1)
            ctx.lineTo(w * 0.75, 1)
            ctx.lineTo(w - 1, h / 2)
            ctx.lineTo(w * 0.75, h - 1)
            ctx.lineTo(w * 0.25, h - 1)
            ctx.closePath()
            ctx.save()
            ctx.clip()
            ctx.fillStyle = root.captureColor
            ctx.globalAlpha = root.temporarilyControlled ? 0.29 : 0.08
            ctx.fillRect(0, 0, w, h)
            ctx.globalAlpha = 0.42
            const fillHeight = h * fillRatio
            ctx.fillRect(0, h - fillHeight, w, fillHeight)
            ctx.restore()
            ctx.strokeStyle = root.captureColor
            ctx.globalAlpha = root.temporarilyControlled ? 0.86 : 0.60
            ctx.lineWidth = Math.max(1, root.visualScale)
            ctx.stroke()
        }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.top
        anchors.bottomMargin: 2 * root.visualScale
        width: readout.implicitWidth + 8 * root.visualScale
        height: readout.implicitHeight + 3 * root.visualScale
        color: "#cf17232a"
        border.color: root.captureColor
        border.width: 1
        radius: 2 * root.visualScale

        Text {
            id: readout

            anchors.centerIn: parent
            text: root.timing ? qsTr("%1 s").arg(root.remainingSec) : qsTr("阵地临控")
            color: "#f7f8f4"
            font.pixelSize: Math.max(9, 9 * root.visualScale)
            font.bold: true
        }
    }
}
