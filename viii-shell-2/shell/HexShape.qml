// File: ~/viii-shell-2/shell/HexShape.qml
// A flat-top hexagon you can size to anything. `inset` (the width of the
// slanted corners) is derived from the height so every corner stays at the
// honeycomb angle of 60 degrees, whatever width you give it.
// For a perfectly regular hexagon use width = height * 1.1547.
//
//   HexShape { width: 35; height: 30; fillColor: Theme.surface; strokeColor: Theme.accent; strokeWidth: 1 }
import QtQuick
import QtQuick.Shapes

Shape {
    id: hex

    property color fillColor: "transparent"
    property color strokeColor: "transparent"
    property real strokeWidth: 0
    property real inset: height * 0.28868

    // The outline is drawn on the path, so pull the path in by half the stroke
    // width to keep the whole stroke inside this item's bounds.
    readonly property real p: strokeWidth > 0 ? strokeWidth / 2 : 0
    readonly property real w: Math.max(1, width - 2 * p)
    readonly property real h: Math.max(1, height - 2 * p)
    readonly property real i: Math.min(inset, w / 2)

    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        fillColor: hex.fillColor
        strokeColor: hex.strokeColor
        strokeWidth: hex.strokeWidth > 0 ? hex.strokeWidth : -1
        joinStyle: ShapePath.RoundJoin

        startX: hex.p + hex.i
        startY: hex.p
        PathLine { x: hex.p + hex.w - hex.i; y: hex.p }
        PathLine { x: hex.p + hex.w;         y: hex.p + hex.h / 2 }
        PathLine { x: hex.p + hex.w - hex.i; y: hex.p + hex.h }
        PathLine { x: hex.p + hex.i;         y: hex.p + hex.h }
        PathLine { x: hex.p;                 y: hex.p + hex.h / 2 }
        PathLine { x: hex.p + hex.i;         y: hex.p }
    }
}
