pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import "DashboardFormat.js" as Format

Rectangle {
    id: root

    required property bool blue
    required property var robots
    property bool compact: false
    readonly property color team: blue ? "#85c6f2" : "#fa9083"
    readonly property var fractions: [0.24, 0.19, 0.20, 0.105, 0.14, 0.125]
    readonly property real lineHeight: Math.max(0, (height - title.height - headings.height - 2) / Math.max(1, robots.length))
    color: "#bb1a252e"
    border.color: Qt.tint("#425666", Qt.alpha(team, 0.52))
    clip: true

    DashboardTitleBar {
        id: title
        x: 1; y: 1
        width: parent.width - 2
        height: root.compact ? 32 : 39
        titleSize: root.compact ? 14 : 17
        title: (root.blue ? "蓝方" : "红方") + "机器人"
        icon: "squad"
        tint: root.team
        topColor: Qt.tint("#20313c", Qt.alpha(root.team, 0.12))
        bottomColor: "#1a2832"
    }
    Row {
        id: headings
        x: 10
        y: title.y + title.height
        width: parent.width - 20
        height: root.compact ? 27 : 31
        Repeater {
            model: ["车位", "血量", "状态", "余弹", "热量 / 上限", "功率上限"]
            Text {
                required property int index
                required property string modelData
                width: headings.width * root.fractions[index]
                height: headings.height
                verticalAlignment: Text.AlignVCenter
                text: modelData
                font.pixelSize: root.compact ? 11 : 12
                color: "#b7c8d5"
            }
        }
    }
    Column {
        x: 1
        y: headings.y + headings.height
        width: parent.width - 2
        Repeater {
            model: root.robots.length
            Rectangle {
                id: line
                required property int index
                readonly property var robot: root.robots[index] ?? ({})
                readonly property bool heavy: robot.number === 1 && robot.heavy !== undefined
                readonly property DashboardHeavyEffects motion: heavyEffect.item as DashboardHeavyEffects
                readonly property bool invincible: robot.invincibleLeft > 0
                readonly property bool reviving: robot.respawnLeft !== undefined
                readonly property color progressTint: invincible ? "#ffd580" : reviving ? "#8fe2ae" : root.team
                readonly property real progress: invincible ? Format.ratio(robot.invincibleLeft, robot.invincibleTotal)
                    : reviving ? Format.ratio(robot.respawnLeft, robot.respawnTotal) : Format.ratio(robot.hp, robot.maxHp)
                width: root.width - 2
                height: root.lineHeight
                clip: true
                color: robot.selected ? Qt.tint("#352c3844", Qt.alpha(root.team, .19))
                    : index % 2 === 0 ? "#611e3946" : "#24111c29"
                Rectangle { width: parent.width; height: 1; color: "#354750" }
                Rectangle {
                    x: root.blue ? parent.width - width : 0
                    width: 2
                    height: parent.height
                    visible: line.robot.selected
                    color: root.team
                }
                Row {
                    id: cells
                    x: 9
                    width: line.width - 18
                    height: line.height
                    Item {
                        width: cells.width * root.fractions[0]; height: parent.height
                        Row {
                            id: portraitRow
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 5
                            Rectangle {
                                width: 21; height: 21; radius: 11
                                color: "#232f39"; border.color: "#526975"
                                anchors.verticalCenter: parent.verticalCenter
                                Text { anchors.centerIn: parent; color: root.team; font.pixelSize: 11; font.bold: true; text: line.robot.number }
                            }
                            Item {
                                id: portrait
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(line.heavy ? 42 : 60, cells.width * 0.075)
                                height: Math.max(0, Math.min(37, line.height - 2))
                                Image {
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectFit
                                    source: Format.portrait(root.blue, line.robot.number, line.heavy ? false : undefined)
                                    opacity: 1 - (line.motion?.heroMix || 0)
                                }
                                Image {
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectFit
                                    source: line.heavy ? Format.portrait(root.blue, 1, true) : ""
                                    opacity: line.motion?.heroMix || 0
                                }
                            }
                            Text {
                                width: Math.max(0, cells.width * root.fractions[0] - 40 - portrait.width)
                                text: line.heavy ? Format.heavyName(root.blue, Boolean(line.motion?.hero)) : line.robot.name
                                textFormat: line.heavy ? Text.RichText : Text.PlainText
                                color: "#edf2f4"
                                font.pixelSize: line.heavy
                                    ? Math.min(root.compact ? 12 : 14, Math.max(8, Math.floor(width / 6)))
                                    : root.compact ? 12 : 14
                                elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                    Item {
                        width: cells.width * root.fractions[1]; height: parent.height
                        Column {
                            width: parent.width - 20
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3
                            Text {
                                text: "<b>" + (line.robot.hp ?? "—") + "</b> <span style='font-size:11px'>/ " + (line.robot.maxHp ?? "—") + "</span>"
                                textFormat: Text.RichText
                                font.family: "Bahnschrift"; font.pixelSize: 16; color: "#f0f5f8"
                            }
                            Rectangle {
                                width: parent.width; height: 5; color: "#354750"; radius: 1
                                Rectangle {
                                    width: parent.width * line.progress
                                    height: parent.height; color: line.progressTint
                                }
                            }
                        }
                    }
                    Item {
                        width: cells.width * root.fractions[2]; height: parent.height
                        Column {
                            width: Math.max(0, parent.width - 14)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                width: parent.width
                                visible: effects.count === 0
                                text: line.invincible ? "无敌 " + line.robot.invincibleLeft + "s"
                                    : line.reviving ? "复活 " + line.robot.respawnLeft + "s"
                                    : line.robot.hp === 0 ? "◇ 战亡"
                                    : line.heavy ? (line.motion?.transforming ? "变形中" : Format.heavyStatus(line.robot.heavy))
                                    : line.robot.sentry ? "○ " + ["—", "攻", "守", "移"][line.robot.sentry.mode]
                                      + (line.robot.sentry.powered ? " 强化" : "")
                                      + (line.robot.sentry.cooldown > 0 ? " ≈" + line.robot.sentry.cooldown + "s" : "")
                                    : line.robot.number === 6 ? "— 单机状态未上报" : line.robot.hp === undefined ? "— 待上报" : "○ 在场"
                                color: line.invincible || line.reviving ? line.progressTint
                                    : line.robot.hp === 0 ? "#ff9b8d"
                                    : line.robot.heavy?.installedAt > 0 ? Format.heavyGold()
                                    : line.robot.heavy?.allowed === true ? Format.heavyAccent(root.blue) : "#c2d5e1"
                                font.pixelSize: root.width < 580 ? 10 : 12
                                elide: Text.ElideRight
                            }
                            Repeater {
                                id: effects
                                model: line.invincible || line.reviving ? [] : (line.robot.effects || []).slice(0, 2)
                                DashboardEffectBadge {
                                    required property var modelData
                                    width: Math.max(0, line.width * root.fractions[2] - 16)
                                    height: 15
                                    effect: modelData
                                }
                            }
                        }
                    }
                    Text {
                        width: cells.width * root.fractions[3]; height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        text: Format.number(line.robot.ammo)
                        font.pixelSize: root.compact ? 12 : 15
                        color: line.robot.ammo === undefined ? "#9aafbf" : "#a5dacb"
                    }
                    Text {
                        width: cells.width * root.fractions[4]; height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        text: line.robot.heatLimit === undefined ? "—"
                            : (line.robot.heat === undefined ? "—" : Math.round(line.robot.heat))
                              + " / " + line.robot.heatLimit
                        font.pixelSize: root.compact ? 12 : 15
                        color: line.robot.heatPenalty ? "#ff9b8d" : line.robot.heat === undefined ? "#adbfcc" : "#e8c494"
                        ToolTip.visible: heatPointer.hovered && line.robot.heatCooling !== undefined
                        ToolTip.text: "冷却 " + line.robot.heatCooling + "/s"
                        HoverHandler { id: heatPointer }
                    }
                    Text {
                        width: cells.width * root.fractions[5]; height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        text: line.robot.maxPower === undefined ? "—" : line.robot.maxPower + " W"
                        font.pixelSize: root.compact ? 12 : 15
                        color: "#e4edf3"
                    }
                }
                Loader {
                    id: heavyEffect
                    objectName: line.heavy ? (root.blue ? "blueSummaryHeavyEffects" : "redSummaryHeavyEffects") : ""
                    anchors.fill: parent
                    z: 10
                    active: line.heavy
                    sourceComponent: DashboardHeavyEffects {
                        teamColor: Format.heavyAccent(root.blue)
                        gold: Format.heavyGold()
                        allowed: line.robot.heavy?.allowed === true
                        installedAt: line.robot.heavy?.installedAt || 0
                        portraitBounds: Qt.rect(cells.x + portrait.x, portraitRow.y + portrait.y,
                                                portrait.width, portrait.height)
                    }
                }
            }
        }
    }
}
