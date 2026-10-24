// File: ~/viii-shell-2/shell/NotchQuick.qml
// Quick settings inside the notch: Wi-Fi and Bluetooth (each with an animated
// picker), mic, speakers/TV, volume, brightness, display scale. Replaces
// AudioPanel.qml and DpiWindow/DpiPanel.qml.
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

    // ── Which picker is open: "" (none), "wifi" or "bt" ──
    // While one is open it crossfades with the volume/brightness/scale rows.
    property string picker: ""
    readonly property bool picking: picker !== ""

    // True for a moment after a list (re)loads, so rows slide in one after
    // another. Outside that window rows appear instantly, so a background
    // update never makes the whole list flicker.
    property bool listIntro: false
    Timer { id: introT; interval: 700; onTriggered: root.listIntro = false }
    function playIntro() { listIntro = true; introT.restart() }

    function openWifi() {
        picker = "wifi"
        stopBtScan()
        pendingSsid = ""
        wifiMsg = ""
        rescan()
    }
    function openBt() {
        picker = "bt"
        playIntro()
        startBtScan()
    }
    function closePicker() {
        picker = ""
        stopBtScan()
    }
    function togglePicker(which) {
        if (picker === which) closePicker()
        else if (which === "wifi") openWifi()
        else openBt()
    }

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
        // Radio takes a moment to come up; rescan once it has.
        if (wifiOn && picker === "wifi") rescanLater.restart()
    }
    Timer { id: rescanLater; interval: 2500; onTriggered: root.rescan() }

    // ── Wi-Fi network picker ──
    property bool scanning: false
    property var networks: []             // [{ ssid, signal, secured, active }]
    property var savedSsids: []           // networks NetworkManager already has a profile for
    property string pendingSsid: ""       // secured network waiting for a password
    property string connectingSsid: ""    // network we are currently joining
    property bool createdProfile: false   // did this attempt create a new profile?
    property string wifiMsg: ""

    // nmcli's terse output separates fields with ":" and escapes literal colons
    // in SSIDs as "\:". Swap those out first so splitting doesn't break names.
    function splitNm(line) {
        return line.replace(/\\:/g, "\u0001").split(":")
                   .map(p => p.replace(/\u0001/g, ":").replace(/\\\\/g, "\\"))
    }

    function rescan() {
        if (!wifiOn || scanQ.running) return
        scanning = true
        scanQ.running = true
        savedQ.running = true
    }

    Process {
        id: scanQ
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "dev", "wifi", "list", "--rescan", "yes"]
        stdout: StdioCollector {
            onStreamFinished: {
                // One entry per SSID (routers show up once per band): keep the
                // active one, otherwise the strongest.
                const best = {}
                for (const line of text.split("\n")) {
                    if (line === "") continue
                    const f = root.splitNm(line)
                    const ssid = f[1]
                    if (!ssid) continue                       // hidden networks
                    const sec = f[3] || ""
                    const net = {
                        ssid: ssid,
                        signal: parseInt(f[2]) || 0,
                        secured: sec !== "" && sec !== "--",
                        active: f[0] === "*"
                    }
                    const old = best[ssid]
                    if (!old || net.active || (!old.active && net.signal > old.signal)) best[ssid] = net
                }
                root.playIntro()      // must come before the model changes
                root.networks = Object.values(best).sort((a, b) =>
                    (b.active - a.active) || (b.signal - a.signal))
                root.scanning = false
            }
        }
        onExited: root.scanning = false
    }

    Process {
        id: savedQ
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.savedSsids = text.split("\n")
                    .filter(l => l !== "")
                    .map(l => root.splitNm(l))
                    .filter(f => f[1] === "802-11-wireless")
                    .map(f => f[0])
            }
        }
    }

    Process {
        id: connQ
        onExited: (code, status) => {
            if (code === 0) {
                root.wifiMsg = ""
                root.pendingSsid = ""
                root.picker = ""
            } else {
                root.wifiMsg = "Couldn't connect (wrong password?)"
                pwShake.restart()          // shake the password box
                // Don't leave a broken profile behind for a failed first attempt.
                if (root.createdProfile)
                    Quickshell.execDetached(["nmcli", "connection", "delete", "id", root.connectingSsid])
            }
            root.connectingSsid = ""
            root.rescan()
        }
    }

    function connectTo(ssid, pass) {
        if (connQ.running) return
        connectingSsid = ssid
        wifiMsg = ""
        createdProfile = savedSsids.indexOf(ssid) === -1
        const cmd = ["nmcli", "dev", "wifi", "connect", ssid]
        if (pass !== "") cmd.push("password", pass)
        connQ.command = cmd
        connQ.running = true
    }
    function pickNetwork(net) {
        if (net.active || connQ.running) return
        if (net.secured && savedSsids.indexOf(net.ssid) === -1) {
            // New secured network: ask for the password first.
            pendingSsid = net.ssid
            wifiMsg = ""
        } else {
            pendingSsid = ""
            connectTo(net.ssid, "")
        }
    }

    // ── Bluetooth ──
    readonly property var bt: Bluetooth.defaultAdapter
    readonly property bool btOn: bt !== null && bt.enabled
    readonly property bool btScanning: bt !== null && bt.discovering
    property string pairingAddr: ""       // device we are pairing, so we connect once paired

    // Devices for the picker: connected first, then paired, then the rest.
    // Skips devices that only have a MAC address as their name (no real name yet).
    readonly property var btDevices: {
        if (!bt) return []
        return bt.devices.values
            .filter(d => d.name !== undefined && d.name !== ""
                         && d.name.replace(/-/g, ":") !== d.address)
            .sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired)
                            || a.name.localeCompare(b.name))
    }

    function startBtScan() {
        if (bt && btOn) {
            bt.discovering = true
            btScanTimer.restart()
        }
    }
    function stopBtScan() {
        btScanTimer.stop()
        if (bt && bt.discovering) bt.discovering = false
    }
    // Scanning drains battery and slows audio, so stop on its own after 15 s.
    Timer { id: btScanTimer; interval: 15000; onTriggered: root.stopBtScan() }

    // ── Microphone ──
    // Pipewire only keeps `audio` (volume/muted) up to date for nodes we track.
    readonly property var source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: root.source ? [root.source] : [] }
    readonly property bool micMuted: source !== null && source.audio !== null && source.audio.muted
    function toggleMic() {
        if (source && source.audio) source.audio.muted = !source.audio.muted
    }

    // ── Audio output (analog <-> HDMI) ──
    readonly property string card: "alsa_card.pci-0000_00_1b.0"
    readonly property string analogProfile: "output:analog-stereo+input:analog-stereo"
    readonly property string hdmiProfile: "output:hdmi-stereo+input:analog-stereo"
    readonly property var sinks: Pipewire.nodes.values.filter(s => s.isSink && !s.isStream)
    PwObjectTracker { objects: root.sinks }

    function isHdmi(s) { return s !== null && (s.name || "").indexOf("hdmi") !== -1 }
    readonly property bool onHdmi: isHdmi(sink)

    // Is the HDMI profile actually usable right now? (false when nothing is plugged in.)
    // This is the check the old code skipped: forcing an unavailable profile
    // removes the analog sink and leaves you with no sound.
    property bool hdmiAvail: false
    Process {
        id: cardQ
        command: ["pactl", "-f", "json", "list", "cards"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const c = JSON.parse(text).find(x => x.name === root.card)
                    const p = c && c.profiles ? c.profiles[root.hdmiProfile] : null
                    root.hdmiAvail = !!p && (p.available === true || p.available === "yes")
                } catch (e) { root.hdmiAvail = false }
            }
        }
    }

    property bool wantHdmi: false
    function toggleOutput() {
        wantHdmi = !onHdmi
        // Refuse to switch TO hdmi unless the profile is available.
        if (wantHdmi && !hdmiAvail) return
        Quickshell.execDetached(["pactl", "set-card-profile", card, wantHdmi ? hdmiProfile : analogProfile])
        settle.restart()
    }
    Timer {
        id: settle
        interval: 900
        onTriggered: {
            // Pick the sink that matches what we asked for (not just sinks[0]).
            const target = root.sinks.find(s => root.isHdmi(s) === root.wantHdmi)
            if (target) {
                Pipewire.preferredDefaultAudioSink = target
            } else {
                // The switch didn't produce the sink we wanted: go back to analog
                // so you are never left without audio.
                Quickshell.execDetached(["pactl", "set-card-profile", root.card, root.analogProfile])
            }
            cardQ.running = true
        }
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

    Component.onCompleted: { wifiQ.running = true; dpiQ.running = true; cardQ.running = true }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.topMargin: 2
        spacing: 10

        // ── toggle tiles ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: [
                    { id: "wifi", glyph: "\uf1eb", label: "Wi-Fi" },
                    { id: "bt",   glyph: "\uf293", label: "Bluetooth" },
                    { id: "mic",  glyph: "\uf130", label: "Mic" },
                    { id: "out",  glyph: "\uf025", label: "Output" }
                ]
                delegate: Glass {
                    id: tile
                    required property var modelData
                    readonly property string tid: modelData.id
                    // Wi-Fi and Bluetooth tiles have a picker behind them.
                    readonly property bool hasPicker: tid === "wifi" || tid === "bt"
                    readonly property bool active: tid === "wifi" ? root.wifiOn
                                                 : (tid === "bt" ? root.btOn
                                                 : (tid === "mic" ? !root.micMuted : root.onHdmi))
                    // The Output tile is inert when there is no HDMI to switch to.
                    readonly property bool usable: tid !== "out" || root.onHdmi || root.hdmiAvail
                    // Wi-Fi / Bluetooth icon pulses while the radio is busy.
                    readonly property bool busy: (tid === "wifi" && (root.scanning || root.connectingSsid !== ""))
                                              || (tid === "bt" && root.btScanning)
                    readonly property string sub: tid === "wifi"
                        ? (root.wifiOn ? (root.n && root.n.netSsid !== "" ? root.n.netSsid : "On") : "Off")
                        : (tid === "bt" ? (root.btOn ? "On" : "Off")
                        : (tid === "mic" ? (root.micMuted ? "Muted" : "Live")
                        : (root.onHdmi ? "TV (HDMI)" : "Speakers")))
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 62
                    radius: 18
                    opacity: usable ? 1 : 0.45
                    color: active ? Qt.alpha(Theme.accent, 0.20)
                                  : (hit.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.05))
                    border.color: active ? Theme.accent : Qt.rgba(1, 1, 1, 0.10)
                    Behavior on color { ColorAnimation { duration: 160 } }
                    Behavior on border.color { ColorAnimation { duration: 160 } }
                    Behavior on opacity { NumberAnimation { duration: 200 } }

                    // squish when pressed, spring back with a little overshoot
                    scale: hit.pressed ? 0.93 : 1.0
                    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2.5 } }

                    // icon pops whenever the tile flips on/off
                    onActiveChanged: iconPop.restart()

                    // expanding ring from the centre on every click
                    Rectangle {
                        id: ring
                        anchors.centerIn: parent
                        width: 44; height: 44
                        radius: 22
                        color: "transparent"
                        border.width: 2
                        border.color: Theme.accentHi
                        opacity: 0
                        scale: 0.3
                    }
                    ParallelAnimation {
                        id: ringAnim
                        NumberAnimation { target: ring; property: "scale"; from: 0.3; to: 1.35; duration: 420; easing.type: Easing.OutCubic }
                        NumberAnimation { target: ring; property: "opacity"; from: 0.7; to: 0; duration: 420; easing.type: Easing.OutCubic }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 3
                        Text {
                            id: glyphText
                            anchors.horizontalCenter: parent.horizontalCenter
                            // crossed-out mic glyph while muted
                            text: tile.tid === "mic" && root.micMuted ? "\uf131" : tile.modelData.glyph
                            color: tile.active ? Theme.accentHi : Theme.fgDim
                            font.family: root.mono; font.pixelSize: 16
                            Behavior on color { ColorAnimation { duration: 160 } }

                            SequentialAnimation {
                                id: iconPop
                                NumberAnimation { target: glyphText; property: "scale"; to: 1.35; duration: 90; easing.type: Easing.OutCubic }
                                NumberAnimation { target: glyphText; property: "scale"; to: 1.0; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 3 }
                            }
                            // gentle breathing while scanning / connecting
                            SequentialAnimation on opacity {
                                running: tile.busy
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.3; duration: 520; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0; duration: 520; easing.type: Easing.InOutSine }
                                onRunningChanged: if (!running) glyphText.opacity = 1
                            }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: tile.width - 16
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: tile.sub
                            color: tile.active ? Theme.accentHi : Theme.fg
                            font.family: root.mono; font.pixelSize: 10
                            Behavior on color { ColorAnimation { duration: 160 } }
                        }
                    }
                    MouseArea {
                        id: hit
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: tile.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: mouse => {
                            // right-click opens the picker, left-click toggles on/off
                            if (tile.hasPicker && mouse.button === Qt.RightButton) {
                                root.togglePicker(tile.tid)
                                return
                            }
                            if (tile.usable) ringAnim.restart()
                            if (tile.tid === "wifi") root.toggleWifi()
                            else if (tile.tid === "bt") { if (root.bt) root.bt.enabled = !root.bt.enabled }
                            else if (tile.tid === "mic") root.toggleMic()
                            else root.toggleOutput()
                        }
                    }

                    // Wi-Fi / Bluetooth tiles: small arrow in the corner that opens the picker.
                    // It rotates 180° instead of swapping glyphs.
                    Item {
                        visible: tile.hasPicker
                        anchors.top: parent.top
                        anchors.right: parent.right
                        width: 26; height: 26
                        Text {
                            anchors.centerIn: parent
                            text: "\uf078"
                            rotation: root.picker === tile.tid ? 180 : 0
                            Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.8 } }
                            color: tile.active ? Theme.accentHi : Theme.fgDim
                            font.family: root.mono; font.pixelSize: 9
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.togglePicker(tile.tid)
                        }
                    }
                }
            }
        }

        // ── stage: sliders and both pickers share this space and crossfade ──
        Item {
            id: stage
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: root.picking ? 130 : 0
            Layout.preferredHeight: Math.max(slidersCol.implicitHeight, root.picking ? 130 : 0)
            Behavior on Layout.preferredHeight { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

            // ── volume / brightness / scale ──
            ColumnLayout {
                id: slidersCol
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 10

                opacity: root.picking ? 0 : 1
                visible: opacity > 0.01
                enabled: !root.picking
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                transform: Translate {
                    y: root.picking ? -10 : 0
                    Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                }

                // volume
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    visible: root.sink !== null && root.sink.audio !== null
                    Text {
                        text: "\uf028"
                        color: root.sink && root.sink.audio && root.sink.audio.muted ? Theme.fgDim : Theme.fg
                        Behavior on color { ColorAnimation { duration: 160 } }
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
                    visible: !!(root.n && root.n.blPath !== "")
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
                            Behavior on color { ColorAnimation { duration: 160 } }
                            Behavior on border.color { ColorAnimation { duration: 160 } }
                            scale: ph.pressed ? 0.92 : 1.0
                            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 2.5 } }
                            Text {
                                anchors.centerIn: parent
                                text: Math.round(preset.modelData * 100) + "%"
                                color: preset.active ? Theme.accentHi : Theme.fg
                                Behavior on color { ColorAnimation { duration: 160 } }
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
            }

            // ── Wi-Fi network picker ──
            ColumnLayout {
                id: wifiPane
                anchors.fill: parent
                spacing: 6

                readonly property bool shown: root.picker === "wifi"
                opacity: shown ? 1 : 0
                visible: opacity > 0.01
                enabled: shown
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                transform: Translate {
                    y: wifiPane.shown ? 0 : 12
                    Behavior on y { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        text: "Wi-Fi networks"
                        color: Theme.fg
                        font.family: root.mono; font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                    Item { Layout.fillWidth: true }
                    // Rescan button: the icon spins while scanning
                    Item {
                        implicitWidth: rescanRow.implicitWidth
                        implicitHeight: rescanRow.implicitHeight
                        Row {
                            id: rescanRow
                            spacing: 5
                            Text {
                                id: rescanIcon
                                text: "\uf021"
                                color: rescanArea.containsMouse || root.scanning ? Theme.accentHi : Theme.fgDim
                                Behavior on color { ColorAnimation { duration: 140 } }
                                font.family: root.mono; font.pixelSize: 11
                                NumberAnimation on rotation {
                                    running: root.scanning
                                    from: 0; to: 360
                                    duration: 900
                                    loops: Animation.Infinite
                                    onRunningChanged: if (!running) rescanIcon.rotation = 0
                                }
                            }
                            Text {
                                text: root.scanning ? "Scanning…" : "Rescan"
                                color: rescanArea.containsMouse ? Theme.accentHi : Theme.fgDim
                                Behavior on color { ColorAnimation { duration: 140 } }
                                font.family: root.mono; font.pixelSize: 11
                            }
                        }
                        MouseArea {
                            id: rescanArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.rescan()
                        }
                    }
                }

                ListView {
                    id: netList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 4
                    model: root.networks

                    // shown when the list is empty
                    Text {
                        anchors.centerIn: parent
                        opacity: netList.count === 0 ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                        text: !root.wifiOn ? "Wi-Fi is off"
                              : (root.scanning ? "Scanning…" : "No networks found")
                        color: Theme.fgDim
                        font.family: root.mono; font.pixelSize: 11
                    }

                    delegate: Glass {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool joining: root.connectingSsid === modelData.ssid
                        width: netList.width
                        height: 34
                        radius: 12
                        color: modelData.active ? Qt.alpha(Theme.accent, 0.20)
                                                : (rowHit.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.05))
                        border.color: modelData.active ? Theme.accent : Qt.rgba(1, 1, 1, 0.10)
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Behavior on border.color { ColorAnimation { duration: 140 } }

                        scale: rowHit.pressed ? 0.97 : 1.0
                        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 2 } }

                        // slide in from the right, each row a beat after the one above
                        opacity: 0
                        transform: Translate { id: rowShift; x: 18 }
                        Component.onCompleted: {
                            if (root.listIntro) rowIntro.start()
                            else { opacity = 1; rowShift.x = 0 }
                        }
                        SequentialAnimation {
                            id: rowIntro
                            PauseAnimation { duration: Math.min(row.index, 8) * 35 }
                            ParallelAnimation {
                                NumberAnimation { target: row; property: "opacity"; to: 1; duration: 220; easing.type: Easing.OutCubic }
                                NumberAnimation { target: rowShift; property: "x"; to: 0; duration: 300; easing.type: Easing.OutCubic }
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8
                            Text {
                                text: "\uf1eb"
                                color: row.modelData.active ? Theme.accentHi : Theme.fgDim
                                font.family: root.mono; font.pixelSize: 12
                            }
                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: row.modelData.ssid
                                color: row.modelData.active ? Theme.accentHi : Theme.fg
                                font.family: root.mono; font.pixelSize: 11
                                font.weight: row.modelData.active ? Font.DemiBold : Font.Normal
                            }
                            Text {
                                id: rowStatus
                                visible: row.joining || row.modelData.active
                                text: row.joining ? "Connecting…" : "Connected"
                                color: Theme.fgDim
                                font.family: root.mono; font.pixelSize: 10
                                // breathing while connecting
                                SequentialAnimation on opacity {
                                    running: row.joining
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.3; duration: 480; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 1.0; duration: 480; easing.type: Easing.InOutSine }
                                    onRunningChanged: if (!running) rowStatus.opacity = 1
                                }
                            }
                            Text {
                                visible: row.modelData.secured
                                text: "\uf023"
                                color: Theme.fgDim
                                font.family: root.mono; font.pixelSize: 10
                            }
                            Text {
                                text: row.modelData.signal + "%"
                                color: Theme.fgDim
                                font.family: root.mono; font.pixelSize: 10
                            }
                        }
                        MouseArea {
                            id: rowHit
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.pickNetwork(row.modelData)
                        }
                    }
                }

                // password prompt for a new secured network (fades in, shakes on a wrong password)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    opacity: root.pendingSsid !== "" ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                    Glass {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        radius: 12
                        color: Qt.rgba(1, 1, 1, 0.05)
                        border.color: pass.activeFocus ? Theme.accent : Qt.rgba(1, 1, 1, 0.10)
                        Behavior on border.color { ColorAnimation { duration: 140 } }

                        transform: Translate { id: pwShift; x: 0 }
                        SequentialAnimation {
                            id: pwShake
                            NumberAnimation { target: pwShift; property: "x"; to: -9; duration: 50 }
                            NumberAnimation { target: pwShift; property: "x"; to: 9; duration: 80 }
                            NumberAnimation { target: pwShift; property: "x"; to: -6; duration: 70 }
                            NumberAnimation { target: pwShift; property: "x"; to: 6; duration: 70 }
                            NumberAnimation { target: pwShift; property: "x"; to: 0; duration: 60 }
                        }

                        TextInput {
                            id: pass
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            verticalAlignment: TextInput.AlignVCenter
                            echoMode: TextInput.Password
                            color: Theme.fg
                            font.family: root.mono; font.pixelSize: 11
                            clip: true
                            onAccepted: root.connectTo(root.pendingSsid, text)
                            // fresh field + focus each time a network is chosen
                            onVisibleChanged: if (visible) { text = ""; forceActiveFocus() }
                            Text {
                                visible: pass.text === ""
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Password for " + root.pendingSsid
                                color: Theme.fgDim
                                font: pass.font
                            }
                        }
                    }
                    Glass {
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 34
                        radius: 12
                        color: joinHit.containsMouse ? Qt.alpha(Theme.accent, 0.30) : Qt.alpha(Theme.accent, 0.20)
                        border.color: Theme.accent
                        Behavior on color { ColorAnimation { duration: 140 } }
                        scale: joinHit.pressed ? 0.92 : 1.0
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 2.5 } }
                        Text {
                            anchors.centerIn: parent
                            text: "Join"
                            color: Theme.accentHi
                            font.family: root.mono; font.pixelSize: 11
                        }
                        MouseArea {
                            id: joinHit
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.connectTo(root.pendingSsid, pass.text)
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    opacity: root.wifiMsg !== "" ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    text: root.wifiMsg
                    color: Theme.fgDim
                    font.family: root.mono; font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }

            // ── Bluetooth device picker ──
            ColumnLayout {
                id: btPane
                anchors.fill: parent
                spacing: 6

                readonly property bool shown: root.picker === "bt"
                opacity: shown ? 1 : 0
                visible: opacity > 0.01
                enabled: shown
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                transform: Translate {
                    y: btPane.shown ? 0 : 12
                    Behavior on y { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        text: "Bluetooth devices"
                        color: Theme.fg
                        font.family: root.mono; font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                    Item { Layout.fillWidth: true }
                    // Scan button: the icon spins while scanning
                    Item {
                        implicitWidth: btScanRow.implicitWidth
                        implicitHeight: btScanRow.implicitHeight
                        opacity: root.btOn ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                        Row {
                            id: btScanRow
                            spacing: 5
                            Text {
                                id: btScanIcon
                                text: "\uf021"
                                color: btScanArea.containsMouse || root.btScanning ? Theme.accentHi : Theme.fgDim
                                Behavior on color { ColorAnimation { duration: 140 } }
                                font.family: root.mono; font.pixelSize: 11
                                NumberAnimation on rotation {
                                    running: root.btScanning
                                    from: 0; to: 360
                                    duration: 900
                                    loops: Animation.Infinite
                                    onRunningChanged: if (!running) btScanIcon.rotation = 0
                                }
                            }
                            Text {
                                text: root.btScanning ? "Scanning… (stop)" : "Scan"
                                color: btScanArea.containsMouse ? Theme.accentHi : Theme.fgDim
                                Behavior on color { ColorAnimation { duration: 140 } }
                                font.family: root.mono; font.pixelSize: 11
                            }
                        }
                        MouseArea {
                            id: btScanArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { if (root.btScanning) root.stopBtScan(); else root.startBtScan() }
                        }
                    }
                }

                ListView {
                    id: btList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 4
                    model: root.btDevices

                    // shown when the list is empty
                    Text {
                        anchors.centerIn: parent
                        opacity: btList.count === 0 ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                        text: !root.btOn ? "Bluetooth is off"
                              : (root.btScanning ? "Scanning…" : "No devices found")
                        color: Theme.fgDim
                        font.family: root.mono; font.pixelSize: 11
                    }

                    delegate: Glass {
                        id: dev
                        required property var modelData
                        required property int index
                        property bool busy: false       // we asked it to connect/pair and are waiting
                        width: btList.width
                        height: 34
                        radius: 12
                        color: modelData.connected ? Qt.alpha(Theme.accent, 0.20)
                                                   : (devHit.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.05))
                        border.color: modelData.connected ? Theme.accent : Qt.rgba(1, 1, 1, 0.10)
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Behavior on border.color { ColorAnimation { duration: 140 } }

                        scale: devHit.pressed ? 0.97 : 1.0
                        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 2 } }

                        // slide in from the right, each row a beat after the one above
                        opacity: 0
                        transform: Translate { id: devShift; x: 18 }
                        Component.onCompleted: {
                            if (root.listIntro) devIntro.start()
                            else { opacity = 1; devShift.x = 0 }
                        }
                        SequentialAnimation {
                            id: devIntro
                            PauseAnimation { duration: Math.min(dev.index, 8) * 35 }
                            ParallelAnimation {
                                NumberAnimation { target: dev; property: "opacity"; to: 1; duration: 220; easing.type: Easing.OutCubic }
                                NumberAnimation { target: devShift; property: "x"; to: 0; duration: 300; easing.type: Easing.OutCubic }
                            }
                        }

                        // Give up waiting after 8 s so "Connecting…" never sticks.
                        Timer { id: busyT; interval: 8000; onTriggered: dev.busy = false }

                        Connections {
                            target: dev.modelData
                            function onConnectedChanged() { dev.busy = false }
                            // Once a new device finishes pairing, connect to it right away.
                            function onPairedChanged() {
                                if (dev.modelData.paired && root.pairingAddr === dev.modelData.address) {
                                    root.pairingAddr = ""
                                    dev.modelData.connect()
                                }
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8
                            Text {
                                text: "\uf293"
                                color: dev.modelData.connected ? Theme.accentHi : Theme.fgDim
                                font.family: root.mono; font.pixelSize: 12
                            }
                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: dev.modelData.name
                                color: dev.modelData.connected ? Theme.accentHi : Theme.fg
                                font.family: root.mono; font.pixelSize: 11
                                font.weight: dev.modelData.connected ? Font.DemiBold : Font.Normal
                            }
                            Text {
                                visible: dev.modelData.connected && dev.modelData.batteryAvailable
                                text: Math.round(dev.modelData.battery * 100) + "%"
                                color: Theme.fgDim
                                font.family: root.mono; font.pixelSize: 10
                            }
                            Text {
                                id: devStatus
                                text: dev.busy ? "Connecting…"
                                      : (dev.modelData.connected ? "Connected"
                                      : (dev.modelData.paired ? "Paired" : ""))
                                color: Theme.fgDim
                                font.family: root.mono; font.pixelSize: 10
                                // breathing while connecting
                                SequentialAnimation on opacity {
                                    running: dev.busy
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.3; duration: 480; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 1.0; duration: 480; easing.type: Easing.InOutSine }
                                    onRunningChanged: if (!running) devStatus.opacity = 1
                                }
                            }
                        }
                        MouseArea {
                            id: devHit
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mouse => {
                                const d = dev.modelData
                                // right-click a paired device to forget it
                                if (mouse.button === Qt.RightButton) {
                                    if (d.paired) d.forget()
                                    return
                                }
                                if (d.connected) {
                                    d.disconnect()
                                } else {
                                    dev.busy = true
                                    busyT.restart()
                                    if (d.paired) {
                                        d.connect()
                                    } else {
                                        root.pairingAddr = d.address
                                        d.trusted = true
                                        d.pair()
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    opacity: root.btOn ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    text: "Click to connect · right-click a paired device to forget it"
                    color: Theme.fgDim
                    font.family: root.mono; font.pixelSize: 9
                    elide: Text.ElideRight
                }
            }
        }
    }
}
