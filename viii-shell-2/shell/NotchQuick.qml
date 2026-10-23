// File: ~/viii-shell-2/shell/NotchQuick.qml
// Quick settings inside the notch: Wi-Fi, Bluetooth, speakers/TV, volume,
// brightness, display scale. Replaces AudioPanel.qml and DpiWindow/DpiPanel.qml.
// Loaded by Notch.qml, which sets `n`.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire

Item {
    id: root
    property var n: null
    readonly property string mono: "JetBrainsMono Nerd Font"
    readonly property var sink: n ? n.sink : null

    // ── Wi-Fi ──
    property bool wifiOn: true
    Process {
        id: wifiQ
        command: ["nmcli", "radio", "wifi"]
        stdout: StdioCollector { onStreamFinished: root.wifiOn = text.trim() === "enabled" }
    }
    Timer { id: wifiRecheck; interval: 1000; onTriggered: wifiQ.running = true }
    function toggleWifi() {
        Quickshell.execDetached(["nmcli", "radio", "wifi", wifiOn ? "off" : "on"])
        wifiOn = !wifiOn
        wifiRecheck.restart()
    }

    // ── Bluetooth ──
    readonly property var bt: Bluetooth.defaultAdapter
    readonly property bool btOn: bt !== null && bt.enabled

    // ── Audio output (analog <-> HDMI, same card profiles as before) ──
    readonly property string card: "alsa_card.pci-0000_00_1b.0"
    readonly property var sinks: Pipewire.nodes.values.filter(s => s.isSink && !s.isStream)
    readonly property bool onHdmi: sink !== null && (sink.name || "").indexOf("hdmi") !== -1
    PwObjectTracker { objects: root.sinks }
    function toggleOutput() {
        const profile = onHdmi ? "output:analog-stereo+input:analog-stereo"
                               : "output:hdmi-stereo+input:analog-stereo"
        Quickshell.execDetached(["pactl", "set-card-profile", card, profile])
        settle.restart()
    }
    Timer {
        id: settle
        interval: 700
        onTriggered: if (root.sinks.length > 0) Pipewire.preferredDefaultAudioSink = root.sinks[0]
    }

    // ── Display scale ──
    property real dpiScale: 1.0
    property var outputs: []
    Process {
        id: dpiQ
        command: ["wlr-randr", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const on = JSON.parse(text).filter(o => o.enabled)
                    root.outputs = on.map(o => o.name)
                    if (on.length > 0) root.dpiScale = on[0].scale
                } catch (e) {}
            }
        }
    }
    Timer {
        id: dpiApply
        interval: 300
        onTriggered: {
            let cmd = ["wlr-randr"]
            for (const o of root.outputs) cmd.push("--output", o, "--scale", root.dpiScale.toFixed(2))
            Quickshell.execDetached(cmd)
        }
    }
    function setScale(v) { dpiScale = v; dpiApply.restart() }

    Component.onCompleted: { wifiQ.running = true; dpiQ.running = true }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.topMargin: 2
        spacing: 10

        // toggle tiles
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: [
                    { id: "wifi", glyph: "\uf1eb", label: "Wi-Fi" },
                    { id: "bt",   glyph: "\uf293", label: "Bluetooth" },
                    { id: "out",  glyph: "\uf025", label: "Output" }
                ]
                delegate: Glass {
                    id: tile
                    required property var modelData
                    readonly property bool active: modelData.id === "wifi" ? root.wifiOn
                                                 : (modelData.id === "bt" ? root.btOn : root.onHdmi)
                    readonly property string sub: modelData.id === "wifi"
                        ? (root.wifiOn ? (root.n && root.n.netSsid !== "" ? root.n.netSsid : "On") : "Off")
                        : (modelData.id === "bt" ? (root.btOn ? "On" : "Off")
                        : (root.onHdmi ? "TV (HDMI)" : "Speakers"))
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 62
                    radius: 18
                    color: active ? Qt.alpha(Theme.accent, 0.20)
                                  : (hit.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.05))
                    border.color: active ? Theme.accent : Qt.rgba(1, 1, 1, 0.10)
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Column {
                        anchors.centerIn: parent
                        spacing: 3
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: tile.modelData.glyph
                            color: tile.active ? Theme.accentHi : Theme.fgDim
                            font.family: root.mono; font.pixelSize: 16
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: tile.width - 16
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: tile.sub
                            color: tile.active ? Theme.accentHi : Theme.fg
                            font.family: root.mono; font.pixelSize: 10
                        }
                    }
                    MouseArea {
                        id: hit
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (tile.modelData.id === "wifi") root.toggleWifi()
                            else if (tile.modelData.id === "bt") { if (root.bt) root.bt.enabled = !root.bt.enabled }
                            else root.toggleOutput()
                        }
                    }
                }
            }
        }

        // volume
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            visible: root.sink !== null && root.sink.audio !== null
            Text {
                text: "\uf028"
                color: root.sink && root.sink.audio && root.sink.audio.muted ? Theme.fgDim : Theme.fg
                font.family: root.mono; font.pixelSize: 14
                Layout.preferredWidth: 18
            }
            GlassSlider {
                Layout.fillWidth: true
                value: root.sink && root.sink.audio ? root.sink.audio.volume : 0
                tone: root.sink && root.sink.audio && root.sink.audio.muted ? Theme.fgDim : Theme.accent
                onMoved: v => { if (root.sink && root.sink.audio) root.sink.audio.volume = v }
            }
            Text {
                Layout.preferredWidth: 36
                horizontalAlignment: Text.AlignRight
                text: Math.round((root.sink && root.sink.audio ? root.sink.audio.volume : 0) * 100) + "%"
                color: Theme.fgDim
                font.family: root.mono; font.pixelSize: 11
            }
        }

        // brightness
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            visible: root.n && root.n.blPath !== ""
            Text {
                text: "\uf185"
                color: Theme.fg
                font.family: root.mono; font.pixelSize: 14
                Layout.preferredWidth: 18
            }
            GlassSlider {
                Layout.fillWidth: true
                value: root.n && root.n.lastBl >= 0 ? root.n.lastBl / root.n.blMax : 0.5
                tone: Theme.accent
                onMoved: v => Quickshell.execDetached(["brightnessctl", "set", Math.max(1, Math.round(v * 100)) + "%"])
            }
            Text {
                Layout.preferredWidth: 36
                horizontalAlignment: Text.AlignRight
                text: Math.round((root.n && root.n.lastBl >= 0 ? root.n.lastBl / root.n.blMax : 0) * 100) + "%"
                color: Theme.fgDim
                font.family: root.mono; font.pixelSize: 11
            }
        }

        // display scale
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text {
                text: "Scale"
                color: Theme.fgDim
                font.family: root.mono; font.pixelSize: 11
                Layout.preferredWidth: 48
            }
            Repeater {
                model: [1.0, 1.25, 1.5, 2.0]
                delegate: Glass {
                    id: preset
                    required property var modelData
                    readonly property bool active: Math.abs(root.dpiScale - modelData) < 0.01
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 32
                    radius: 16
                    color: active ? Qt.alpha(Theme.accent, 0.20)
                                  : (ph.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.05))
                    border.color: active ? Theme.accent : Qt.rgba(1, 1, 1, 0.10)
                    Text {
                        anchors.centerIn: parent
                        text: Math.round(preset.modelData * 100) + "%"
                        color: preset.active ? Theme.accentHi : Theme.fg
                        font.family: root.mono; font.pixelSize: 11
                        font.weight: preset.active ? Font.DemiBold : Font.Normal
                    }
                    MouseArea {
                        id: ph
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setScale(preset.modelData)
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
