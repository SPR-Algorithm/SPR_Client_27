pragma ComponentBehavior: Bound

import QtQuick 2.15

Row {
    id: root

    property var buffs: ({})
    property real visualScale: 1
    readonly property var defense: root.buffs.defenseOrVulnerability || ({})
    readonly property var cooling: root.buffs.cooling || ({})
    readonly property var preparation: root.buffs.terrainPrewarn || ({})
    readonly property string defenseText: root.effectText(root.defense, true)
    readonly property string coolingText: root.effectText(root.cooling, false)
    readonly property string preparationText: Number(root.preparation.leftTime) > 0
        ? qsTr("跨越预备  %1 s").arg(root.preparation.leftTime)
        : (Number(root.preparation.level) > 0 && !Number(root.preparation.maxTime)
                ? qsTr("跨越预备") : "")
    spacing: 5 * root.visualScale
    visible: root.defenseText.length + root.coolingText.length + root.preparationText.length > 0

    function effectText(buff, defenseType) {
        const level = Number(buff.level) || 0
        const seconds = Number(buff.leftTime) || 0
        const maxTime = Number(buff.maxTime) || 0
        if (!level || (maxTime > 0 && seconds <= 0))
            return ""
        const effect = defenseType
            ? (level > 0 ? qsTr("防御 +%1%").arg(level) : qsTr("易伤 %1%").arg(-level))
            : qsTr("冷却 %1/s").arg(level > 0 ? "+" + level : level)
        return seconds > 0 ? effect + "  " + seconds + " s" : effect
    }

    Repeater {
        model: [
            { text: root.preparationText, tint: "#e4bc86" },
            { text: root.defenseText, tint: Number(root.defense.level) > 0 ? "#a4dfc7" : "#f18a80" },
            { text: root.coolingText, tint: "#a9d1f3" }
        ]

        Rectangle {
            id: chip

            required property var modelData
            visible: chip.modelData.text.length > 0
            width: chipLabel.implicitWidth + 12 * root.visualScale
            height: chipLabel.implicitHeight + 4 * root.visualScale
            radius: 3 * root.visualScale
            color: "#19272e"
            border.color: "#5b7375"
            border.width: 1

            Text {
                id: chipLabel
                anchors.centerIn: parent
                text: chip.modelData.text
                font.pixelSize: Math.max(10, 10 * root.visualScale)
                color: chip.modelData.tint
            }
        }
    }
}
