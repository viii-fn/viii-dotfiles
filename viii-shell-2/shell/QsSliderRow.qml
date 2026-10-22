import QtQuick
import QtQuick.Layouts

// Icon + your HexSlider + percentage, with throttled output for shell commands.
//   QsSliderRow { glyph: "\uf028"; value: 0.4; onMoved: v => doSomething(v) }
RowLayout {
    id: r

    property real value: 0              // 0..1, set from outside
    property string glyph: ""
    property bool dim: false            // e.g. muted
    signal moved(real v)                // throttled, always ends with the final value
    signal iconClicked()

    // While dragging, the handle follows the pointer instead of waiting for the system to report back
    property real local: -1
    readonly property real shown: local >= 0 ? local : value
    property real last: 0
    property bool pending: false

    Layout.fillWidth: true
    spacing: 12

    Timer {
        id: throttle
        interval: 70
        onTriggered: if (r.pending) { r.pending = false; r.moved(r.last) }
    }
    // Give control back to the real value shortly after the drag ends
    Timer {
        id: release
        interval: 600
        onTriggered: r.local = -1
    }

    function push(v) {
        last = v
        if (!throttle.running) { moved(v); throttle.start() }
        else pending = true
    }

    Item {
        Layout.preferredWidth: 34
        Layout.preferredHeight: 34

        HexShape {
            anchors.fill: parent
            fillColor: Theme.surfaceHi
            strokeWidth: 0
        }
        Text {
            anchors.centerIn: parent
            text: r.glyph
            color: r.dim ? Theme.fgDim : Theme.accentHi
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 14
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: r.iconClicked()
        }
    }

    HexSlider {
        Layout.fillWidth: true
        Layout.preferredHeight: 18
        value: r.shown
        tone: r.dim ? Theme.fgDim : Theme.accent
        trackColor: Theme.surfaceHi
        onMoved: v => {
            r.local = v
            release.restart()
            r.push(v)
        }
    }

    Text {
        Layout.preferredWidth: 38
        horizontalAlignment: Text.AlignRight
        text: Math.round(r.shown * 100) + "%"
        color: Theme.fgDim
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 11
    }
}
