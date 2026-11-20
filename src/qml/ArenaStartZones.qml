pragma ComponentBehavior: Bound

import QtQuick 2.15

Item {
    id: root

    // RMUL 1V1: 1 m × 1 m start zones within the 5 m × 5 m playable floor.
    property bool mirrored: false

    Repeater {
        model: [true, false]

        Rectangle {
            id: zone
            required property bool modelData
            readonly property bool topLeft: zone.modelData !== root.mirrored
            readonly property color tint: zone.modelData ? "#e88678" : "#82b9f3"
            width: root.width / 5
            height: root.height / 5
            x: zone.topLeft ? 0 : root.width - width
            y: zone.topLeft ? 0 : root.height - height
            color: Qt.rgba(zone.tint.r, zone.tint.g, zone.tint.b, 0.17)
            border.color: Qt.rgba(zone.tint.r, zone.tint.g, zone.tint.b, 0.65)
            border.width: Math.max(1, root.width / 600)
        }
    }
}
