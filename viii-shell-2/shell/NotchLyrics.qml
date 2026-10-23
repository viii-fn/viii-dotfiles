// File: ~/viii-shell-2/shell/NotchLyrics.qml
// Synced lyrics inside the notch. Loaded by Notch.qml, which sets `n`.
import QtQuick

Item {
    id: root
    property var n: null
    readonly property string mono: "JetBrainsMono Nerd Font"

    Column {
        anchors.fill: parent
        anchors.margins: 20
        anchors.topMargin: 0
        spacing: 4

        Text {
            width: parent.width; elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            font.family: root.mono; font.pixelSize: 12; font.weight: Font.DemiBold
            color: Theme.accentHi
            text: root.n && root.n.parsedTitle !== "" ? root.n.parsedTitle : "it's quiet here"
        }
        Text {
            width: parent.width; elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            font.family: root.mono; font.pixelSize: 10
            color: Theme.fgDim
            text: root.n ? root.n.parsedArtist : ""
        }
    }

    Item {
        anchors.fill: parent
        anchors.topMargin: 40
        anchors.margins: 20
        clip: true

        Text {
            anchors.centerIn: parent
            visible: !root.n || root.n.lines.length === 0
            text: root.n ? root.n.status : ""
            color: Theme.fgDim; font.family: root.mono; font.pixelSize: 12
        }
        Column {
            anchors.centerIn: parent
            width: parent.width
            spacing: 12
            visible: root.n && root.n.lines.length > 0
            Repeater {
                model: 5
                delegate: Text {
                    required property int index
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.family: root.mono
                    font.pixelSize: index === 2 ? 16 : 12
                    font.weight: index === 2 ? Font.Bold : Font.Normal
                    color: index === 2 ? Theme.accentHi : Theme.fg
                    opacity: index === 2 ? 1 : (Math.abs(index - 2) === 1 ? 0.45 : 0.2)
                    text: root.n ? root.n.lineAt(root.n.lyricIdx + index - 2) : ""
                }
            }
        }
    }
}
