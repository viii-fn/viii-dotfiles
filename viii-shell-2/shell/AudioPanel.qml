// File: ~/viii-shell-2/shell/AudioPanel.qml
// Audio output picker, glass style. The window is created on the first toggle
// and destroyed shortly after it closes.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Scope {
    id: root

    property bool shown: false
    property bool alive: false           // true while the window exists (open + closing)
    readonly property int closeMs: 0

    onShownChanged: {
        if (shown) { unload.stop(); alive = true }
        else unload.restart()
    }
    Timer { id: unload; interval: root.closeMs; onTriggered: root.alive = false }

    // Your Intel HDA card (from `pactl list cards`).
    readonly property string card: "alsa_card.pci-0000_00_1b.0"

    // Real output devices only, not per-app playback streams.
    // Only tracked while the panel exists (or a profile switch is settling).
    readonly property var sinks: (alive || settle.running)
        ? Pipewire.nodes.values.filter(n => n.isSink && !n.isStream) : []
    readonly property var current: Pipewire.defaultAudioSink
    readonly property bool onHdmi: current !== null && (current.name || "").indexOf("hdmi") !== -1

    // Your card can only drive analog OR HDMI at once, so switching = changing profile.
    function setProfile(profile) {
        profileProc.command = ["pactl", "set-card-profile", card, profile]
        profileProc.running = true
        settle.restart()
    }

    Process { id: profileProc }

    // After the profile changes the old sink disappears and a new one appears.
    // Wait a moment, then make whatever sink is there the default.
    Timer {
        id: settle
        interval: 700
        onTriggered: {
            if (root.sinks.length > 0)
                Pipewire.preferredDefaultAudioSink = root.sinks[0]
        }
    }

    // Toggle from a keybind: qs ipc call audio toggle
    IpcHandler {
        target: "audio"
        function toggle(): void { root.shown = !root.shown }
    }

    LazyLoader {
        active: root.alive

        FloatingWindow {
            id: w
            title: "Audio Output"
            color: "transparent"
            visible: true
            implicitWidth: 420
            implicitHeight: col.implicitHeight + 48

            // 0 = hidden, 1 = open. Starts at 0 and fades in once created.
            property real appear: 0
            Behavior on appear { NumberAnimation { duration: 0; easing.type: Easing.OutCubic } }
            Component.onCompleted: appear = Qt.binding(() => root.shown ? 1 : 0)

            onVisibleChanged: if (!visible) root.shown = false

            PwObjectTracker { objects: root.sinks }

            Shortcut { sequence: "Escape"; onActivated: root.shown = false }

            // Glass body
            // Glass body (no radius or border of its own: labwc rounds and outlines the window)
            Rectangle {
                anchors.fill: parent
                color: Qt.alpha(Theme.panel, 0.82)
                opacity: w.appear

                // Specular sheen across the top
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
                        GradientStop { position: 0.3; color: Qt.rgba(1, 1, 1, 0.0) }
                    }
                }

                ColumnLayout {
                    id: col
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 24
                    spacing: 10

                    Text {
                        text: "Output"
                        color: Theme.fg
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                    }

                    // Main switch: speakers/headphones vs TV.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Repeater {
                            model: [
                                { label: "Speakers", glyph: "\uf025", profile: "output:analog-stereo+input:analog-stereo", hdmi: false },
                                { label: "TV (HDMI)", glyph: "\uf26c", profile: "output:hdmi-stereo+input:analog-stereo",   hdmi: true }
                            ]

                            delegate: Glass {
                                id: btn
                                required property var modelData
                                readonly property bool active: root.onHdmi === modelData.hdmi

                                Layout.fillWidth: true
                                Layout.preferredWidth: 1      // both buttons get equal width
                                Layout.preferredHeight: 52
                                radius: 18
                                color: active ? Qt.alpha(Theme.accent, 0.20)
                                              : (btnHover.containsMouse ? Qt.rgba(1, 1, 1, 0.10)
                                                                        : Qt.rgba(1, 1, 1, 0.05))
                                border.color: active ? Theme.accent : Qt.rgba(1, 1, 1, 0.10)
                                Behavior on color { ColorAnimation { duration: 120 } }

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 10
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: btn.modelData.glyph
                                        color: btn.active ? Theme.accentHi : Theme.fgDim
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 14
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: btn.modelData.label
                                        color: btn.active ? Theme.accentHi : Theme.fg
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 12
                                        font.weight: btn.active ? Font.DemiBold : Font.Normal
                                    }
                                }

                                MouseArea {
                                    id: btnHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setProfile(btn.modelData.profile)
                                }
                            }
                        }
                    }

                    // Individual devices (useful for anything beyond the two above, e.g. Bluetooth).
                    Repeater {
                        model: root.sinks

                        delegate: Glass {
                            id: row
                            required property var modelData
                            readonly property bool active:
                                root.current !== null && root.current.id === modelData.id

                            Layout.fillWidth: true
                            Layout.preferredHeight: 42
                            radius: 14
                            color: hover.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.05)
                            border.color: active ? Theme.accent : Qt.rgba(1, 1, 1, 0.10)
                            Behavior on color { ColorAnimation { duration: 120 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 10

                                // dot: filled when this is the active output
                                Rectangle {
                                    Layout.preferredWidth: 10
                                    Layout.preferredHeight: 10
                                    Layout.alignment: Qt.AlignVCenter
                                    radius: 5
                                    color: row.active ? Theme.accent : "transparent"
                                    border.width: 1
                                    border.color: row.active ? Theme.accent : Theme.fgDim
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: row.modelData.description || row.modelData.nickname || row.modelData.name
                                    color: Theme.fg
                                    elide: Text.ElideRight
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 12
                                }
                            }

                            MouseArea {
                                id: hover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Pipewire.preferredDefaultAudioSink = row.modelData
                            }
                        }
                    }

                    // Volume for whichever output is currently the default.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        spacing: 10
                        visible: root.current !== null && root.current.audio !== null

                        Text {
                            text: "\uf028"
                            color: root.current && root.current.audio && root.current.audio.muted ? Theme.fgDim : Theme.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 14
                        }
                        GlassSlider {
                            Layout.fillWidth: true
                            value: root.current && root.current.audio ? root.current.audio.volume : 0
                            tone: root.current && root.current.audio && root.current.audio.muted ? Theme.fgDim : Theme.accent
                            onMoved: v => {
                                if (root.current && root.current.audio)
                                    root.current.audio.volume = v
                            }
                        }
                        Text {
                            Layout.preferredWidth: 36
                            horizontalAlignment: Text.AlignRight
                            text: Math.round((root.current && root.current.audio ? root.current.audio.volume : 0) * 100) + "%"
                            color: Theme.fgDim
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                        }
                    }
                }
            }
        }
    }
}