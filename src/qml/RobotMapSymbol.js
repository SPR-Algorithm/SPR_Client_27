.pragma library

// The disc is centered on the telemetry point. Only the bearing tick rotates.
function drawAlliedMarker(ctx, x, y, scale, team, self, heading, number) {
    const accent = self ? "#ade9d1" : team
    ctx.save()
    ctx.translate(x, y)
    ctx.scale(scale, scale)

    if (Number.isFinite(heading)) {
        ctx.save()
        ctx.rotate(heading * Math.PI / 180)
        ctx.fillStyle = accent
        ctx.strokeStyle = "#142128"
        ctx.lineWidth = 1.15
        ctx.lineJoin = "round"
        ctx.beginPath()
        ctx.moveTo(0, -16.3)
        ctx.lineTo(3.3, -11.6)
        ctx.lineTo(-3.3, -11.6)
        ctx.closePath()
        ctx.stroke()
        ctx.fill()
        ctx.restore()
    }

    ctx.beginPath()
    ctx.arc(0, 1.1, 12.4, 0, Math.PI * 2)
    ctx.fillStyle = "rgba(11,17,21,0.70)"
    ctx.fill()

    const bevel = ctx.createLinearGradient(-7, -12, 7, 12)
    bevel.addColorStop(0, "#9ab1b8")
    bevel.addColorStop(0.36, "#48636b")
    bevel.addColorStop(1, "#22343c")
    ctx.fillStyle = bevel
    ctx.beginPath()
    ctx.arc(0, 0, 11.1, 0, Math.PI * 2)
    ctx.fill()

    const face = ctx.createLinearGradient(-4, -9, 5, 9)
    face.addColorStop(0, "#475d66")
    face.addColorStop(0.49, "#23363e")
    face.addColorStop(1, "#172930")
    ctx.fillStyle = face
    ctx.beginPath()
    ctx.arc(0, 0, 8.8, 0, Math.PI * 2)
    ctx.fill()

    ctx.strokeStyle = team
    ctx.lineWidth = 1.35
    ctx.beginPath()
    ctx.arc(0, 0, 9.55, -1.34, 1.34)
    ctx.stroke()
    ctx.beginPath()
    ctx.arc(0, 0, 9.55, 1.80, 4.48)
    ctx.stroke()

    if (self) {
        ctx.strokeStyle = accent
        ctx.lineWidth = 1.35
        ctx.beginPath()
        ctx.arc(0, 0, 11.3, -.72, .72)
        ctx.stroke()
        ctx.beginPath()
        ctx.arc(0, 0, 11.3, 2.42, 3.86)
        ctx.stroke()
    }

    ctx.fillStyle = self ? "#d2f6e8" : "#f4f7f2"
    ctx.font = "bold 12px sans-serif"
    ctx.textAlign = "center"
    ctx.textBaseline = "middle"
    ctx.fillText(number, 0, 0.45)
    ctx.restore()
}
