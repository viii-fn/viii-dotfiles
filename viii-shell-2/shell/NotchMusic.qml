// File: ~/viii-shell-2/shell/NotchMusic.qml
// The notch grown into a player: big cover, title, draggable timeline, controls.
// Loaded by Notch.qml, which sets `n` (the notch window).
import QtQuick
import QtQuick.Effects

Item {
    id: root
    property var n: null
    readonly property var p: n ? n.player : null
    readonly property string mono: "JetBrainsMono Nerd Font"

    Row {
        anchors.fill: parent
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.topMargin: 2
        spacing: 18

        // cover
        Item {
            width: 150; height: 150

            Item {
                id: artStack
                anchors.fill: parent
                visible: false
                Rectangle { anchors.fill: parent; color: Theme.surface }
                Text {
                    anchors.centerIn: parent
                    text: "♪"; font.pixelSize: 48; color: Theme.fgDim
                    visible: art.status !== Image.Ready
                }
                Image {
                    id: art
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(300, 300)
                    source: root.p ? (root.p.trackArtUrl || "") : ""
                }
            }
            Rectangle {
                id: artMask
                anchors.fill: parent
                radius: 20
                visible: false
                layer.enabled: true
                layer.samples: 4
                color: "white"
            }
            MultiEffect {
                anchors.fill: parent
                source: artStack
                maskEnabled: true
                maskSource: artMask
            }
            Rectangle {
                anchors.fill: parent
                radius: 20
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.22)
            }
        }

        Column {
            width: parent.width - 150 - 18
            spacing: 6

            Text {
                width: parent.width; elide: Text.ElideRight
                font.family: root.mono; font.pixelSize: 15; font.weight: Font.Bold
                color: Theme.fg
                text: root.n && root.n.parsedTitle !== "" ? root.n.parsedTitle : "it's quiet here"
            }
            Text {
                width: parent.width; elide: Text.ElideRight
                font.family: root.mono; font.pixelSize: 11
                color: Theme.fgDim
                text: root.n ? root.n.parsedArtist : ""
            }

            Item { width: 1; height: 6 }

            // timeline: drag to seek
            HexSlider {
                width: parent.width
                live: false
                value: (root.p && root.p.length > 0) ? Math.min(1, root.p.position / root.p.length) : 0
                onMoved: v => { if (root.p && root.p.canSeek) root.p.position = v * root.p.length }
            }
            Item {
                width: parent.width; height: 12
                Text { anchors.left: parent.left; font.family: root.mono; font.pixelSize: 10; color: Theme.fgDim
                       text: root.p ? root.n.fmtSec(root.p.position) : "0:00" }
                Text { anchors.right: parent.right; font.family: root.mono; font.pixelSize: 10; color: Theme.fgDim
                       text: root.p ? root.n.fmtSec(root.p.length) : "0:00" }
            }

            // controls
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12
                IconBtn {
                    width: 36; height: 36; radius: 18
                    glyph: "\uf048"; glyphSize: 13; tone: Theme.fg
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: if (root.p) root.p.previous()
                }
                Rectangle {
                    width: 46; height: 46; radius: 23
                    color: Theme.accent
                    anchors.verticalCenter: parent.verticalCenter
                    scale: playHit.pressed ? 0.94 : 1
                    Behavior on scale { NumberAnimation { duration: 80 } }
                    Text {
                        anchors.centerIn: parent
                        text: (root.n && root.n.playing) ? "\uf04c" : "\uf04b"
                        color: Theme.accentText
                        font.family: root.mono; font.pixelSize: 17
                    }
                    MouseArea {
                        id: playHit
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.p) root.p.togglePlaying()
                    }
                }
                IconBtn {
                    width: 36; height: 36; radius: 18
                    glyph: "\uf051"; glyphSize: 13; tone: Theme.fg
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: if (root.p) root.p.next()
                }
            }
        }
    }
}
