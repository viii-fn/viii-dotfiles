// Quick Settings, glass style. Layer-shell card pinned to the right edge.
//   qs ipc call quicksettings toggle
// Sliders, toggle tiles, Wi-Fi and Bluetooth cards, two-tap power row. Esc closes.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    property bool shown: false
    property bool alive: false
    readonly property int closeMs: 0
    readonly property string mono: "JetBrainsMono Nerd Font"

    onShownChanged: {
        if (shown) {
            unload.stop()
            alive = true
            introAnim.restart()
        } else {
            unload.restart()
            armed = ""
            pendingSsid = ""
        }
    }

    Timer {
        id: unload
        interval: root.closeMs
        onTriggered: root.alive = false
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // Slide/fade of the whole card, and a staggered intro for the sections inside it
    property real enter: shown ? 1 : 0
    Behavior on enter { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

    property real intro: 0
    NumberAnimation {
        id: introAnim
        target: root
        property: "intro"
        from: 0
        to: 1
        duration: 1100
        easing.type: Easing.OutCubic
    }
    function lp(i, n) {
        return Math.max(0, Math.min(1, intro * (1 + 0.14 * (n - 1)) - i * 0.14))
    }

    // ── System state (from quicksettings-report) ──
    property int vol: 0
    property bool muted: false
    property bool micMuted: false
    property int bri: 0
    property bool hasBri: false
    property int bat: 0
    property string batStatus: ""
    property bool hasBat: false
    property bool btOn: false
    property string profile: ""

    // ── Wi-Fi state ──
    property bool wifiOn: true
    property var current: null
    property var saved: ({})
    property string pendingSsid: ""
    property bool badPassword: false
    property string msg: ""

    // ── UI state ──
    property string expanded: ""          // "", "wifi" or "bt"
    property var btDevs: []
    property bool btNeeded: false
    property string armed: ""

    readonly property string report: Quickshell.env("HOME") + "/.local/bin/quicksettings-report"

    ListModel { id: networks }

    readonly property var tiles: {
        const t = [
            { id: "wifi", glyph: "\uf1eb", title: "Wi-Fi", sub: wifiOn ? (current ? current.ssid : "Not connected") : "Off", on: wifiOn },
            { id: "bt", glyph: "\uf293", title: "Bluetooth", sub: btOn ? btSummary() : "Off", on: btOn },
            { id: "mic", glyph: micMuted ? "\uf131" : "\uf130", title: "Mic", sub: micMuted ? "Muted" : "Live", on: !micMuted },
            { id: "air", glyph: "\uf072", title: "Airplane", sub: (!wifiOn && !btOn) ? "On" : "Off", on: !wifiOn && !btOn }
        ]
        if (profile !== "")
            t.push({ id: "prof", glyph: "\uf0e7", title: "Power", sub: profileLabel(profile), on: profile !== "balanced" })
        return t
    }

    // ── Helpers ──
    function hex(c) {
        const h = v => ("0" + Math.round(v * 255).toString(16)).slice(-2)
        return "#" + h(c.r) + h(c.g) + h(c.b)
    }
    function sigHtml(v) {
        return '<span style="font-size:40px; font-weight:600; color:' + hex(Theme.accentHi) + ';">' + v + '</span>'
             + '<span style="font-size:14px; color:' + hex(Theme.fgDim) + ';">%</span>'
    }
    function profileLabel(p) {
        if (p === "power-saver") return "Saver"
        if (p === "performance") return "Performance"
        return "Balanced"
    }
    function btSummary() {
        const c = btDevs.filter(d => d.connected)
        if (c.length === 0) return "No device"
        return c[0].name + (c.length > 1 ? " +" + (c.length - 1) : "")
    }
    function batGlyph() {
        if (batStatus === "Charging") return "\uf0e7"
        if (bat > 87) return "\uf240"
        if (bat > 62) return "\uf241"
        if (bat > 37) return "\uf242"
        if (bat > 12) return "\uf243"
        return "\uf244"
    }

    function parseStatus(text) {
        let b = false, bt = false, pr = ""
        for (const line of text.split("\n")) {
            const p = line.split("\t")
            if (p[0] === "VOL") { vol = parseInt(p[1]); muted = p[2] === "1" }
            else if (p[0] === "MIC") { micMuted = p[1] === "1" }
            else if (p[0] === "BRI") { bri = parseInt(p[1]); b = true }
            else if (p[0] === "BAT") { bat = parseInt(p[1]); batStatus = p[2]; bt = true }
            else if (p[0] === "WIFI") { wifiOn = p[1] === "enabled" }
            else if (p[0] === "BT") { btOn = p[1] === "yes" }
            else if (p[0] === "PROF") { pr = p[1] || "" }
        }
        hasBri = b
        hasBat = bt
        profile = pr
        if (btNeeded) { btNeeded = false; btProc.running = true }
    }
    function parseBt(text) {
        const d = []
        for (const line of text.split("\n")) {
            const p = line.split("\t")
            if (p[0] === "BTD") d.push({ mac: p[1], connected: p[2] === "1", name: p[3] })
        }
        btDevs = d
    }

    function parseWifi(text) {
        const byName = {}
        for (const line of text.trim().split("\n")) {
            if (!line) continue
            const f = line.replace(/\\:/g, "\u0001").split(":").map(s => s.replace(/\u0001/g, ":"))
            const ssid = f[1]
            if (!ssid) continue
            const strength = parseInt(f[2]) || 0
            const freq = parseInt(f[4]) || 0
            const row = byName[ssid] || (byName[ssid] = { active: false, ssid: ssid, strength: 0, security: f[3] || "", band: "" })
            row.active = row.active || f[0] === "*"
            if (strength >= row.strength) {
                row.strength = strength
                row.band = freq >= 5900 ? "6 GHz" : (freq >= 4900 ? "5 GHz" : (freq > 0 ? "2.4 GHz" : ""))
            }
        }
        const rows = Object.values(byName)
        rows.sort((a, b) => b.strength - a.strength)
        current = rows.find(r => r.active) || null

        // Don't rebuild the list while someone is typing a password
        if (pendingSsid !== "") return
        const others = rows.filter(r => !r.active)
        let same = networks.count === others.length
        if (same) for (let i = 0; i < others.length; i++) if (networks.get(i).ssid !== others[i].ssid) { same = false; break }
        if (same) {
            for (let i = 0; i < others.length; i++) networks.set(i, others[i])
        } else {
            networks.clear()
            for (const r of others) networks.append(r)
        }
    }

    function connectTo(ssid, secured, password) {
        if (connector.running) return
        badPassword = false
        msg = "Connecting to " + ssid + "…"
        connector.ssid = ssid
        connector.secured = secured
        connector.password = password
        connector.running = true
    }

    function refresh() {
        btNeeded = true
        sysProc.running = true
        scan.running = true
        savedList.running = true
    }
    function act(cmd) {
        Quickshell.execDetached(cmd)
        settle.restart()
    }
    function setExpanded(which) {
        pendingSsid = ""
        expanded = (expanded === which) ? "" : which
        if (expanded === "wifi") { scan.running = true; savedList.running = true }
        if (expanded === "bt") btProc.running = true
    }
    function tileClick(id) {
        if (id === "wifi") {
            radioSet.target = !wifiOn
            wifiOn = !wifiOn
            radioSet.running = true
        } else if (id === "bt") {
            act(["bluetoothctl", "power", btOn ? "off" : "on"])
            btOn = !btOn
        } else if (id === "mic") {
            act(["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"])
            micMuted = !micMuted
        } else if (id === "air") {
            act(["rfkill", (!wifiOn && !btOn) ? "unblock" : "block", "all"])
        } else if (id === "prof") {
            const next = { "power-saver": "balanced", "balanced": "performance", "performance": "power-saver" }[profile]
            act(["powerprofilesctl", "set", next])
            profile = next
        }
    }
    function power(id) {
        if (armed !== id) { armed = id; armTimer.restart(); return }
        armed = ""
        shown = false
        if (id === "suspend") Quickshell.execDetached(["systemctl", "suspend"])
        else if (id === "logout") Quickshell.execDetached(["niri", "msg", "action", "quit", "--skip-confirmation"])
        else if (id === "reboot") Quickshell.execDetached(["systemctl", "reboot"])
        else if (id === "off") Quickshell.execDetached(["systemctl", "poweroff"])
    }

    IpcHandler {
        target: "quicksettings"
        function toggle(): void {
            root.shown = !root.shown
            if (root.shown) root.refresh()
        }
    }

    // ── Timers (all idle while the panel is closed) ──
    Timer {
        id: settle
        interval: 1200
        onTriggered: {
            sysProc.running = true
            if (root.wifiOn) scan.running = true
            if (root.expanded === "bt" || root.btOn) btProc.running = true
        }
    }
    Timer {
        interval: 4000
        repeat: true
        running: root.shown
        onTriggered: if (!sysProc.running) sysProc.running = true
    }
    Timer {
        interval: 10000
        repeat: true
        running: root.shown && root.wifiOn && root.pendingSsid === ""
        onTriggered: if (!scan.running) scan.running = true
    }
    Timer {
        id: armTimer
        interval: 3000
        onTriggered: root.armed = ""
    }

    // ── Processes ──
    Process {
        id: sysProc
        command: [root.report, "status"]
        stdout: StdioCollector { onStreamFinished: root.parseStatus(text) }
    }
    Process {
        id: btProc
        command: [root.report, "bt"]
        stdout: StdioCollector { onStreamFinished: root.parseBt(text) }
    }
    Process {
        id: scan
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY,FREQ", "device", "wifi", "list", "--rescan", "auto"]
        stdout: StdioCollector { onStreamFinished: root.parseWifi(text) }
    }
    Process {
        id: savedList
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = {}
                for (const line of text.trim().split("\n")) {
                    if (!line) continue
                    const f = line.replace(/\\:/g, "\u0001").split(":").map(x => x.replace(/\u0001/g, ":"))
                    if ((f[1] || "").indexOf("wireless") >= 0) s[f[0]] = true
                }
                root.saved = s
            }
        }
    }
    Process {
        id: radioSet
        property bool target: true
        command: ["nmcli", "radio", "wifi", target ? "on" : "off"]
        onExited: root.refresh()
    }
    Process {
        id: disconnector
        property string ssid: ""
        command: ["nmcli", "connection", "down", "id", ssid]
        onExited: { root.msg = "Disconnected"; scan.running = true }
    }
    Process {
        id: forgetter
        property string ssid: ""
        command: ["nmcli", "connection", "delete", "id", ssid]
        onExited: { root.msg = "Forgot " + ssid; root.refresh() }
    }
    Process {
        id: connector
        property string ssid: ""
        property string password: ""
        property bool secured: false
        command: password === ""
            ? ["nmcli", "device", "wifi", "connect", ssid]
            : ["nmcli", "device", "wifi", "connect", ssid, "password", password]
        stderr: StdioCollector { id: connErr }
        onExited: (code) => {
            root.badPassword = false
            if (code === 0) {
                root.msg = "Connected to " + ssid
                root.pendingSsid = ""
                savedList.running = true
            } else if (secured) {
                root.pendingSsid = ssid
                root.badPassword = password !== ""
                root.msg = password === "" ? "Password needed" : "Wrong password?"
            } else {
                root.msg = connErr.text.trim() || "Connection failed"
            }
            scan.running = true
        }
    }

    // ── The panel: layer-shell window pinned to the right edge ──
    LazyLoader {
        active: root.alive

        FloatingWindow {
            id: win
            title: "Quick Settings"
            implicitWidth: 430
            implicitHeight: 700
            color: "transparent"
            // Closed from outside (e.g. Mod+Q): tell the panel it is no longer shown
            onVisibleChanged: if (!visible && root.shown) root.shown = false

            Shortcut { sequence: "Escape"; onActivated: root.shown = false }

            // Glass body
            Rectangle {
                id: card
                anchors.fill: parent
                radius: 24
                clip: true
                color: Qt.alpha(Theme.panel, 0.82)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.12)
                opacity: root.enter


                // Specular sheen across the top
                Rectangle {
                    anchors.fill: parent
                    radius: card.radius
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
                        GradientStop { position: 0.25; color: Qt.rgba(1, 1, 1, 0.0) }
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 14

                    // ── Header ──
                    RowLayout {
                        id: headerRow
                        Layout.fillWidth: true
                        spacing: 10
                        opacity: root.lp(0, 7)

                        ColumnLayout {
                            spacing: 0
                            Text {
                                text: "Quick Settings"
                                color: Theme.fg
                                font.family: root.mono
                                font.pixelSize: 18
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: Qt.formatDateTime(clock.date, "ddd d MMM  ·  HH:mm")
                                color: Theme.fgDim
                                font.family: root.mono
                                font.pixelSize: 11
                            }
                        }
                        Item { Layout.fillWidth: true }

                        Glass {
                            visible: root.hasBat
                            Layout.preferredHeight: 30
                            Layout.preferredWidth: batRow.implicitWidth + 24
                            radius: 15

                            Row {
                                id: batRow
                                anchors.centerIn: parent
                                spacing: 7
                                Text {
                                    text: root.batGlyph()
                                    color: (root.bat <= 15 && root.batStatus !== "Charging") ? Theme.bad : Theme.accentHi
                                    font.family: root.mono
                                    font.pixelSize: 12
                                }
                                Text {
                                    text: root.bat + "%"
                                    color: Theme.fg
                                    font.family: root.mono
                                    font.pixelSize: 11
                                }
                            }
                        }
                        IconBtn {
                            glyph: "\uf00d"
                            tone: Theme.accentHi
                            onClicked: root.shown = false
                        }
                    }

                    // Scanline that sweeps across once on open
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 2
                        clip: true
                        Rectangle { anchors.fill: parent; color: Qt.rgba(1, 1, 1, 0.10) }
                        Rectangle {
                            width: 140
                            height: 2
                            x: -140 + (parent.width + 140) * root.intro
                            opacity: root.intro < 1 ? 1 : 0
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: Qt.rgba(Theme.accentHi.r, Theme.accentHi.g, Theme.accentHi.b, 0) }
                                GradientStop { position: 0.5; color: Theme.accentHi }
                                GradientStop { position: 1; color: Qt.rgba(Theme.accentHi.r, Theme.accentHi.g, Theme.accentHi.b, 0) }
                            }
                        }
                    }

                    // ── Scrollable body ──
                    Flickable {
                        id: flick
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentWidth: width
                        contentHeight: body.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: body
                            width: flick.width
                            spacing: 14

                            // ── Sliders ──
                            Glass {
                                Layout.fillWidth: true
                                Layout.preferredHeight: sliders.implicitHeight + 28
                                radius: 20
                                opacity: root.lp(1, 7)
                                transform: Translate { y: (1 - root.lp(1, 7)) * 16 }

                                ColumnLayout {
                                    id: sliders
                                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                                    spacing: 8

                                    QsSliderRow {
                                        glyph: root.muted ? "\uf6a9" : "\uf028"
                                        dim: root.muted
                                        value: root.vol / 100
                                        onMoved: (v) => {
                                            root.vol = Math.round(v * 100)
                                            Quickshell.execDetached(["wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", v.toFixed(2)])
                                        }
                                        onIconClicked: {
                                            root.muted = !root.muted
                                            root.act(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
                                        }
                                    }
                                    QsSliderRow {
                                        visible: root.hasBri
                                        glyph: "\uf185"
                                        value: root.bri / 100
                                        onMoved: (v) => {
                                            root.bri = Math.max(1, Math.round(v * 100))
                                            Quickshell.execDetached(["brightnessctl", "set", root.bri + "%"])
                                        }
                                    }
                                }
                            }

                            // ── Toggle tiles ──
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Repeater {
                                    model: root.tiles

                                    Glass {
                                        id: tile
                                        required property var modelData
                                        required property int index
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        Layout.preferredHeight: 78
                                        radius: 18
                                        opacity: root.lp(index + 1, 8)
                                        scale: tHit.pressed ? 0.95 : (tHit.containsMouse ? 1.04 : 1)
                                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

                                        // Active tint
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 18
                                            color: Qt.alpha(Theme.accent, 0.22)
                                            border.width: 1
                                            border.color: Theme.accent
                                            opacity: tile.modelData.on ? 1 : 0
                                            Behavior on opacity { NumberAnimation { duration: 0} }
                                        }

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 6
                                            spacing: 2
                                            Item { Layout.fillHeight: true }
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: tile.modelData.glyph
                                                color: tile.modelData.on ? Theme.accentHi : Theme.fgDim
                                                font.family: root.mono
                                                font.pixelSize: 20
                                            }
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                Layout.fillWidth: true
                                                horizontalAlignment: Text.AlignHCenter
                                                text: tile.modelData.title
                                                color: tile.modelData.on ? Theme.fg : Theme.fgDim
                                                font.family: root.mono
                                                font.pixelSize: 9
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                Layout.fillWidth: true
                                                horizontalAlignment: Text.AlignHCenter
                                                text: tile.modelData.sub
                                                color: Theme.fgDim
                                                font.family: root.mono
                                                font.pixelSize: 8
                                                elide: Text.ElideRight
                                            }
                                            Item { Layout.fillHeight: true }
                                        }

                                        MouseArea {
                                            id: tHit
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.tileClick(tile.modelData.id)
                                        }
                                    }
                                }
                            }

                            // ── Wi-Fi card ──
                            Glass {
                                id: wifiCard
                                Layout.fillWidth: true
                                property real h: wifiCol.implicitHeight + 28
                                Behavior on h { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                                Layout.preferredHeight: h
                                clip: true
                                radius: 20
                                opacity: root.lp(5, 7)
                                transform: Translate { y: (1 - root.lp(5, 7)) * 16 }

                                ColumnLayout {
                                    id: wifiCol
                                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                                    spacing: 10

                                    // Hero
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 84

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.setExpanded("wifi")
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            spacing: 14

                                            Row {
                                                Layout.alignment: Qt.AlignVCenter
                                                spacing: 4
                                                Repeater {
                                                    model: 4
                                                    Rectangle {
                                                        required property int index
                                                        width: 7
                                                        height: (10 + index * 7) * root.lp(index, 5)
                                                        anchors.bottom: parent.bottom
                                                        radius: 3
                                                        color: (root.wifiOn && root.current && root.current.strength > index * 25)
                                                               ? Theme.accent : Qt.rgba(1, 1, 1, 0.12)
                                                    }
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: !root.wifiOn ? "Wi-Fi is off" : (root.current ? root.current.ssid : "Not connected")
                                                    color: Theme.fg
                                                    font.family: root.mono
                                                    font.pixelSize: 14
                                                    font.weight: Font.DemiBold
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    visible: root.wifiOn && root.current !== null
                                                    textFormat: Text.RichText
                                                    font.family: root.mono
                                                    text: root.current ? root.sigHtml(Math.round(root.current.strength * root.intro)) : ""
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: !root.wifiOn ? "Tap the Wi-Fi tile to turn on"
                                                        : (root.current
                                                            ? (root.current.band + (root.current.band !== "" ? " · " : "")
                                                               + (root.current.security !== "" ? "Secured" : "Open"))
                                                            : "Tap to pick a network")
                                                    color: Theme.fgDim
                                                    font.family: root.mono
                                                    font.pixelSize: 10
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            Rectangle {
                                                visible: root.wifiOn && root.current !== null
                                                Layout.alignment: Qt.AlignVCenter
                                                Layout.preferredWidth: dcText.implicitWidth + 22
                                                Layout.preferredHeight: 28
                                                radius: 14
                                                color: dcHit.containsMouse ? Qt.rgba(Theme.bad.r, Theme.bad.g, Theme.bad.b, 0.25) : Qt.rgba(1, 1, 1, 0.06)
                                                border.width: 1
                                                border.color: dcHit.containsMouse ? Theme.bad : Qt.rgba(1, 1, 1, 0.12)
                                                Text {
                                                    id: dcText
                                                    anchors.centerIn: parent
                                                    text: "Disconnect"
                                                    color: dcHit.containsMouse ? Theme.bad : Theme.fgDim
                                                    font.family: root.mono
                                                    font.pixelSize: 9
                                                }
                                                MouseArea {
                                                    id: dcHit
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        disconnector.ssid = root.current.ssid
                                                        disconnector.running = true
                                                    }
                                                }
                                            }

                                            Text {
                                                Layout.alignment: Qt.AlignVCenter
                                                text: "\uf078"
                                                color: Theme.fgDim
                                                font.family: root.mono
                                                font.pixelSize: 11
                                                rotation: root.expanded === "wifi" ? 180 : 0
                                                Behavior on rotation { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                            }
                                        }
                                    }

                                    // Expanded: status, scan sweep, network list
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        visible: root.expanded === "wifi"
                                        spacing: 8

                                        Text {
                                            Layout.fillWidth: true
                                            visible: root.msg !== "" && root.wifiOn
                                            text: root.msg
                                            color: root.badPassword ? Theme.bad : Theme.fgDim
                                            font.family: root.mono
                                            font.pixelSize: 10
                                            elide: Text.ElideRight
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            visible: root.wifiOn
                                            spacing: 8
                                            Text {
                                                text: "AVAILABLE"
                                                color: Theme.fgDim
                                                font.family: root.mono
                                                font.pixelSize: 9
                                                font.letterSpacing: 1.6
                                            }
                                            Item { Layout.fillWidth: true }
                                            Text {
                                                text: scan.running ? "scanning…" : networks.count + " found"
                                                color: Theme.fgDim
                                                font.family: root.mono
                                                font.pixelSize: 9
                                            }
                                            IconBtn {
                                                glyph: "\uf021"
                                                tone: Theme.accentHi
                                                onClicked: { scan.running = true; savedList.running = true }
                                            }
                                        }

                                        // Sweeping bar while a scan runs
                                        Item {
                                            id: sweepHost
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 2
                                            clip: true
                                            visible: root.wifiOn
                                            Rectangle { anchors.fill: parent; color: Qt.rgba(1, 1, 1, 0.10) }
                                            Rectangle {
                                                visible: scan.running
                                                width: 90
                                                height: 2
                                                gradient: Gradient {
                                                    orientation: Gradient.Horizontal
                                                    GradientStop { position: 0; color: Qt.rgba(Theme.accentHi.r, Theme.accentHi.g, Theme.accentHi.b, 0) }
                                                    GradientStop { position: 0.5; color: Theme.accentHi }
                                                    GradientStop { position: 1; color: Qt.rgba(Theme.accentHi.r, Theme.accentHi.g, Theme.accentHi.b, 0) }
                                                }
                                                NumberAnimation on x {
                                                    running: scan.running
                                                    loops: Animation.Infinite
                                                    from: -90
                                                    to: sweepHost.width
                                                    duration: 1000
                                                }
                                            }
                                        }

                                        Repeater {
                                            model: root.wifiOn ? networks : null

                                            Item {
                                                id: row
                                                required property int index
                                                required property string ssid
                                                required property int strength
                                                required property string security
                                                required property string band

                                                readonly property bool pending: root.pendingSsid === ssid
                                                readonly property bool isSaved: root.saved[ssid] === true
                                                property bool reveal: false
                                                property real h: 50 + (pending ? 54 : 0)
                                                Behavior on h { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                                Layout.fillWidth: true
                                                Layout.preferredHeight: h
                                                clip: true
                                                opacity: 0
                                                transform: Translate { id: rowTr; x: 28 }

                                                SequentialAnimation {
                                                    running: true
                                                    PauseAnimation { duration: Math.min(row.index, 8) * 40 }
                                                    ParallelAnimation {
                                                        NumberAnimation { target: row; property: "opacity"; from: 0; to: 1; duration: 240 }
                                                        NumberAnimation { target: rowTr; property: "x"; from: 28; to: 0; duration: 300; easing.type: Easing.OutCubic }
                                                    }
                                                }

                                                onPendingChanged: if (pending) { reveal = false; pw.text = ""; pw.forceActiveFocus() }

                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: 14
                                                    color: hit.containsMouse || row.pending ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(1, 1, 1, 0.04)
                                                    border.width: row.pending ? 1 : 0
                                                    border.color: root.badPassword ? Theme.bad : Theme.accent
                                                    Behavior on color { ColorAnimation { duration: 120 } }
                                                }

                                                Item {
                                                    width: parent.width
                                                    height: 50

                                                    MouseArea {
                                                        id: hit
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (row.pending) root.pendingSsid = ""
                                                            else if (row.isSaved || row.security === "") root.connectTo(row.ssid, row.security !== "", "")
                                                            else root.pendingSsid = row.ssid
                                                        }
                                                    }

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 14
                                                        anchors.rightMargin: 12
                                                        spacing: 12

                                                        Row {
                                                            Layout.alignment: Qt.AlignVCenter
                                                            spacing: 2
                                                            Repeater {
                                                                model: 4
                                                                Rectangle {
                                                                    required property int index
                                                                    width: 4
                                                                    height: 6 + index * 4
                                                                    anchors.bottom: parent.bottom
                                                                    radius: 2
                                                                    color: row.strength > index * 25
                                                                           ? (row.strength >= 50 ? Theme.accent : Theme.fgDim)
                                                                           : Qt.rgba(1, 1, 1, 0.12)
                                                                }
                                                            }
                                                        }

                                                        ColumnLayout {
                                                            Layout.fillWidth: true
                                                            spacing: 0
                                                            Text {
                                                                Layout.fillWidth: true
                                                                text: row.ssid
                                                                color: Theme.fg
                                                                font.family: root.mono
                                                                font.pixelSize: 12
                                                                elide: Text.ElideRight
                                                            }
                                                            Text {
                                                                Layout.fillWidth: true
                                                                text: (row.isSaved ? "saved · " : "") + (row.security !== "" ? "secured" : "open")
                                                                      + (row.band !== "" ? " · " + row.band : "")
                                                                color: row.isSaved ? Theme.accent : Theme.fgDim
                                                                font.family: root.mono
                                                                font.pixelSize: 9
                                                                elide: Text.ElideRight
                                                            }
                                                        }

                                                        Text {
                                                            visible: row.security !== ""
                                                            text: "\uf023"
                                                            color: Theme.fgDim
                                                            font.family: root.mono
                                                            font.pixelSize: 11
                                                        }
                                                        Text {
                                                            visible: row.isSaved
                                                            text: "\uf1f8"
                                                            color: forgetHit.containsMouse ? Theme.bad : Theme.fgDim
                                                            font.family: root.mono
                                                            font.pixelSize: 12
                                                            MouseArea {
                                                                id: forgetHit
                                                                anchors.fill: parent
                                                                anchors.margins: -8
                                                                hoverEnabled: true
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: {
                                                                    forgetter.ssid = row.ssid
                                                                    forgetter.running = true
                                                                }
                                                            }
                                                        }
                                                    }
                                                }

                                                // Inline password field
                                                Rectangle {
                                                    visible: row.pending
                                                    x: 10
                                                    y: 52
                                                    width: parent.width - 20
                                                    height: 38
                                                    radius: 19
                                                    color: Qt.alpha(Theme.surfaceHi, 0.7)
                                                    border.width: 1
                                                    border.color: root.badPassword ? Theme.bad : Theme.accent

                                                    Text {
                                                        anchors.left: parent.left
                                                        anchors.leftMargin: 16
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: "Password"
                                                        color: Theme.fgDim
                                                        font.family: root.mono
                                                        font.pixelSize: 12
                                                        visible: pw.text === ""
                                                    }
                                                    TextInput {
                                                        id: pw
                                                        anchors.left: parent.left
                                                        anchors.right: eye.left
                                                        anchors.leftMargin: 16
                                                        anchors.rightMargin: 8
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        echoMode: row.reveal ? TextInput.Normal : TextInput.Password
                                                        color: Theme.fg
                                                        font.family: root.mono
                                                        font.pixelSize: 12
                                                        clip: true
                                                        onAccepted: root.connectTo(row.ssid, true, text)
                                                        Keys.onEscapePressed: root.pendingSsid = ""
                                                    }
                                                    Text {
                                                        id: eye
                                                        anchors.right: joinBtn.left
                                                        anchors.rightMargin: 10
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: row.reveal ? "\uf070" : "\uf06e"
                                                        color: Theme.fgDim
                                                        font.family: root.mono
                                                        font.pixelSize: 12
                                                        MouseArea {
                                                            anchors.fill: parent
                                                            anchors.margins: -6
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: row.reveal = !row.reveal
                                                        }
                                                    }
                                                    Rectangle {
                                                        id: joinBtn
                                                        anchors.right: parent.right
                                                        anchors.rightMargin: 5
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: 54
                                                        height: 28
                                                        radius: 14
                                                        color: Theme.accent
                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: "Join"
                                                            color: Theme.accentText
                                                            font.family: root.mono
                                                            font.pixelSize: 11
                                                            font.weight: Font.DemiBold
                                                        }
                                                        MouseArea {
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: root.connectTo(row.ssid, true, pw.text)
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            visible: root.wifiOn && networks.count === 0 && !scan.running
                                            text: "No other networks found"
                                            color: Theme.fgDim
                                            font.family: root.mono
                                            font.pixelSize: 11
                                        }
                                    }
                                }
                            }

                            // ── Bluetooth card ──
                            Glass {
                                id: btCard
                                Layout.fillWidth: true
                                property real h: btCol.implicitHeight + 28
                                Behavior on h { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                                Layout.preferredHeight: h
                                clip: true
                                radius: 20
                                opacity: root.lp(6, 7)
                                transform: Translate { y: (1 - root.lp(6, 7)) * 16 }

                                ColumnLayout {
                                    id: btCol
                                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                                    spacing: 10

                                    Item {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 44

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.setExpanded("bt")
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            spacing: 12

                                            Rectangle {
                                                Layout.preferredWidth: 36
                                                Layout.preferredHeight: 36
                                                radius: 18
                                                color: root.btOn ? Qt.alpha(Theme.accent, 0.22) : Qt.rgba(1, 1, 1, 0.06)
                                                border.width: root.btOn ? 1 : 0
                                                border.color: Theme.accent
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "\uf293"
                                                    color: root.btOn ? Theme.accentHi : Theme.fgDim
                                                    font.family: root.mono
                                                    font.pixelSize: 14
                                                }
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                Text {
                                                    text: "Bluetooth"
                                                    color: Theme.fg
                                                    font.family: root.mono
                                                    font.pixelSize: 13
                                                    font.weight: Font.DemiBold
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: root.btOn ? root.btSummary() : "Off"
                                                    color: Theme.fgDim
                                                    font.family: root.mono
                                                    font.pixelSize: 10
                                                    elide: Text.ElideRight
                                                }
                                            }
                                            Text {
                                                text: "\uf078"
                                                color: Theme.fgDim
                                                font.family: root.mono
                                                font.pixelSize: 11
                                                rotation: root.expanded === "bt" ? 180 : 0
                                                Behavior on rotation { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                            }
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        visible: root.expanded === "bt"
                                        spacing: 6

                                        Text {
                                            visible: root.btDevs.length === 0
                                            text: root.btOn ? "No paired devices" : "Bluetooth is off"
                                            color: Theme.fgDim
                                            font.family: root.mono
                                            font.pixelSize: 11
                                        }

                                        Repeater {
                                            model: root.btOn ? root.btDevs : []

                                            Rectangle {
                                                id: drow
                                                required property var modelData
                                                required property int index
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 38
                                                radius: 19
                                                opacity: 0
                                                transform: Translate { id: dTr; x: 28 }
                                                color: modelData.connected
                                                    ? Qt.alpha(Theme.accent, 0.18)
                                                    : (dHit.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(1, 1, 1, 0.04))
                                                border.width: modelData.connected ? 1 : 0
                                                border.color: Theme.accent

                                                SequentialAnimation {
                                                    running: true
                                                    PauseAnimation { duration: Math.min(drow.index, 8) * 40 }
                                                    ParallelAnimation {
                                                        NumberAnimation { target: drow; property: "opacity"; from: 0; to: 1; duration: 240 }
                                                        NumberAnimation { target: dTr; property: "x"; from: 28; to: 0; duration: 300; easing.type: Easing.OutCubic }
                                                    }
                                                }

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 16
                                                    anchors.rightMargin: 16
                                                    spacing: 8
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: drow.modelData.name
                                                        color: drow.modelData.connected ? Theme.accentHi : Theme.fg
                                                        font.family: root.mono
                                                        font.pixelSize: 12
                                                        elide: Text.ElideRight
                                                    }
                                                    Text {
                                                        text: drow.modelData.connected ? "connected" : "tap to connect"
                                                        color: Theme.fgDim
                                                        font.family: root.mono
                                                        font.pixelSize: 9
                                                    }
                                                }
                                                MouseArea {
                                                    id: dHit
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.act(["bluetoothctl", drow.modelData.connected ? "disconnect" : "connect", drow.modelData.mac])
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ── Power row (tap twice) ──
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                spacing: 10
                                opacity: root.lp(6, 7)

                                Repeater {
                                    model: [
                                        { id: "suspend", glyph: "\uf186", label: "Sleep" },
                                        { id: "logout", glyph: "\uf08b", label: "Log out" },
                                        { id: "reboot", glyph: "\uf021", label: "Reboot" },
                                        { id: "off", glyph: "\uf011", label: "Shut down" }
                                    ]

                                    ColumnLayout {
                                        id: pb
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        spacing: 4

                                        IconBtn {
                                            Layout.alignment: Qt.AlignHCenter
                                            glyph: pb.modelData.glyph
                                            tone: root.armed === pb.modelData.id ? Theme.bad : Theme.accentHi
                                            scale: root.armed === pb.modelData.id ? 1.2 : 1
                                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                                            onClicked: root.power(pb.modelData.id)
                                        }
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: root.armed === pb.modelData.id ? "Tap again" : pb.modelData.label
                                            color: root.armed === pb.modelData.id ? Theme.bad : Theme.fgDim
                                            font.family: root.mono
                                            font.pixelSize: 9
                                        }
                                    }
                                }
                            }

                            Item { Layout.preferredHeight: 2 }
                        }
                    }
                }
            }
        }
    }
}
