// File: ~/viii-shell-2/shell/HexSlider.qml
// A thin bar with a hexagon handle. `value` is 0..1; `moved(v)` fires when the
// user presses or drags (live: true) or when they let go (live: false).
//
//   HexSlider { width: 200; value: 0.4; onMoved: v => doSomething(v) }
import QtQuick

Item {
    id: s

    property real value: 0
    property bool live: true
    property color tone: Theme.accent
    property color trackColor: Theme.surface
    signal moved(real v)

    implicitHeight: 18

    readonly property real v: isNaN(value) ? 0 : Math.max(0, Math.min(1, value))
    readonly property real hw: 14
    readonly property real hh: hw / 1.1547

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width; height: 4
        color: s.trackColor
    }
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        height: 4
        width: handle.x + s.hw / 2
        color: s.tone
    }
    HexShape {
        id: handle
        anchors.verticalCenter: parent.verticalCenter
        width: s.hw; height: s.hh
        x: s.v * (s.width - s.hw)
        fillColor: s.tone
        strokeColor: Theme.bg
        strokeWidth: 2
    }

    MouseArea {
        anchors { fill: parent; topMargin: -6; bottomMargin: -6 }
        preventStealing: true
        function frac(m) { return Math.max(0, Math.min(1, m.x / width)) }
        onPressed: mouse => { if (s.live) s.moved(frac(mouse)) }
        onPositionChanged: mouse => { if (s.live && pressed) s.moved(frac(mouse)) }
        onReleased: mouse => { if (!s.live) s.moved(frac(mouse)) }
    }
}
