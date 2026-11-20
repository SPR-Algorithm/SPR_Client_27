pragma ComponentBehavior: Bound

import QtQuick 2.15

Canvas {
    id: root

    property color redSurface: "#493038"
    property color blueSurface: "#31445d"

    onRedSurfaceChanged: requestPaint()
    onBlueSurfaceChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        const radians = 16 * Math.PI / 180
        const dx = Math.cos(radians)
        const dy = Math.sin(radians)
        const length = Math.max(65, width * dx + height * dy)
        const gradient = ctx.createLinearGradient((width - length * dx) / 2, (height - length * dy) / 2,
                                                  (width + length * dx) / 2, (height + length * dy) / 2)
        gradient.addColorStop(0, Qt.tint(root.redSurface, "#47101820"))
        gradient.addColorStop(0.21, root.redSurface)
        gradient.addColorStop(0.5 - 9 / length, Qt.tint(root.redSurface, "#670e151d"))
        gradient.addColorStop(0.5 - 8 / length, "#68555c")
        gradient.addColorStop(0.5 - 6 / length, "#0c131a")
        gradient.addColorStop(0.5 + 6 / length, "#0c131a")
        gradient.addColorStop(0.5 + 8 / length, "#526573")
        gradient.addColorStop(0.5 + 9 / length, Qt.tint(root.blueSurface, "#670e151d"))
        gradient.addColorStop(0.79, root.blueSurface)
        gradient.addColorStop(1, Qt.tint(root.blueSurface, "#47101820"))
        ctx.clearRect(0, 0, width, height)
        ctx.fillStyle = gradient
        ctx.fillRect(0, 0, width, height)
    }
}
