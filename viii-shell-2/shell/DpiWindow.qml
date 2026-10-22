// File: ~/viii-shell-2/shell/DpiWindow.qml
// The display-scale panel (same wlr-randr logic as before), glass style.
// Created by DpiPanel.qml on the first toggle, destroyed shortly after closing.
import QtQuick
import Quickshell
import Quickshell.Io

FloatingWindow {
    id: root
    title: "Display Scale"
    visible: true
    implicitWidth: 340
    implicitHeight: 260
    color: "transparent"

    property bool shown: false           // set by DpiPanel.qml
    signal closeRequested()

    // 0 = hidden, 1 = open. Starts at 0 and fades in once created.
    property real appear: 0
    Behavior on appear { NumberAnimation { duration: 0; easing.type: Easing.OutCubic } }
    Component.onCompleted: {
        appear = Qt.binding(() => root.shown ? 1 : 0)
        query.running = true             // read the current scale when the panel opens
    }
    onVisibleChanged: if (!visible) closeRequested()

    property real dpiScale: 1.0
    property var outputs: []

    function clamp(v) { return Math.max(0.5, Math.min(3.0, Math.round(v * 20) / 20)) }
    function nudge(d) { dpiScale = clamp(dpiScale + d); applyTimer.restart() }
    function setTo(v) { dpiScale = v; applyTimer.restart() }

    Process {
        id: query
        command: ["wlr-randr", "--json"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const on = JSON.parse(text).filter(o => o.enabled)
                root.outputs = on.map(o => o.name)
                if (on.length > 0) root.dpiScale = on[0].scale
            }
        }
    }

    Process { id: apply }

    // Wait 300 ms after the last click, then apply once (so fast clicking doesn't spam wlr-randr).
    Timer {
        id: applyTimer
        interval: 300
        onTriggered: {
            let cmd = ["wlr-randr"]
            for (const n of root.outputs)
                cmd.push("--output", n, "--scale", root.dpiScale.toFixed(2))
            apply.command = cmd
            apply.running = true
        }
    }

    // Glass body (no radius or border of its own: labwc rounds and outlines the window)
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Theme.panel, 0.82)
        opacity: root.appear

        // Specular sheen across the top
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
                GradientStop { position: 0.35; color: Qt.rgba(1, 1, 1, 0.0) }
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 22

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Display Scale"
                color: Theme.fgDim
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 12
            }

            // − 100% +
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 14

                IconBtn {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 52; height: 52; radius: 26
                    glyph: "−"; glyphSize: 24
                    tone: Theme.fg
                    onClicked: root.nudge(-0.1)
                }

                Text {
                    width: 110
                    height: 58
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: Math.round(root.dpiScale * 100) + "%"
                    color: Theme.accentHi
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 32
                    font.weight: Font.DemiBold
                }

                IconBtn {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 52; height: 52; radius: 26
                    glyph: "+"; glyphSize: 24
                    tone: Theme.fg
                    onClicked: root.nudge(0.1)
                }
            }

            // Presets: the one matching the current scale is highlighted
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8

                Repeater {
                    model: [1.0, 1.25, 1.5, 2.0]

                    delegate: Glass {
                        id: preset
                        required property var modelData
                        readonly property bool active: Math.abs(root.dpiScale - modelData) < 0.01

                        width: 64; height: 34; radius: 17
                        color: active ? Qt.alpha(Theme.accent, 0.20)
                                      : (presetHit.containsMouse ? Qt.rgba(1, 1, 1, 0.10)
                                                                 : Qt.rgba(1, 1, 1, 0.05))
                        border.color: active ? Theme.accent : Qt.rgba(1, 1, 1, 0.10)
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: Math.round(preset.modelData * 100) + "%"
                            color: preset.active ? Theme.accentHi : Theme.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            font.weight: preset.active ? Font.DemiBold : Font.Normal
                        }
                        MouseArea {
                            id: presetHit
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setTo(preset.modelData)
                        }
                    }
                }
            }
        }
    }
}