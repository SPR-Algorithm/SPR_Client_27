pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    required property color teamColor
    required property color gold
    required property rect portraitBounds
    property bool allowed: false
    property double installedAt: 0
    property real phase: 1
    property real charge: (allowed || installedAt > 0) ? 1 : 0
    property real edgeTravel
    readonly property int transitionDuration: 1000
    readonly property bool transforming: installedAt > 0 && phase < 1
    readonly property bool hero: installedAt > 0 && phase >= 0.525
    readonly property real heroMix: installedAt > 0 ? easeWindow(phase, 0.41, 0.67) : 0
    readonly property color ionColor: blend(teamColor, gold, installedAt > 0 ? easeWindow(phase, 0.20, 0.82) : 0)

    function easeWindow(value, start, end) {
        const p = Math.max(0, Math.min(1, (value - start) / (end - start)))
        return p * p * (3 - 2 * p)
    }

    function blend(from, to, fraction) {
        return Qt.rgba(from.r + (to.r - from.r) * fraction,
                      from.g + (to.g - from.g) * fraction,
                      from.b + (to.b - from.b) * fraction, 1)
    }

    function synchronize() {
        transformation.stop()
        const elapsed = installedAt > 0 ? Math.max(0, Date.now() - installedAt) : transitionDuration
        phase = Math.min(1, elapsed / transitionDuration)
        if (visible && installedAt > 0 && elapsed < transitionDuration) {
            transformation.duration = Math.max(1, transitionDuration - Math.round(elapsed))
            transformation.start()
        }
    }

    onInstalledAtChanged: synchronize()
    onVisibleChanged: synchronize()
    Component.onCompleted: synchronize()

    NumberAnimation {
        id: transformation
        target: root
        property: "phase"
        to: 1
    }
    Behavior on charge { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    NumberAnimation on edgeTravel {
        from: 0
        to: 1
        duration: 2650
        loops: Animation.Infinite
        running: root.visible && root.charge > 0
    }

    function paintEdge(ctx, w, h) {
        if (charge <= 0)
            return
        const corners = [[2, 2], [w - 2, 2], [w - 2, h - 2], [2, h - 2], [2, 2]]
        ctx.save()
        ctx.globalAlpha = charge
        ctx.beginPath()
        ctx.moveTo(2, 2)
        for (let side = 0; side < 4; ++side) {
            const [x, y] = corners[side]
            const [nextX, nextY] = corners[side + 1]
            const vertical = side % 2 !== 0
            const steps = Math.max(4, Math.round((vertical ? h : w) / 12))
            for (let index = 1; index < steps; ++index) {
                const t = index / steps
                const offset = Math.sin(side * 3.2 + index * 3.04) * (index % 4 === 1 ? 1.8 : 0.8)
                ctx.lineTo(x + (nextX - x) * t + (vertical ? offset : 0),
                           y + (nextY - y) * t + (vertical ? 0 : offset))
            }
            ctx.lineTo(nextX, nextY)
        }
        ctx.closePath()
        ctx.lineJoin = "round"
        ctx.lineWidth = 3.8
        ctx.strokeStyle = Qt.alpha(ionColor, 0.25)
        ctx.stroke()
        ctx.lineWidth = 0.9
        ctx.strokeStyle = ionColor
        ctx.stroke()
        const perimeter = 2 * (w + h)
        ctx.setLineDash([0.054, 0.142, 0.024, 0.281, 0.079, 0.420].map(fraction => fraction * perimeter))
        ctx.lineDashOffset = -edgeTravel * perimeter
        ctx.lineWidth = 1.5
        ctx.strokeStyle = blend(ionColor, Qt.rgba(1, 1, 1, 1), 0.55)
        ctx.stroke()
        ctx.restore()
    }

    function paintPortraitEnergy(ctx) {
        const bounds = portraitBounds
        if (bounds.width <= 0 || bounds.height <= 0)
            return
        const p = phase
        const pull = easeWindow(p, 0.08, 0.54)
        const glow = easeWindow(p, 0.11, 0.45) * (1 - easeWindow(p, 0.55, 0.88))
        const spiralOpacity = easeWindow(p, 0.07, 0.25) * (1 - easeWindow(p, 0.57, 0.93))
        const x = bounds.x + bounds.width * (0.19 + 0.64 * easeWindow(p, 0.10, 0.69))
        const y = bounds.y + bounds.height * 0.51
        const radius = Math.max(bounds.width, bounds.height) * (0.55 - 0.11 * pull)
        ctx.save()
        const aura = ctx.createRadialGradient(x, y, 0, x, y, radius)
        aura.addColorStop(0, Qt.rgba(1, 0.966, 0.85, glow * 0.78))
        aura.addColorStop(0.27, Qt.rgba(1, 0.89, 0.69, glow * 0.42))
        aura.addColorStop(0.63, Qt.rgba(1, 0.78, 0.45, glow * 0.10))
        aura.addColorStop(1, "transparent")
        ctx.fillStyle = aura
        ctx.fillRect(x - radius, y - radius, radius * 2, radius * 2)

        ctx.translate(bounds.x + bounds.width / 2, y)
        ctx.rotate((-55 + 325 * p) * Math.PI / 180)
        const scale = (1.35 - 1.0 * pull) * Math.max(bounds.width, bounds.height) / 100
        ctx.scale(scale, scale)
        ctx.globalAlpha = spiralOpacity
        const spiral = ctx.createRadialGradient(0, 0, 0, 0, 0, 55)
        spiral.addColorStop(0, "#fff9d9")
        spiral.addColorStop(0.52, "#ffc76e")
        spiral.addColorStop(0.82, "#eca446")
        spiral.addColorStop(1, Qt.rgba(1, 0.82, 0.47, 0.28))
        ctx.fillStyle = spiral
        for (let arm = 0; arm < 4; ++arm) {
            ctx.beginPath()
            for (let step = 0; step <= 40; ++step) {
                const t = (step < 20 ? step : 40 - step) / 20
                const angle = arm * Math.PI / 2 + t * 2.55
                const fraction = Math.sin(t * Math.PI) * (3.3 - t)
                const r = 55 - t * 50 + (step < 20 ? -fraction : fraction)
                const px = Math.cos(angle) * r
                const py = Math.sin(angle) * r
                if (step === 0)
                    ctx.moveTo(px, py)
                else
                    ctx.lineTo(px, py)
            }
            ctx.closePath()
            ctx.fill()
        }
        ctx.restore()
    }

    function crestPath(ctx) {
        ctx.moveTo(-38, -18)
        ctx.bezierCurveTo(-13, 2, -27, 15, 1, 34)
        ctx.bezierCurveTo(25, 50, 14, 63, -3, 70)
        ctx.bezierCurveTo(-27, 82, 13, 92, 10, 108)
        ctx.bezierCurveTo(9, 126, -3, 137, 12, 155)
    }

    function paintWave(ctx, w, h) {
        const p = phase
        ctx.save()
        ctx.globalAlpha = easeWindow(p, 0, 0.09) * (1 - easeWindow(p, 0.90, 1))
        ctx.scale(w / 400, h / 144)
        ctx.translate(-47 + 550 * easeWindow(p, 0, 1), 0)
        const tide = ctx.createLinearGradient(-150, 0, 17, 0)
        tide.addColorStop(0, Qt.alpha(ionColor, 0))
        tide.addColorStop(0.55, Qt.alpha(ionColor, 0.31))
        tide.addColorStop(0.89, Qt.alpha(ionColor, 0.92))
        tide.addColorStop(1, "#defaf0d9")
        ctx.fillStyle = tide
        ctx.beginPath()
        crestPath(ctx)
        ctx.lineTo(-158, 155)
        ctx.lineTo(-158, -18)
        ctx.closePath()
        ctx.fill()
        ctx.beginPath()
        crestPath(ctx)
        ctx.strokeStyle = "#eafff4dd"
        ctx.lineWidth = 2.3
        ctx.stroke()
        ctx.beginPath()
        ctx.moveTo(-38, 35)
        ctx.bezierCurveTo(-25, 53, 14, 53, 7, 45)
        ctx.bezierCurveTo(3, 40, -6, 47, -2, 50)
        ctx.moveTo(-40, 85)
        ctx.quadraticCurveTo(-23, 74, -10, 84)
        ctx.moveTo(-32, 125)
        ctx.quadraticCurveTo(-9, 111, -7, 121)
        ctx.lineWidth = 1.6
        ctx.strokeStyle = "#b5fff2dc"
        ctx.lineCap = "round"
        ctx.stroke()
        ctx.restore()
    }

    Canvas {
        id: paintArea
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (width < 4 || height < 4)
                return
            root.paintEdge(ctx, width, height)
            if (root.transforming) {
                root.paintPortraitEnergy(ctx)
                root.paintWave(ctx, width, height)
            }
        }
    }
    onChargeChanged: paintArea.requestPaint()
    onEdgeTravelChanged: paintArea.requestPaint()
    onIonColorChanged: paintArea.requestPaint()
    onPhaseChanged: paintArea.requestPaint()
    onPortraitBoundsChanged: paintArea.requestPaint()
}
