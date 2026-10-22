// File: ~/viii-shell-2/shell/PillBtn.qml
// A glass pill text button. `primary: true` fills it with the accent color.
// Set `enabled: false` to dim it and ignore clicks.
//
//   PillBtn { text: "SET IN  [I]"; onClicked: doSomething() }
//   PillBtn { text: "EXPORT  ↗"; primary: true }
import QtQuick

Rectangle {
    id: b

    property string text: ""
    property bool primary: false
    signal clicked()

    implicitHeight: 38
    implicitWidth: label.implicitWidth + 32
    radius: height / 2

    color: primary ? Theme.accent
         : (hit.pressed ? Qt.rgba(1, 1, 1, 0.16)
         : (hit.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.07)))
    border.width: 1
    border.color: primary ? Theme.accentHi : Qt.rgba(1, 1, 1, 0.12)
    opacity: enabled ? 1 : 0.42
    Behavior on color { ColorAnimation { duration: 120 } }

    // small press-in, like a real button
    scale: hit.pressed ? 0.96 : 1
    Behavior on scale { NumberAnimation { duration: 80 } }

    Text {
        id: label
        anchors.centerIn: parent
        text: b.text
        color: b.primary ? Theme.accentText : Theme.fg
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 11
        font.weight: Font.DemiBold
    }
    MouseArea {
        id: hit
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: b.clicked()
    }
}
