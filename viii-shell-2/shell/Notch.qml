// File: ~/viii-shell-2/shell/Notch.qml
// One notch. Everything lives inside it and it grows into whatever you open.
//
//   View = page (opened by you) or a flash (opens itself briefly):
//     pages:      music lyrics list quick screentime weather launcher
//     transients: card (new notification) osd ws net charge
//
//   qs ipc call notch toggle music|lyrics|list|quick|screentime|weather|launcher
//   qs ipc call notch close
//   (legacy targets music / audio / dpi / screentime / weather / omni / island still work)
//
// Click empty notch space: idle -> quick settings hub, open -> fold back.
// Esc folds it too. Tabs along the top jump between pages.

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects

PanelWindow {
    id: win

    anchors.top: true
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "notch"
    WlrLayershell.keyboardFocus: page === "launcher" ? WlrKeyboardFocus.Exclusive
                               : (page !== "" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None)
    margins.top: 0                       // a notch is flush with the edge
    implicitWidth: 1200
    implicitHeight: 820
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: idleH
    color: "transparent"

    // Only the notch itself catches clicks.
    mask: Region { item: notch }

    readonly property string font: "JetBrainsMono Nerd Font"

    // --- Tweak these ------------------------------------------------------
    readonly property real idleH: 38
    readonly property real pad: 16
    readonly property real topY: 50              // where page content starts (below the tab bar)
    readonly property int popupMs: 6000
    readonly property int osdMs: 1500
    readonly property int netMs: 3500
    readonly property int wsMs: 1600
    readonly property int chargeMs: 2600
    readonly property int swapMs: 6000
    // Spring feel (Hyprland-ish: quick, one soft overshoot). Higher spring = faster,
    // lower damping = bouncier.
    readonly property real springK: 4.2
    readonly property real springD: 0.32

    function hex(c) {
        const h = v => ("0" + Math.round(v * 255).toString(16)).slice(-2)
        return "#" + h(c.r) + h(c.g) + h(c.b)
    }
    function fmtSec(s) { return Math.floor(s / 60) + ":" + ("0" + Math.floor(s % 60)).slice(-2) }
    function fmtTime(sec) {
        if (!sec || sec <= 0) return "--"
        const m = Math.round(sec / 60)
        const h = Math.floor(m / 60)
        return h > 0 ? h + "h " + ("0" + (m % 60)).slice(-2) + "m" : m + "m"
    }

    // --- View state ---------------------------------------------------------
    property string page: ""              // opened by the user
    property string flashKind: ""         // opens by itself, folds on a timer
    readonly property string view: page !== "" ? page : flashKind

    readonly property var pageFiles: ({
        music: "NotchMusic.qml", lyrics: "NotchLyrics.qml", quick: "NotchQuick.qml",
        screentime: "ScreenTimePage.qml", weather: "WeatherPage.qml", launcher: "LauncherPage.qml"
    })

    function flash(kind, ms) {
        if (page !== "") return
        flashKind = kind
        transTimer.interval = ms
        transTimer.restart()
    }
    Timer { id: transTimer; onTriggered: win.flashKind = "" }

    function openPage(p) {
        flashKind = ""
        transTimer.stop()
        page = (page === p) ? "" : p
    }
    function closeAll() {
        page = ""
        flashKind = ""
        transTimer.stop()
    }

    Shortcut { sequence: "Escape"; onActivated: win.closeAll() }

    onPageChanged: {
        if ((page === "music" || page === "lyrics") && lines.length === 0 && key !== "") {
            status = "Loading lyrics…"
            debounce.restart()
        }
    }

    // Target size of the notch for the current view
    readonly property real idleW: idleRow.implicitWidth + 2 * pad
    readonly property real wsW: wsRow.implicitWidth + 32
    readonly property real netW: netRow.implicitWidth + 44
    readonly property real listH: topY + 26 + (notifCount > 0 ? Math.min(300, notifList.contentHeight) : 26) + 16

    readonly property real contentW: {
        switch (view) {
        case "osd": return 250
        case "ws": return wsW
        case "net": return netW
        case "card": return 390
        case "charge": return 220
        case "list": return 390
        case "music": return 450
        case "lyrics": return 450
        case "quick": return 430
        case "screentime": return 560
        case "weather": return 560
        case "launcher": return 560
        default: return idleW
        }
    }
    // The sides lean inward going down, so at the bottom the notch is narrower by
    // `slT` on each side. Expanded views get that much extra width, and the content
    // sits inside it, so nothing ever touches the slanted edge.
    function slantFor(h) { return Math.min(36, 9 + h * 0.06) }
    readonly property bool expanded: ["card","list","music","lyrics","quick","screentime","weather","launcher"].indexOf(view) >= 0
    readonly property real slT: slantFor(th)
    readonly property real tw: contentW + (expanded ? 2 * slT : 0)
    readonly property real th: {
        switch (view) {
        case "osd": return 58
        case "ws": return 64
        case "net": return 54
        case "card": return popupCard.implicitHeight + 36
        case "charge": return 54
        case "list": return listH
        case "music": return 226
        case "lyrics": return 330
        case "quick": return 350
        case "screentime": return 756
        case "weather": return 756
        case "launcher": return 660
        default: return idleH
        }
    }

    // --- Battery / power ------------------------------------------------------
    readonly property var bat: UPower.displayDevice
    readonly property bool charging: bat.state === UPowerDeviceState.Charging
    readonly property int pct: Math.round(bat.percentage * 100)
    readonly property color batTone: charging ? Theme.good
                                   : (pct <= 15 ? Theme.bad
                                   : (pct <= 30 ? Theme.accentHi : Theme.accent))
    property int clockMode: 0            // 0 time, 1 date, 2 battery
    readonly property real secsLeft: charging ? bat.timeToFull : bat.timeToEmpty
    Timer { id: swapTimer; interval: win.swapMs; onTriggered: win.clockMode = 0 }

    // --- Music (shared by idle row, music page, lyrics page) ----------------
    readonly property var player: {
        const ps = Mpris.players.values
        if (ps.length === 0) return null
        for (let i = 0; i < ps.length; i++)
            if (ps[i].identity.toLowerCase().indexOf("spotify") >= 0) return ps[i]
        for (let i = 0; i < ps.length; i++) {
            const id = ps[i].identity.toLowerCase()
            if (id.indexOf("amberol") >= 0 || id.indexOf("gapless") >= 0) return ps[i]
        }
        for (let i = 0; i < ps.length; i++) if (ps[i].isPlaying) return ps[i]
        return ps[0]
    }
    readonly property bool playing: player !== null && player.isPlaying

    // --- Beat: live spectrum from cava, only runs while music plays ---
    // bands = [bass, mids, highs], each 0..1
    property var bands: [0, 0, 0]
    Process {
        id: cava
        running: win.playing
        command: ["cava", "-p", Quickshell.shellPath("scripts/cava-notch.conf")]
        stdout: SplitParser {
            onRead: line => {
                // "12;40;33;..." -> [0.12, 0.40, 0.33, ...]
                const v = line.split(";").filter(s => s !== "").map(s => parseInt(s) / 100)
                if (v.length < 3) return
                // split the bars into thirds and average each third
                const t = Math.floor(v.length / 3)
                const avg = (a, b) => { let s = 0; for (let i = a; i < b; i++) s += v[i]; return s / Math.max(1, b - a) }
                win.bands = [avg(0, t), avg(t, 2 * t), avg(2 * t, v.length)]
            }
        }
        onRunningChanged: if (!running) win.bands = [0, 0, 0]
    }

    readonly property string parsedTitle: {
        if (!player || !player.trackTitle) return ""
        let t = player.trackTitle
        if (t.startsWith("file://")) t = decodeURIComponent(t.substring(t.lastIndexOf("/") + 1))
        t = t.replace(/\.(mp3|flac|m4a|ogg|wav|opus|aac)$/i, "")
        if ((!player.trackArtist || player.trackArtist.length === 0) && t.indexOf(" - ") !== -1)
            return t.split(" - ").slice(1).join(" - ").trim()
        return t
    }
    readonly property string parsedArtist: {
        if (!player) return ""
        if (player.trackArtist && player.trackArtist.length > 0) return player.trackArtist
        if (player.trackTitle) {
            let t = player.trackTitle
            if (t.startsWith("file://")) t = decodeURIComponent(t.substring(t.lastIndexOf("/") + 1))
            if (t.indexOf(" - ") !== -1) return t.split(" - ")[0].trim()
        }
        return ""
    }

    property var lines: []
    property string status: ""
    property bool again: false
    readonly property string key: player ? parsedArtist + "|" + parsedTitle : ""
    readonly property bool lyricsWanted: page === "music" || page === "lyrics"

    onKeyChanged: {
        lines = []
        status = key ? "Loading lyrics…" : ""
        if (lyricsWanted) debounce.restart()
    }
    Timer { id: debounce; interval: 400; onTriggered: win.fetchLyrics() }

    function fetchLyrics() {
        if (!parsedTitle) return
        if (lrc.running) { again = true; return }
        let args = ["curl", "-s", "-G", "-A", "quickshell-player", "https://lrclib.net/api/search",
                    "--data-urlencode", "track_name=" + parsedTitle]
        if (parsedArtist) args.push("--data-urlencode", "artist_name=" + parsedArtist)
        lrc.command = args
        lrc.running = true
    }
    Process {
        id: lrc
        stdout: StdioCollector { onStreamFinished: win.parseLyrics(text) }
        onExited: if (win.again) { win.again = false; win.fetchLyrics() }
    }
    function parseLyrics(raw) {
        try {
            const results = JSON.parse(raw)
            let best = null, bestDiff = 1e9
            const len = player ? player.length : 0
            for (const r of results) {
                if (!r.syncedLyrics) continue
                const diff = len > 0 ? Math.abs((r.duration || 0) - len) : 0
                if (diff < bestDiff) { best = r; bestDiff = diff }
            }
            if (!best) { status = "No synced lyrics found"; return }
            const out = []
            for (const l of best.syncedLyrics.split("\n")) {
                const m = l.match(/^\[(\d+):(\d+(?:\.\d+)?)\](.*)$/)
                if (m) out.push({ t: parseInt(m[1]) * 60 + parseFloat(m[2]), text: m[3].trim() })
            }
            lines = out
            status = out.length ? "" : "No synced lyrics found"
        } catch (e) { status = "No lyrics found" }
    }
    readonly property int lyricIdx: {
        const pos = player ? player.position : 0
        let i = -1
        for (let k = 0; k < lines.length; k++) { if (lines[k].t <= pos + 0.3) i = k; else break }
        return i
    }
    function lineAt(i) { return (i >= 0 && i < lines.length) ? lines[i].text : "" }

    Timer {
        interval: 250; repeat: true
        running: win.lyricsWanted && win.playing
        onTriggered: win.player.positionChanged()
    }

    // --- Notifications (newest first) -----------------------------------------
    property var popup: null
    readonly property var notifItems: server.trackedNotifications.values.slice().reverse()
    readonly property int notifCount: notifItems.length

    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        actionsSupported: true
        imageSupported: true
        onNotification: (n) => {
            n.tracked = true
            win.popup = n
            n.closed.connect(() => {
                if (win.popup === n) {
                    win.popup = null
                    if (win.flashKind === "card") win.flashKind = ""
                }
            })
            win.flash("card", win.popupMs)
        }
    }

    // --- IPC ---------------------------------------------------------------------
    IpcHandler {
        target: "notch"
        function toggle(page: string): void { win.openPage(page) }
        function close(): void { win.closeAll() }
        function pulse(): void { win.pulseNow() }
    }
    IpcHandler { target: "island"; function notifications(): void { win.openPage("list") }
                                   function workspaces(): void { win.showWs() }
                                   function pulse(): void { win.pulseNow() } }
    IpcHandler { target: "music"; function toggle(): void { win.openPage("music") } }
    IpcHandler { target: "audio"; function toggle(): void { win.openPage("quick") } }
    IpcHandler { target: "dpi"; function toggle(): void { win.openPage("quick") } }
    IpcHandler { target: "screentime"; function toggle(): void { win.openPage("screentime") } }
    IpcHandler {
        target: "omni"
        function toggle(): void { win.openPage("launcher") }
        function show(): void { if (win.page !== "launcher") win.openPage("launcher") }
        function hide(): void { if (win.page === "launcher") win.closeAll() }
    }

    // Weather place / units live here so they survive the page closing.
    property string wxPlace: "Abuja"
    property real wxLat: 9.0765
    property real wxLon: 7.3986
    property bool wxUseF: false
    IpcHandler {
        target: "weather"
        function toggle(): void { win.openPage("weather") }
        function show(): void { if (win.page !== "weather") win.openPage("weather") }
        function hide(): void { if (win.page === "weather") win.closeAll() }
        function refresh(): void { if (win.page === "weather" && pageLoader.item) pageLoader.item.load() }
        function units(): void { win.wxUseF = !win.wxUseF }
        function setPlace(name: string, la: real, lo: real): void {
            win.wxPlace = name
            win.wxLat = la
            win.wxLon = lo
            if (win.page === "weather" && pageLoader.item) pageLoader.item.reset()
        }
    }

    // --- Workspaces ----------------------------------------------------------------
    property int lastWsId: -1
    readonly property var wsIds: {
        const ids = []
        const vals = Hyprland.workspaces.values
        for (let i = 0; i < vals.length; i++) if (vals[i].id > 0) ids.push(vals[i].id)
        const f = Hyprland.focusedWorkspace
        if (f && f.id > 0 && ids.indexOf(f.id) < 0) ids.push(f.id)
        ids.sort((a, b) => a - b)
        return ids
    }
    function showWs() { flash("ws", wsMs) }
    function wsEvent() {
        const f = Hyprland.focusedWorkspace
        if (!f) return
        const first = lastWsId === -1
        const changed = f.id !== lastWsId
        lastWsId = f.id
        if (first || !changed) return
        showWs()
    }
    Connections { target: Hyprland; function onFocusedWorkspaceChanged() { win.wsEvent() } }

    // --- OSD: volume + brightness ------------------------------------------------
    property string osdIcon: ""
    property real osdValue: 0
    property bool osdMuted: false
    readonly property bool osdOn: view === "osd"

    function showOsd(icon, value, muted) {
        osdIcon = icon
        osdValue = value
        osdMuted = muted
        flash("osd", osdMs)
    }
    Timer { id: osdArm; interval: 2000; running: true }

    readonly property var sink: Pipewire.defaultAudioSink
    property real lastVol: -1
    property bool lastMuted: false
    onSinkChanged: osdArm.restart()
    PwObjectTracker { objects: [win.sink] }
    Connections {
        target: win.sink ? win.sink.audio : null
        function onVolumeChanged() { win.volEvent() }
        function onMutedChanged() { win.volEvent() }
    }
    function volEvent() {
        const a = sink ? sink.audio : null
        if (!a) return
        const changed = a.volume !== lastVol || a.muted !== lastMuted
        lastVol = a.volume
        lastMuted = a.muted
        if (osdArm.running || !changed) return
        showOsd(a.muted || a.volume === 0 ? "\uf026" : (a.volume > 0.5 ? "\uf028" : "\uf027"), a.volume, a.muted)
    }

    property string blPath: ""
    property real blMax: 1
    property real lastBl: -1
    Process {
        running: true
        command: ["sh", "-c", "d=$(ls -d /sys/class/backlight/* 2>/dev/null | head -n1); [ -n \"$d\" ] && echo \"$d $(cat $d/max_brightness)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(" ")
                if (p.length === 2) { win.blMax = parseInt(p[1]); win.blPath = p[0] }
            }
        }
    }
    FileView {
        path: win.blPath !== "" ? win.blPath + "/brightness" : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const v = parseInt(text())
            if (isNaN(v)) return
            const first = win.lastBl < 0
            const changed = v !== win.lastBl
            win.lastBl = v
            if (first || !changed || osdArm.running) return
            win.showOsd("\uf185", v / win.blMax, false)
        }
    }

    // --- Battery alerts ------------------------------------------------------------
    property int lastBatLevel: 0
    function batLevel(p) { return p <= 10 ? 10 : (p <= 20 ? 20 : (p <= 30 ? 30 : 100)) }
    function checkBattery() {
        const p = Math.round(bat.percentage * 100)
        const lvl = batLevel(p)
        if (lastBatLevel !== 0 && !charging && lvl < lastBatLevel) {
            Quickshell.execDetached(["notify-send", "-a", "Battery",
                "-u", lvl <= 10 ? "critical" : "normal",
                "-i", lvl <= 10 ? "battery-empty" : "battery-low",
                "Battery at " + p + "%", "Plug in soon."])
        }
        lastBatLevel = lvl
    }
    property int lastPct: -1
    Component.onCompleted: lastPct = pct
    onPctChanged: {
        if (lastPct > 0 && pct !== lastPct) pulseNow()
        lastPct = pct
        checkBattery()
    }
    Connections {
        target: win.bat
        function onStateChanged() {
            win.checkBattery()
            win.pulseNow()
            if (win.charging) win.flash("charge", win.chargeMs)
        }
    }

    // --- RAM alert ----------------------------------------------------------------------
    Process {
        running: screen === Quickshell.screens[0]
        command: ["sh", Quickshell.shellPath("scripts/memwatch.sh")]
        stdout: SplitParser {
            onRead: line => {
                const i = line.indexOf("|")
                if (i < 0) return
                Quickshell.execDetached(["notify-send", "-a", "Memory", "-u", "critical",
                    "-i", "dialog-warning", "RAM at " + line.slice(0, i) + "%",
                    "Biggest users:\n" + line.slice(i + 1)])
            }
        }
    }

    // --- Network -----------------------------------------------------------------------------
    property string netIface: ""
    property string netSsid: ""
    property bool netKnown: false
    readonly property bool online: netIface !== ""
    readonly property bool isWifi: netIface.startsWith("w")

    function netUpdate(iface, ssid) {
        const wasOnline = netIface !== ""
        const nowOnline = iface !== ""
        const changed = wasOnline !== nowOnline
            || (nowOnline && (iface !== netIface || (ssid !== "" && ssid !== netSsid)))
        const first = !netKnown
        netIface = iface
        netSsid = ssid
        netKnown = true
        if (first || !changed) return
        flash("net", netMs)
    }
    Process {
        id: netProc
        command: ["sh", "-c",
            "i=$(ip -o route show default | awk '{print $5; exit}'); "
            + "s=$(iwgetid -r 2>/dev/null || nmcli -t -f active,ssid dev wifi 2>/dev/null | sed -n 's/^yes://p' | head -n1); "
            + "printf '%s\\n%s\\n' \"$i\" \"$s\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.split("\n")
                win.netUpdate((l[0] || "").trim(), (l[1] || "").trim())
            }
        }
    }
    Process {
        running: true
        command: ["ip", "monitor", "route"]
        stdout: SplitParser { onRead: netDebounce.restart() }
    }
    Timer { id: netDebounce; interval: 600; onTriggered: if (!netProc.running) netProc.running = true }
    Timer { interval: 10000; running: true; repeat: true; triggeredOnStart: true
            onTriggered: if (!netProc.running) netProc.running = true }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    // --- Battery-change pulse --------------------------------------------------------------------
    property real pulse: 0
    function pulseNow() { pulseAnim.restart() }
    SequentialAnimation {
        id: pulseAnim
        NumberAnimation { target: win; property: "pulse"; to: 1;    duration: 180; easing.type: Easing.OutCubic }
        NumberAnimation { target: win; property: "pulse"; to: 0.25; duration: 160; easing.type: Easing.InOutQuad }
        NumberAnimation { target: win; property: "pulse"; to: 1;    duration: 180; easing.type: Easing.OutCubic }
        NumberAnimation { target: win; property: "pulse"; to: 0;    duration: 320; easing.type: Easing.InOutQuad }
    }

    // ══════════════════════════════════════════════════════════════════════
    // THE NOTCH
    // ══════════════════════════════════════════════════════════════════════
    Item {
        id: notch
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter

        // Springy size: overshoots slightly and settles, like Hyprland's default curve.
        property real nw: win.tw
        property real nh: win.th
        Behavior on nw { SpringAnimation { spring: win.springK; damping: win.springD; epsilon: 0.4 } }
        Behavior on nh { SpringAnimation { spring: win.springK; damping: win.springD; epsilon: 0.4 } }
        width: Math.max(90, nw)
        height: Math.max(26, nh)

        // Geometry: wide at the top, sides slant inward, bottom corners softly rounded.
        // The slant grows with the height so a tall notch leans a little more.
        readonly property real sl: win.slantFor(height)
        readonly property real rr: Math.min(22, height * 0.38)
        readonly property real len: Math.sqrt(sl * sl + height * height)
        readonly property real rx1: width - sl + sl / len * rr
        readonly property real ry1: height - height / len * rr
        readonly property real rx2: width - sl - rr
        readonly property real lx3: sl + rr
        readonly property real lx4: sl - sl / len * rr

        // Open outline: down the left slant, along the bottom, up the right slant.
        // The top edge is NOT part of it (that is where the equalizer lives).
        readonly property string outline:
            "M0,0 L" + lx4 + "," + ry1
            + " Q" + sl + "," + height + " " + lx3 + "," + height
            + " L" + rx2 + "," + height
            + " Q" + (width - sl) + "," + height + " " + rx1 + "," + ry1
            + " L" + width + ",0"
        readonly property real perim: 2 * len + width - 2 * sl - rr

        readonly property real sw: (win.osdOn ? 5 : 2) + win.pulse * 3
        property real baseSwDummy: 0
        property real gauge: win.osdOn ? Math.min(1, Math.max(0, win.osdValue))
                                       : Math.min(1, Math.max(0, win.pct / 100))
        Behavior on gauge { NumberAnimation { duration: win.osdOn ? 140 : 600; easing.type: Easing.OutCubic } }
        property color gaugeColor: win.osdOn ? (win.osdMuted ? Theme.fgDim : Theme.accent) : win.batTone
        Behavior on gaugeColor { ColorAnimation { duration: 250 } }

        Shape {
            anchors.fill: parent
            layer.enabled: true
            layer.samples: 4

            // body
            ShapePath {
                fillColor: Theme.panel
                strokeColor: "transparent"
                strokeWidth: -1
                PathSvg { path: notch.outline + " Z" }
            }
            // track
            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.rgba(1, 1, 1, 0.12)
                strokeWidth: notch.sw
                capStyle: ShapePath.RoundCap
                PathSvg { path: notch.outline }
            }
            // gauge (battery at rest, level during volume / brightness)
            ShapePath {
                fillColor: "transparent"
                strokeColor: notch.gaugeColor
                strokeWidth: notch.sw
                capStyle: win.osdOn ? ShapePath.FlatCap : ShapePath.RoundCap
                strokeStyle: ShapePath.DashLine
                dashPattern: [Math.max(0.01, notch.perim * notch.gauge / notch.sw), notch.perim]
                PathSvg { path: notch.outline }
            }
        }

        // ── Equalizer: wavy lines along the top edge, alive while music plays ──
        Canvas {
            id: eq
            x: notch.sl + 8
            y: 0
            width: Math.max(10, notch.width - 2 * (notch.sl + 8))
            height: 10
            property real phase: 0
            property real amp: win.playing ? 1 : 0
            property var cur: [0, 0, 0]   // smoothed band levels
            Behavior on amp { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
            onAmpChanged: requestPaint()
            onWidthChanged: requestPaint()
            Component.onCompleted: requestPaint()

            Timer {
                interval: 40; repeat: true
                running: win.playing || eq.amp > 0.02
                onTriggered: {
                    eq.phase += 0.22
                    const b = win.bands
                    for (let i = 0; i < 3; i++) {
                        const d = b[i] - eq.cur[i]
                        eq.cur[i] += d * (d > 0 ? 0.6 : 0.15)   // fast attack, slow release
                    }
                    eq.requestPaint()
                }
            }

            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                const cols = [win.hex(Theme.accentHi), win.hex(Theme.accent), win.hex(Theme.fgDim)]
                const L = [
                    { f: 0.070, s: 1.0,  a: 1.00, w: 1.6, al: 0.95 },
                    { f: 0.045, s: -1.4, a: 0.75, w: 1.3, al: 0.60 },
                    { f: 0.110, s: 2.1,  a: 0.50, w: 1.0, al: 0.40 }
                ]
                // a slow "beat" so the amplitude breathes instead of being a flat sine
                for (let i = 0; i < 3; i++) {
                    const l = L[i]
                    // line 0 follows bass, line 1 mids, line 2 highs; small floor so it never goes flat while playing
                    const lvl = 0.12 + 0.88 * Math.min(1, cur[i] * 1.6)
                    ctx.beginPath()
                    ctx.lineWidth = l.w
                    ctx.strokeStyle = cols[i]
                    ctx.globalAlpha = l.al
                    for (let x = 0; x <= width; x += 2) {
                        const env = Math.sin(Math.PI * x / width)
                        const y = height / 2 + Math.sin(x * l.f + phase * l.s) * amp * lvl * l.a * env * (height / 2 - 1.5)
                        if (x === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                    }
                    ctx.stroke()
                }
                ctx.globalAlpha = 1
            }
        }

        // ── Everything inside the notch ──
        Item {
            id: body
            anchors.fill: parent
            clip: true

            // Click empty space: idle -> hub, open -> fold
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (win.page !== "") win.closeAll()
                    else if (win.flashKind !== "") { win.flashKind = ""; transTimer.stop() }
                    else win.openPage("quick")
                }
            }
            HoverHandler {
                onHoveredChanged: {
                    if (win.flashKind === "" || win.page !== "") return
                    if (hovered) transTimer.stop(); else transTimer.restart()
                }
            }

            // ── IDLE: dot, clock, bell, music (always), open windows ──
            Row {
                id: idleRow
                anchors.horizontalCenter: parent.horizontalCenter
                y: 10
                height: win.idleH - 12
                spacing: 12
                opacity: win.view === "" ? 1 : 0
                visible: opacity > 0.01
                enabled: win.view === ""
                Behavior on opacity { NumberAnimation { duration: 150 } }

                // network dot (tap: quick settings)
                Item {
                    width: 14; height: parent.height
                    Rectangle {
                        anchors.centerIn: parent
                        width: 6; height: 6; radius: 3
                        color: win.online ? Theme.fgDim : Theme.bad
                        SequentialAnimation on opacity {
                            running: !win.online
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.25; duration: 700 }
                            NumberAnimation { to: 1.0; duration: 700 }
                        }
                    }
                    MouseArea { anchors.fill: parent; onClicked: win.openPage("quick") }
                }

                // clock: time -> date -> battery
                Text {
                    id: clockText
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: win.font; font.pixelSize: 13; font.weight: Font.DemiBold
                    font.letterSpacing: 1
                    color: win.clockMode === 2 ? win.batTone : Theme.fg
                    text: win.clockMode === 0 ? Qt.formatDateTime(clock.date, "HH:mm")
                        : (win.clockMode === 1 ? Qt.formatDateTime(clock.date, "ddd d MMM")
                        : win.pct + "%  " + win.fmtTime(win.secsLeft))
                    MouseArea {
                        anchors.fill: parent; anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { win.clockMode = (win.clockMode + 1) % 3; swapTimer.restart() }
                    }
                }

                // bell
                Item {
                    id: bellSec
                    width: 24; height: 20
                    anchors.verticalCenter: parent.verticalCenter
                    property int prevCount: 0
                    readonly property int cnt: win.notifCount
                    onCntChanged: { if (cnt > prevCount) ring.restart(); prevCount = cnt }

                    Text {
                        id: bellIcon
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: win.font; font.pixelSize: 14
                        text: "\uf0f3"
                        color: win.notifCount > 0 ? Theme.fg : Theme.fgDim
                        transformOrigin: Item.Top
                        SequentialAnimation {
                            id: ring
                            NumberAnimation { target: bellIcon; property: "rotation"; to: 18;  duration: 80;  easing.type: Easing.OutQuad }
                            NumberAnimation { target: bellIcon; property: "rotation"; to: -16; duration: 120; easing.type: Easing.InOutQuad }
                            NumberAnimation { target: bellIcon; property: "rotation"; to: 10;  duration: 120; easing.type: Easing.InOutQuad }
                            NumberAnimation { target: bellIcon; property: "rotation"; to: -6;  duration: 100; easing.type: Easing.InOutQuad }
                            NumberAnimation { target: bellIcon; property: "rotation"; to: 0;   duration: 100; easing.type: Easing.OutQuad }
                        }
                    }
                    Rectangle {
                        x: 9; y: 0
                        height: 12
                        width: Math.max(12, badgeText.implicitWidth + 6)
                        radius: 6
                        color: Theme.accent
                        visible: win.notifCount > 0
                        Text {
                            id: badgeText
                            anchors.centerIn: parent
                            font.family: win.font; font.pixelSize: 8; font.weight: Font.Bold
                            color: Theme.accentText
                            text: win.notifCount > 9 ? "9+" : win.notifCount
                        }
                    }
                    MouseArea {
                        anchors.fill: parent; anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.openPage("list")
                    }
                }

                // music: album art + play/pause + title (prev/next live on the music page)
                Row {
                    spacing: 8
                    anchors.verticalCenter: parent.verticalCenter
                
                    // album art thumbnail: only takes space once the player provides an image
                    Rectangle {
                        width: 22; height: 22; radius: 5
                        anchors.verticalCenter: parent.verticalCenter
                        visible: art.status === Image.Ready
                        color: Qt.rgba(1, 1, 1, 0.08)
                        clip: true
                        Image {
                            id: art
                            anchors.fill: parent
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                            sourceSize: Qt.size(44, 44)   // decode small to save RAM
                            source: win.player && win.player.trackArtUrl ? win.player.trackArtUrl : ""
                        }
                    }
                    Rectangle {
                        width: 22; height: 22; radius: 11
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.accent
                        opacity: win.player ? 1 : 0.35
                        scale: playArea.pressed ? 0.9 : 1
                        Behavior on scale { NumberAnimation { duration: 70 } }
                        Text {
                            anchors.centerIn: parent
                            font.family: win.font; font.pixelSize: 9
                            color: Theme.accentText
                            text: win.playing ? "\uf04c" : "\uf04b"
                        }
                        MouseArea { id: playArea; anchors.fill: parent
                                    onClicked: if (win.player) win.player.togglePlaying() }
                    }
                    // title: tap to grow into the music card
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 130
                        elide: Text.ElideRight
                        font.family: win.font; font.pixelSize: 12
                        font.italic: win.parsedTitle === ""
                        color: win.parsedTitle !== "" ? Theme.fg : Theme.fgDim
                        text: win.parsedTitle !== "" ? win.parsedTitle : "it's quiet here"
                        MouseArea { anchors.fill: parent; anchors.margins: -4
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: win.openPage("music") }
                    }
                }

                // open windows: the active one is stamped
                Row {
                    id: iconsRow
                    spacing: 4
                    anchors.verticalCenter: parent.verticalCenter
                    visible: ToplevelManager.toplevels.values.length > 0
                    Repeater {
                        model: ToplevelManager.toplevels
                        delegate: Rectangle {
                            required property var modelData
                            width: 22; height: 22; radius: 5
                            color: modelData.activated ? Qt.alpha(Theme.accent, 0.14) : "transparent"
                            border.width: modelData.activated ? 1 : 0
                            border.color: Theme.accent
                            rotation: modelData.activated ? -4 : 0
                            Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                            Image {
                                anchors.centerIn: parent
                                width: 14; height: 14
                                sourceSize: Qt.size(28, 28)
                                opacity: modelData.activated ? 1 : 0.5
                                source: Quickshell.iconPath(modelData.appId, "application-x-executable")
                            }
                            MouseArea { anchors.fill: parent; onClicked: modelData.activate() }
                        }
                    }
                }
            }

            // ── TRANSIENT: new notification card ──
            IslandNotif {
                id: popupCard
                visible: win.view === "card" && win.popup !== null
                y: 16
                anchors.horizontalCenter: parent.horizontalCenter
                width: 366
                notif: win.popup
            }

            // ── TRANSIENT: volume / brightness ──
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 22
                spacing: 12
                opacity: win.view === "osd" ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 180 } }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: win.font; font.pixelSize: 18
                    color: Theme.fg
                    text: win.osdIcon
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 150; height: 6; radius: 3
                    color: Qt.rgba(1, 1, 1, 0.12)
                    Rectangle {
                        width: parent.width * Math.min(1, Math.max(0, win.osdValue))
                        height: parent.height; radius: 3
                        color: win.osdMuted ? Theme.fgDim : Theme.accent
                    }
                }
            }

            // ── TRANSIENT: workspace chips ──
            Row {
                id: wsRow
                anchors.horizontalCenter: parent.horizontalCenter
                y: 14
                spacing: 6
                opacity: win.view === "ws" ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 180 } }
                Repeater {
                    model: win.wsIds
                    delegate: Rectangle {
                        id: chip
                        required property var modelData
                        readonly property bool active: Hyprland.focusedWorkspace !== null
                                                       && Hyprland.focusedWorkspace.id === modelData
                        readonly property var apps: {
                            const out = []
                            const v = Hyprland.toplevels.values
                            for (let i = 0; i < v.length; i++)
                                if (v[i].workspace && v[i].workspace.id === modelData) out.push(v[i])
                            return out.slice(0, 3)
                        }
                        height: 36
                        width: chipRow.implicitWidth + 22
                        radius: 12
                        color: active ? Qt.alpha(Theme.accent, 0.14) : "transparent"
                        border.width: 1
                        border.color: active ? Theme.accent : Qt.rgba(1, 1, 1, 0.08)
                        Row {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                font.family: win.font; font.pixelSize: 13; font.weight: Font.DemiBold
                                color: chip.active ? Theme.accentHi : Theme.fgDim
                                text: chip.modelData
                            }
                            Repeater {
                                model: chip.apps
                                delegate: Image {
                                    required property var modelData
                                    readonly property string appId: modelData.wayland
                                        ? modelData.wayland.appId : (modelData.lastIpcObject.class || "")
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 16; height: 16
                                    sourceSize: Qt.size(32, 32)
                                    opacity: chip.active ? 1 : 0.55
                                    source: Quickshell.iconPath(appId, "application-x-executable")
                                }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Hyprland.dispatch("workspace " + chip.modelData)
                        }
                    }
                }
            }

            // ── TRANSIENT: wifi change ──
            Row {
                id: netRow
                anchors.horizontalCenter: parent.horizontalCenter
                y: 20
                spacing: 8
                opacity: win.view === "net" ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 180 } }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: win.font; font.pixelSize: 13
                    text: !win.online ? "\uf071" : (win.isWifi ? "\uf1eb" : "\uf0e8")
                    color: win.online ? Theme.good : Theme.bad
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: win.font; font.pixelSize: 12; font.weight: Font.DemiBold
                    color: Theme.fg
                    text: win.online ? "Connected" : "Disconnected"
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: win.online
                    width: Math.min(implicitWidth, 110)
                    elide: Text.ElideRight
                    font.family: win.font; font.pixelSize: 11
                    color: Theme.fgDim
                    text: win.netSsid !== "" ? win.netSsid : win.netIface
                }
            }

            // ── TRANSIENT: plugged in ──
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 21
                font.family: win.font; font.pixelSize: 12; font.weight: Font.DemiBold
                color: Theme.good
                text: "\uf0e7  Charging · " + win.pct + "%"
                opacity: win.view === "charge" ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 180 } }
            }

            // ── PAGES: tab bar + content ──
            Row {
                id: tabs
                anchors.horizontalCenter: parent.horizontalCenter
                y: 12
                spacing: 6
                opacity: win.page !== "" ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 180 } }
                Repeater {
                    model: [
                        { k: "music", g: "\uf001" }, { k: "lyrics", g: "\uf10d" },
                        { k: "list", g: "\uf0f3" }, { k: "quick", g: "\uf1de" },
                        { k: "screentime", g: "\uf017" }, { k: "weather", g: "\uf0c2" },
                        { k: "launcher", g: "\uf002" }
                    ]
                    IconBtn {
                        required property var modelData
                        width: 30; height: 30; radius: 15
                        glyph: modelData.g; glyphSize: 12
                        tone: win.page === modelData.k ? Theme.accentHi : Theme.fgDim
                        onClicked: { if (win.page === modelData.k) win.closeAll(); else win.page = modelData.k }
                    }
                }
            }

            // Notification list: latest first
            Item {
                y: win.topY
                anchors.horizontalCenter: parent.horizontalCenter
                width: 362
                height: win.th - win.topY
                visible: win.page === "list"

                Text {
                    anchors.left: parent.left
                    y: 2
                    text: "Notifications"
                    color: Theme.accentHi
                    font.family: win.font; font.pixelSize: 12; font.weight: Font.DemiBold
                }
                Text {
                    anchors.right: parent.right
                    y: 3
                    visible: win.notifCount > 0
                    text: "Clear all"
                    color: clearArea.containsMouse ? Theme.accentHi : Theme.fgDim
                    font.family: win.font; font.pixelSize: 11
                    MouseArea {
                        id: clearArea
                        anchors.fill: parent; anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.notifItems.slice().forEach(n => n.dismiss())
                    }
                }
                Text {
                    y: 28
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: win.notifCount === 0
                    text: "You're all caught up"
                    color: Theme.fgDim
                    font.family: win.font; font.pixelSize: 11
                }
                ListView {
                    id: notifList
                    y: 26
                    width: parent.width
                    height: win.notifCount > 0 ? Math.min(300, contentHeight) : 0
                    clip: true
                    spacing: 8
                    boundsBehavior: Flickable.StopAtBounds
                    model: win.notifItems
                    delegate: IslandNotif {
                        required property var modelData
                        width: notifList.width
                        notif: modelData
                    }
                }
            }

            // Every other page is its own file, created only while it is open
            Loader {
                id: pageLoader
                x: win.slT; y: win.topY
                width: win.contentW
                height: win.th - win.topY - 8
                readonly property string wantFile: win.pageFiles[win.page] || ""
                active: wantFile !== ""
                // setSource hands `n` over BEFORE the page's Component.onCompleted runs
                onWantFileChanged: { if (wantFile !== "") setSource(wantFile, { n: win }); else setSource("") }
                onLoaded: fadeIn.restart()
                NumberAnimation { id: fadeIn; target: pageLoader; property: "opacity"
                                  from: 0; to: 1; duration: 240; easing.type: Easing.OutCubic }
            }
            Text {
                anchors.centerIn: parent
                visible: pageLoader.status === Loader.Error
                color: Theme.fgDim
                font.family: win.font; font.pixelSize: 12
                text: win.pageFiles[win.page] + " not ported yet"
            }
        }
    }
}
