// File: ~/viii-shell-2/shell/IconBtn.qml
// A round glass icon button.
//   IconBtn { glyph: "\uf021"; onClicked: doSomething() }
import QtQuick

Rectangle {
    id: b

    property string glyph: ""
    property int glyphSize: 12
    property color tone: Theme.fgDim
    signal clicked()

    width: 30; height: 30; radius: 15
    color: hit.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)
    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
        anchors.centerIn: parent
        text: b.glyph
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: b.glyphSize
        color: b.tone
    }
    MouseArea {
        id: hit
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: b.clicked()
    }
}