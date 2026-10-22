// File: ~/viii-shell-2/shell/GlassSlider.qml
// A rounded slider with a round knob. `value` is 0..1; `moved(v)` fires when the
// user presses or drags (live: true) or when they let go (live: false).
// Same properties as HexSlider, so it can replace it anywhere.
//
//   GlassSlider { width: 200; value: 0.4; onMoved: v => doSomething(v) }
import QtQuick

Item {
    id: s

    property real value: 0
    property bool live: true
    property color tone: Theme.accent
    property color trackColor: Qt.rgba(1, 1, 1, 0.12)
    signal moved(real v)

    implicitHeight: 22

    readonly property real v: isNaN(value) ? 0 : Math.max(0, Math.min(1, value))
    readonly property real hs: 16               // knob size

    // track
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width; height: 6; radius: 3
        color: s.trackColor
    }
    // filled part, ends in the middle of the knob
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: knob.x + s.hs / 2; height: 6; radius: 3
        color: s.tone
    }
    // knob
    Rectangle {
        id: knob
        anchors.verticalCenter: parent.verticalCenter
        width: s.hs; height: s.hs; radius: s.hs / 2
        x: s.v * (s.width - s.hs)
        color: Theme.fg
    }

    MouseArea {
        anchors { fill: parent; topMargin: -6; bottomMargin: -6 }
        preventStealing: true
        // mouse position -> 0..1, measured between the knob's centre at each end
        function frac(m) { return Math.max(0, Math.min(1, (m.x - s.hs / 2) / (width - s.hs))) }
        onPressed: mouse => { if (s.live) s.moved(frac(mouse)) }
        onPositionChanged: mouse => { if (s.live && pressed) s.moved(frac(mouse)) }
        onReleased: mouse => { if (!s.live) s.moved(frac(mouse)) }
    }
}