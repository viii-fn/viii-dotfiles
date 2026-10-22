// File: ~/viii-shell-2/shell/HexPattern.qml
// A faint honeycomb of flat-top hexagon outlines, drawn ONE time on a Canvas
// (and again only if the item is resized). It is white; set `opacity` to
// control how visible it is, so it never needs repainting on a theme fade.
//
//   HexPattern { width: 400; height: 300; opacity: 0.06 }
import QtQuick

Canvas {
    id: cv

    property real radius: 9          // hexagon radius (center to corner)
    property real lineWidth: 1
    property color stroke: "white"

    onAvailableChanged: if (available) requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        ctx.lineWidth = lineWidth
        ctx.strokeStyle = stroke.toString()

        var r = radius
        var h = Math.sqrt(3) * r            // hexagon height
        ctx.beginPath()
        for (var col = 0; col * 1.5 * r - r < width; col++) {
            var cx = col * 1.5 * r
            var off = (col % 2) ? h / 2 : 0
            for (var cy = off - h; cy < height + h; cy += h) {
                for (var k = 0; k < 6; k++) {
                    var a = Math.PI / 3 * k
                    var px = cx + r * Math.cos(a)
                    var py = cy + r * Math.sin(a)
                    if (k === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py)
                }
                ctx.closePath()
            }
        }
        ctx.stroke()
    }
}
