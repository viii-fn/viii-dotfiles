// File: ~/viii-shell-2/shell/HexButton.qml
// A hexagon icon button. `size` is its height; the width follows so the
// hexagon is regular.
//
//   HexButton { size: 34; glyph: "\uf04b"; onClicked: doSomething() }
//   HexButton { size: 44; filled: true; glyph: "\uf04c" }       // accent fill
//   HexButton { size: 24; outlined: true; interactive: false; glyph: "\uf1eb" }  // status icon
import QtQuick

Item {
    id: btn

    property string glyph: ""
    property int glyphSize: 15
    property real size: 34
    property bool filled: false
    property bool outlined: false
    property bool interactive: true
    property color tone: Theme.fg
    signal clicked()

    height: size
    width: size * 1.1547

    HexShape {
        anchors.fill: parent
        fillColor: btn.filled ? Theme.accent
                 : ((btn.interactive && hover.containsMouse) ? Theme.surface
                 : (btn.outlined ? Theme.surface : "transparent"))
        strokeColor: btn.outlined ? Theme.line : "transparent"
        strokeWidth: btn.outlined ? 1 : 0
    }
    Text {
        anchors.centerIn: parent
        text: btn.glyph
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: btn.glyphSize
        color: btn.filled ? Theme.accentText : btn.tone
    }
    MouseArea {
        id: hover
        anchors.fill: parent
        enabled: btn.interactive
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
