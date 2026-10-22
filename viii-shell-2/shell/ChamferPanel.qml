// File: ~/viii-shell-2/shell/ChamferPanel.qml
// A rectangle with cut corners (the hive look for panels, rows and buttons).
// Put your content inside it like in any Item. Colors default to the theme.
//
//   ChamferPanel { width: 300; height: 200; cut: 16; pattern: true
//                  Text { text: "hello"; color: Theme.fg } }
import QtQuick
import QtQuick.Shapes

Item {
    id: cp

    property real cut: 14                                  // size of the cut corners
    property color fillColor: Theme.panel
    property color strokeColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.5)
    property real strokeWidth: 1
    property bool pattern: false                           // faint honeycomb inside
    property real patternOpacity: 0.07

    readonly property real c: Math.min(cut, width / 2, height / 2)
    readonly property real p: strokeWidth > 0 ? strokeWidth / 2 : 0

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: cp.fillColor
            strokeColor: cp.strokeColor
            strokeWidth: cp.strokeWidth > 0 ? cp.strokeWidth : -1
            joinStyle: ShapePath.RoundJoin
            startX: cp.c; startY: cp.p
            PathLine { x: cp.width - cp.c;  y: cp.p }
            PathLine { x: cp.width - cp.p;  y: cp.c }
            PathLine { x: cp.width - cp.p;  y: cp.height - cp.c }
            PathLine { x: cp.width - cp.c;  y: cp.height - cp.p }
            PathLine { x: cp.c;             y: cp.height - cp.p }
            PathLine { x: cp.p;             y: cp.height - cp.c }
            PathLine { x: cp.p;             y: cp.c }
            PathLine { x: cp.c;             y: cp.p }
        }
    }

    // Painted once; kept out of the cut corners so nothing pokes outside the shape.
    Loader {
        active: cp.pattern
        x: cp.c
        width: Math.max(0, cp.width - 2 * cp.c)
        height: cp.height
        opacity: cp.patternOpacity
        sourceComponent: HexPattern {}
    }
}
