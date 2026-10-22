// File: ~/viii-shell-2/shell/HairSlider.qml
// Hairline slider. Click or drag to set, double-click to zero.

import QtQuick

Item {
    id: sl
    property string label: ""
    property real value: 0
    property real from: -45
    property real to: 45
    signal moved(real v)
    implicitWidth: 200
    implicitHeight: 34

    Text {
        anchors.left: parent.left
        anchors.top: parent.top
        text: sl.label
        color: Theme.fgDim
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 9
        font.letterSpacing: 2.5
    }
    Text {
        anchors.right: parent.right
        anchors.top: parent.top
        text: sl.value.toFixed(1) + "°"
        color: sl.value !== 0 ? Theme.accentHi : Theme.fg
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 9
    }
    Rectangle {
        id: trk
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 7
        height: 1
        color: Qt.rgba(1, 1, 1, 0.3)
    }
    Rectangle {   // zero tick
        x: (-sl.from) / (sl.to - sl.from) * trk.width
        anchors.verticalCenter: trk.verticalCenter
        width: 1
        height: 7
        color: Qt.rgba(1, 1, 1, 0.4)
    }
    Rectangle {   // knob
        width: 9
        height: 9
        rotation: 45
        color: Theme.accentHi
        x: (sl.value - sl.from) / (sl.to - sl.from) * trk.width - width / 2
        anchors.verticalCenter: trk.verticalCenter
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        function setFrom(mx) {
            const f = Math.max(0, Math.min(1, mx / width))
            sl.moved(Math.round((sl.from + f * (sl.to - sl.from)) * 2) / 2)
        }
        onPressed: (m) => setFrom(m.x)
        onPositionChanged: (m) => { if (pressed) setFrom(m.x) }
        onDoubleClicked: sl.moved(0)
    }
}
