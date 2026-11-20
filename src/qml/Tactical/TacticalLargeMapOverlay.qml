import QtQuick 2.15

Item {
    id: tacticalLargeMapOverlay

    objectName: "tacticalLargeMapOverlay"
    property var pageRoot: null
    readonly property bool currentSeason: pageRoot && pageRoot.gameDataContext
        ? Boolean(pageRoot.gameDataContext.uses2027Protocol) : false
    readonly property real fieldAspect: currentSeason
        ? pageRoot.gameDataContext.fieldWidth / pageRoot.gameDataContext.fieldHeight : 1
    // At scale 1 the 840 px panel leaves 20 px for side margins and 64 px for the header and footer.
    readonly property real mapAspectRatio: currentSeason
        ? 840 / (820 / fieldAspect + 64) : 840 / 474
    readonly property real mapWidth: currentSeason
        ? Math.max(0, Math.min(width - 80, (height - 120) * mapAspectRatio))
        : Math.min(width, height * mapAspectRatio)
    readonly property real mapHeight: mapWidth / mapAspectRatio
    readonly property real mapVisualScale: mapWidth / 840

    Rectangle {
        anchors.fill: parent
        color: "#10191f"
    }

    MouseArea {
        objectName: "tacticalLargeMapInputBlocker"
        anchors.fill: parent
        z: 0
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        preventStealing: true
        onPressed: function(mouse) { mouse.accepted = true }
        onWheel: function(wheel) { wheel.accepted = true }
    }

    TacticalRadarMap {
        id: tacticalLargeMap

        objectName: "tacticalLargeMap"
        width: tacticalLargeMapOverlay.mapWidth
        height: tacticalLargeMapOverlay.mapHeight
        anchors.centerIn: parent
        anchors.verticalCenterOffset: tacticalLargeMapOverlay.currentSeason ? -10 : 0
        z: 1
        visualScale: tacticalLargeMapOverlay.mapVisualScale
        largeView: true
        threadedCanvasRendering: true
        model: pageRoot ? pageRoot.tacticalMapModel : null
        allyStatusModel: pageRoot ? pageRoot.allyRobotsForMap : []
        enemyStatusModel: pageRoot ? pageRoot.enemyRobotsForMap : []
        allyIsBlue: pageRoot ? pageRoot.allyIsBlue : false
        enemyIsBlue: pageRoot ? pageRoot.enemyIsBlue : true
        backgroundSource: pageRoot ? pageRoot.tacticalMapBackgroundSource : ""
        viewMirrored: pageRoot ? pageRoot.tacticalMapViewMirrored : false
        pageRoot: tacticalLargeMapOverlay.pageRoot
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        z: 2
        width: largeMapHintText.implicitWidth + 32
        height: largeMapHintText.implicitHeight + 16
        radius: 4
        color: "#1d2b33"
        border.color: "#52656c"
        border.width: 1

        Text {
            id: largeMapHintText

            anchors.centerIn: parent
            text: "M 返回普通指挥屏"
            color: "#effbff"
            font.pixelSize: 14
            font.bold: true
        }
    }
}
