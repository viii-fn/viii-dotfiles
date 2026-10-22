// File: ~/viii-shell-2/shell/StatBlock.qml
// A small right-aligned label + value pair.
//   StatBlock { label: "DAILY AVG"; value: "2h 10m" }
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: s

    property string label: ""
    property string value: ""

    spacing: 0
    Text {
        Layout.alignment: Qt.AlignRight
        text: s.label
        color: Theme.fgDim
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 8
        font.letterSpacing: 1.2
    }
    Text {
        Layout.alignment: Qt.AlignRight
        text: s.value
        color: Theme.fg
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 17
        font.weight: Font.DemiBold
    }
}