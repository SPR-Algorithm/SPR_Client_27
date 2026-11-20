pragma ComponentBehavior: Bound

import QtQuick 2.15
import "DashboardFormat.js" as Format

Item {
    id: root

    required property bool blue
    required property string teamName
    required property bool structures
    required property var stats
    property bool compact: false
    readonly property string side: blue ? "blue" : "red"
    readonly property color accent: blue ? "#85c6f2" : "#fa9083"
    readonly property color outpostAccent: stats.outpostOwnerRed === undefined ? accent
        : (stats.outpostOwnerRed ? "#ff9d90" : "#8cc8ff")
    readonly property real unit: bars.height / 58
    readonly property int flagSize: compact ? 26 : 33

    Row {
        id: teamTitle
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.structures ? root.flagSize : root.height
        layoutDirection: root.blue ? Qt.RightToLeft : Qt.LeftToRight
        spacing: 8

        Image {
            width: root.flagSize
            height: root.flagSize
            anchors.verticalCenter: parent.verticalCenter
            source: "qrc:/images/top_mid/" + root.side + "_team_logo.png"
            fillMode: Image.PreserveAspectFit
        }
        Text {
            width: Math.max(0, parent.width - root.flagSize - 45)
            anchors.verticalCenter: parent.verticalCenter
            text: root.teamName
            horizontalAlignment: root.blue ? Text.AlignRight : Text.AlignLeft
            elide: Text.ElideRight
            color: "#f1f5f9"
            font.pixelSize: Math.max(14, Math.min(23, width / 22))
            font.weight: Font.Bold
            style: Text.Raised
            styleColor: "#393238"
        }
        Text {
            width: 29
            anchors.verticalCenter: teamTitle.verticalCenter
            text: root.blue ? "蓝方" : "红方"
            color: root.accent
            font.pixelSize: 11
            horizontalAlignment: root.blue ? Text.AlignLeft : Text.AlignRight
        }
    }

    Canvas {
        id: bars
        visible: root.structures
        x: 0
        y: teamTitle.height + 4
        width: parent.width
        height: root.compact ? 49 : 58
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        function plate(top, bottom, hp, maxHp, isBlue, outlineColor) {
            const ctx = getContext("2d")
            const slope = width * 2.66 / 480
            const upper = width - 1 - slope * top
            const lower = width - 1 - slope * bottom
            const ratio = hp === undefined ? 0 : Math.max(0, Math.min(1, hp / maxHp))
            const y1 = top * root.unit
            const y2 = bottom * root.unit
            ctx.beginPath()
            ctx.moveTo(1, y1)
            ctx.lineTo(upper, y1)
            ctx.lineTo(lower, y2)
            ctx.lineTo(1, y2)
            ctx.closePath()
            ctx.fillStyle = isBlue ? "#283f50" : "#423a3e"
            ctx.fill()
            ctx.strokeStyle = outlineColor
            ctx.lineWidth = 0.7
            ctx.stroke()
            if (!ratio)
                return
            const gradient = ctx.createLinearGradient(0, y1, 0, y2)
            gradient.addColorStop(0, isBlue ? "#529dcc" : "#d76455")
            gradient.addColorStop(0.55, isBlue ? "#326987" : "#a74237")
            gradient.addColorStop(1, isBlue ? "#275470" : "#85372f")
            ctx.beginPath()
            ctx.moveTo(1, y1)
            ctx.lineTo(1 + (upper - 1) * ratio, y1)
            ctx.lineTo(1 + (lower - 1) * ratio, y2)
            ctx.lineTo(1, y2)
            ctx.closePath()
            ctx.fillStyle = gradient
            ctx.fill()
        }

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.save()
            if (root.blue) {
                ctx.translate(width, 0)
                ctx.scale(-1, 1)
            }
            plate(4, 27, root.stats.baseHp, 10000, root.blue, root.accent)
            plate(34, 51, root.stats.outpostHp, 1000,
                  root.stats.outpostOwnerRed === undefined ? root.blue : !root.stats.outpostOwnerRed, root.outpostAccent)
            ctx.restore()
        }
        Connections {
            target: root
            function onStatsChanged() { bars.requestPaint() }
        }
    }

    Repeater {
        model: root.structures ? [
            { label:"基地", hp:root.stats.baseHp, max:10000, top:4, bottom:27,
              state:root.stats.baseHp === 0 ? "已摧毁"
                    : ["防御 +100%", "装甲闭合", "装甲展开"][root.stats.baseStatus] || "" },
            { label:root.blue ? "B 前哨" : "R 前哨", hp:root.stats.outpostHp, max:1000, top:34, bottom:51,
              state:root.stats.outpostHp === 0 ? "已摧毁" : root.stats.outpostOwnerRed === undefined ? ""
                    : (root.stats.outpostOwnerRed ? "红方" : "蓝方")
                      + (root.stats.outpostControl === 1 || root.stats.outpostControl === 4 ? "完全控制"
                         : root.stats.outpostControl === 2 || root.stats.outpostControl === 3 ? "临时控制" : "控制") }
        ] : []

        Row {
            id: labelRow
            required property var modelData
            required property int index
            x: root.blue ? root.width - width - 8 : 8
            y: bars.y + modelData.top * root.unit
            height: (modelData.bottom - modelData.top) * root.unit
            layoutDirection: root.blue ? Qt.RightToLeft : Qt.LeftToRight
            spacing: root.compact ? 6 : 9

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                layoutDirection: root.blue ? Qt.RightToLeft : Qt.LeftToRight
                DashboardGlyph {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 12; height: 12
                    kind: labelRow.index === 0 ? "base" : "outpost"
                    tint: "#e8edf1"
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: labelRow.modelData.label
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: "#ffffff"
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.RichText
                text: "<b>" + Format.number(labelRow.modelData.hp) + "</b> <span style='font-size:10px'>/ "
                    + Format.number(labelRow.modelData.max) + "</span>"
                font.family: "Bahnschrift"
                font.pixelSize: labelRow.index === 0 ? (root.compact ? 16 : 18) : 14
                color: "#ffffff"
                style: Text.Raised
                styleColor: "#5a1b2530"
            }
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                DashboardGlyph {
                    visible: labelRow.index === 0 && root.stats.baseHp !== 0 && root.stats.baseStatus === 0
                    kind: "shield"; tint: "#eaf2f5"; width: 12; height: 12
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: labelRow.modelData.state
                    font.pixelSize: 10
                    color: labelRow.index === 1 ? root.outpostAccent : "#ffffff"
                    style: Text.Outline
                    styleColor: "#8911202c"
                }
            }
        }
    }
}
