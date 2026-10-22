// File: ~/viii-shell-2/shell/WeatherPanel.qml
// Weather, glass style. One page, no scrolling:
//   character-built sky, big temperature + high/low, stat chips, 24h sparkline, 5-day strip
//   qs ipc call weather toggle | show | hide | refresh | units
//   qs ipc call weather setPlace "Lagos" 6.5244 3.3792
// Keys: Esc close, R refresh, U toggle units

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool shown: false
    property bool alive: false
    readonly property int closeMs: 0
    readonly property string mono: "JetBrainsMono Nerd Font"

    property string place: "Abuja"
    property real lat: 9.0765
    property real lon: 7.3986
    property bool useF: false

    property var wx: null
    property string err: ""
    property real updatedAt: 0
    property real progress: 0

    // Targets the animated scene eases toward
    property real tCloud: 0.2
    property real tRain: 0
    property real tSnow: 0
    property real tFog: 0
    property real tStorm: 0
    property real tNight: 0
    property real tWind: 0
    property real tDir: 270

    readonly property string apiUrl: "https://api.open-meteo.com/v1/forecast?latitude=" + lat + "&longitude=" + lon
        + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,is_day,weather_code,cloud_cover,wind_speed_10m,wind_direction_10m,precipitation"
        + "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max"
        + "&hourly=temperature_2m&forecast_days=6&timezone=auto"

    onShownChanged: {
        if (shown) {
            unload.stop()
            alive = true
            if (wx === null || Date.now() - updatedAt > 300000) load()
            else anim.restart()
        } else {
            anim.stop()
            unload.restart()
        }
    }
    Timer { id: unload; interval: root.closeMs; onTriggered: root.alive = false }
    Timer { interval: 600000; repeat: true; running: root.alive; onTriggered: root.load() }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    NumberAnimation {
        id: anim
        target: root
        property: "progress"
        from: 0
        to: 1
        duration: 1100
        easing.type: Easing.OutCubic
    }

    IpcHandler {
        target: "weather"
        function toggle(): void { root.shown = !root.shown }
        function show(): void { root.shown = true }
        function hide(): void { root.shown = false }
        function refresh(): void { root.load() }
        function units(): void { root.useF = !root.useF }
        function setPlace(name: string, la: real, lo: real): void {
            root.place = name
            root.lat = la
            root.lon = lo
            root.wx = null
            root.load()
        }
    }

    // ── helpers ──
    function hex(c) {
        const h = v => ("0" + Math.round(v * 255).toString(16)).slice(-2)
        return "#" + h(c.r) + h(c.g) + h(c.b)
    }
    function sp(v, size, col, weight) {
        return '<span style="font-size:' + size + 'px; font-weight:' + (weight || 400) + '; color:' + hex(col) + ';">' + v + '</span>'
    }
    function conv(c) { return useF ? Math.round(c * 9 / 5 + 32) : Math.round(c) }
    // Big number, small unit
    function tempHtml(c, ns, us, col) {
        return sp(conv(c), ns, col, 600) + sp("&deg;" + (useF ? "F" : "C"), us, Theme.fgDim, 400)
    }
    function numUnit(v, u, ns, us, col) {
        return sp(v, ns, col, 600) + (u === "" ? "" : sp("&nbsp;" + u, us, Theme.fgDim, 400))
    }
    function hiLo(hi, lo) {
        return sp(conv(hi), 18, Theme.fg, 600) + sp("&deg;", 10, Theme.fgDim, 400)
            + "&nbsp;" + sp(conv(lo), 13, Theme.fgDim, 400) + sp("&deg;", 9, Theme.fgDim, 400)
    }
    function compass(d) {
        return ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Math.round(d / 45) % 8]
    }
    function dayName(iso) {
        return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][new Date(iso + "T00:00:00").getDay()]
    }
    function agoMs(t, tick) {
        if (t === 0) return "never"
        const s = Math.max(0, (Date.now() - t) / 1000)
        if (s < 60) return "just now"
        if (s < 3600) return Math.floor(s / 60) + "m ago"
        return Math.floor(s / 3600) + "h ago"
    }
    function cond(k) {
        const m = {
            0: "Clear sky", 1: "Mainly clear", 2: "Partly cloudy", 3: "Overcast",
            45: "Fog", 48: "Rime fog",
            51: "Light drizzle", 53: "Drizzle", 55: "Heavy drizzle", 56: "Freezing drizzle", 57: "Freezing drizzle",
            61: "Light rain", 63: "Rain", 65: "Heavy rain", 66: "Freezing rain", 67: "Freezing rain",
            71: "Light snow", 73: "Snow", 75: "Heavy snow", 77: "Snow grains",
            80: "Light showers", 81: "Showers", 82: "Violent showers", 85: "Snow showers", 86: "Snow showers",
            95: "Thunderstorm", 96: "Thunderstorm, hail", 99: "Thunderstorm, hail"
        }
        return m[k] || "Unknown"
    }
    // Staggered 0..1 progress for item i of n, so things animate in one after another.
    function lp(i, n) {
        return Math.max(0, Math.min(1, progress * (1 + 0.08 * (n - 1)) - i * 0.08))
    }

    // Map a WMO weather code plus live numbers onto the scene targets
    function applyScene(c) {
        const k = c.weather_code
        let rain = 0, snow = 0, fog = 0, storm = 0
        if (k >= 51 && k <= 57) rain = 0.3
        else if (k === 61 || k === 66) rain = 0.5
        else if (k === 63 || k === 67) rain = 0.7
        else if (k === 65) rain = 0.95
        else if (k === 80) rain = 0.5
        else if (k === 81) rain = 0.75
        else if (k === 82) rain = 1
        if (k >= 71 && k <= 77) snow = (k === 75) ? 0.9 : 0.5
        if (k === 85 || k === 86) snow = 0.7
        if (k === 45 || k === 48) fog = 1
        if (k >= 95) { storm = 1; rain = 0.9 }
        if (rain > 0) rain = Math.max(rain, Math.min(1, c.precipitation / 6))

        let cover = c.cloud_cover / 100
        if (rain > 0 || snow > 0 || storm > 0) cover = Math.max(cover, 0.8)
        if (fog > 0) cover = Math.max(cover, 0.5)
        if (k === 3) cover = Math.max(cover, 0.9)

        tRain = rain
        tSnow = snow
        tFog = fog
        tStorm = storm
        tCloud = cover
        tNight = c.is_day === 1 ? 0 : 1
        tWind = c.wind_speed_10m
        tDir = c.wind_direction_10m
    }

    function load() {
        if (fetch.running) return
        err = ""
        fetch.running = true
    }

    function ingest(text) {
        let j
        try { j = JSON.parse(text) } catch (e) { err = "Can't reach the weather service"; return }
        if (!j || !j.current) { err = "Can't reach the weather service"; return }
        const c = j.current, d = j.daily, h = j.hourly

        const at = h.time.findIndex(t => t >= c.time.slice(0, 13) + ":00")
        const from = Math.max(0, at)
        const spark = h.temperature_2m.slice(from, from + 24)
        const lo = Math.min(...spark), hi = Math.max(...spark)
        const blocks = "\u2581\u2582\u2583\u2584\u2585\u2586\u2587\u2588"
        const line = spark.map(v => blocks[Math.min(7, Math.floor((v - lo) / Math.max(0.1, hi - lo) * 8))]).join("")

        const days = []
        for (let i = 1; i < d.time.length; i++) {
            days.push({
                name: dayName(d.time[i]),
                code: d.weather_code[i],
                hi: d.temperature_2m_max[i],
                lo: d.temperature_2m_min[i],
                pop: d.precipitation_probability_max[i] || 0
            })
        }

        wx = {
            temp: c.temperature_2m,
            feels: c.apparent_temperature,
            hum: Math.round(c.relative_humidity_2m),
            wind: c.wind_speed_10m,
            dir: c.wind_direction_10m,
            code: c.weather_code,
            sunrise: d.sunrise[0].slice(11, 16),
            sunset: d.sunset[0].slice(11, 16),
            pop: d.precipitation_probability_max[0] || 0,
            hi: d.temperature_2m_max[0],
            lo: d.temperature_2m_min[0],
            days: days,
            spark: line,
            sparkLo: lo,
            sparkHi: hi
        }
        applyScene(c)
        updatedAt = Date.now()
        err = ""
        if (shown) anim.restart()
    }

    Process {
        id: fetch
        command: ["curl", "-sS", "--max-time", "12", root.apiUrl]
        stdout: StdioCollector { onStreamFinished: root.ingest(text) }
    }

    // ── window ──
    LazyLoader {
        active: root.alive

        FloatingWindow {
            id: win
            visible: root.shown
            title: "Weather"
            implicitWidth: 560
            implicitHeight: 740
            color: "transparent"
            onVisibleChanged: if (!visible) { anim.stop(); root.shown = false }

            property int tick: 0

            Shortcut { sequence: "Escape"; onActivated: root.shown = false }
            Shortcut { sequence: "R"; onActivated: root.load() }
            Shortcut { sequence: "Ctrl+R"; onActivated: root.load() }
            Shortcut { sequence: "U"; onActivated: root.useF = !root.useF }

            Timer { interval: 50; repeat: true; running: win.visible; onTriggered: scene.requestPaint() }
            Timer { interval: 30000; repeat: true; running: win.visible; onTriggered: win.tick++ }

            // Glass body
            Rectangle {
                anchors.fill: parent
                color: Qt.alpha(Theme.panel, 0.82)

                // Specular sheen across the top
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
                        GradientStop { position: 0.25; color: Qt.rgba(1, 1, 1, 0.0) }
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 12

                    // ── Header ──
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Text {
                            text: "Weather"
                            color: Theme.fg
                            font.family: root.mono
                            font.pixelSize: 18
                            font.weight: Font.DemiBold
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "/ " + root.place
                            color: Theme.fgDim
                            font.family: root.mono
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                        Text {
                            visible: fetch.running
                            text: "updating…"
                            color: Theme.accent
                            font.family: root.mono
                            font.pixelSize: 10
                        }
                        Text {
                            text: Qt.formatDateTime(clock.date, "HH:mm  ·  ddd d MMM")
                            color: Theme.fgDim
                            font.family: root.mono
                            font.pixelSize: 11
                        }
                        IconBtn {
                            glyph: "\uf021"
                            onClicked: root.load()
                        }
                        IconBtn {
                            glyph: "\uf2c9"
                            tone: Theme.accentHi
                            onClicked: root.useF = !root.useF
                        }
                    }

                    Flickable { id: flick; Layout.fillWidth: true; Layout.fillHeight: true; clip: true; contentWidth: width; contentHeight: body.implicitHeight; boundsBehavior: Flickable.StopAtBounds
 ColumnLayout { id: body; width: flick.width; spacing: 12

                    // ── The character-built sky ──
                    Glass {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 250
                        radius: 20

                        Canvas {
                            id: scene
                            anchors.fill: parent
                            anchors.margins: 6

                            property real lastT: 0
                            property real t: 0
                            property real cloud: 0.2
                            property real rain: 0
                            property real snow: 0
                            property real fog: 0
                            property real storm: 0
                            property real night: 0
                            property real wind: 0
                            property real flash: 0
                            property real nextBolt: 4
                            property var drops: []
                            property var flakes: []
                            property var splashes: []
                            property var bolt: null
                            property var stars: []
                            property var cloudDefs: [
                                { x: 0.05, y: 0.10, s: 1.0, v: 1.0 },
                                { x: 0.55, y: 0.34, s: 0.8, v: 0.7 },
                                { x: 0.30, y: 0.55, s: 1.2, v: 1.3 },
                                { x: 0.80, y: 0.05, s: 0.9, v: 0.9 },
                                { x: 0.15, y: 0.75, s: 0.7, v: 0.6 },
                                { x: 0.65, y: 0.62, s: 1.1, v: 1.1 }
                            ]
                            property var lobes: [
                                { ox: 0, oy: 0, rx: 10, ry: 2.3 },
                                { ox: -8, oy: 0.9, rx: 7, ry: 1.7 },
                                { ox: 8.5, oy: 0.9, rx: 8, ry: 1.8 },
                                { ox: 1.5, oy: -1.1, rx: 6, ry: 1.6 }
                            ]

                            Component.onCompleted: {
                                const s = []
                                for (let i = 0; i < 50; i++)
                                    s.push({ x: Math.random(), y: Math.random(), p: Math.random() * 6.28 })
                                stars = s
                            }

                            onPaint: {
                                const ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)

                                const now = Date.now()
                                const dt = lastT === 0 ? 0.05 : Math.min(0.1, (now - lastT) / 1000)
                                lastT = now
                                t += dt

                                const cw = 7.8, chh = 15
                                const cols = Math.floor(width / cw)
                                const rows = Math.floor(height / chh)
                                if (cols < 10 || rows < 6) return

                                // Ease toward the live targets
                                const k = Math.min(1, dt * 1.6)
                                cloud += (root.tCloud - cloud) * k
                                rain += (root.tRain - rain) * k
                                snow += (root.tSnow - snow) * k
                                fog += (root.tFog - fog) * k
                                storm += (root.tStorm - storm) * k
                                night += (root.tNight - night) * k
                                wind += (root.tWind - wind) * k
                                flash = Math.max(0, flash - dt * 3)

                                // Wind blows toward the opposite of its "from" bearing
                                const wdir = -Math.sin(root.tDir * Math.PI / 180)
                                const slant = Math.max(0, Math.min(1.2, wind / 35)) * wdir

                                const N = cols * rows
                                const G = new Array(N).fill(" ")
                                const K = new Array(N).fill(0)
                                const A = new Array(N).fill(1)
                                function put(c, r, s, kd, a) {
                                    c = Math.round(c)
                                    r = Math.round(r)
                                    if (c < 0 || c >= cols || r < 0 || r >= rows || a < 0.04) return
                                    const i = r * cols + c
                                    G[i] = s
                                    K[i] = kd
                                    A[i] = Math.min(1, a)
                                }

                                // Stars
                                if (night > 0.05) {
                                    for (const s of stars) {
                                        const tw = 0.5 + 0.5 * Math.sin(t * 1.6 + s.p)
                                        put(s.x * cols, s.y * rows * 0.8,
                                            tw > 0.85 ? "*" : (tw > 0.55 ? "+" : "."),
                                            5, night * (1 - cloud * 0.85) * (0.25 + 0.75 * tw))
                                    }
                                }

                                // Sun and moon
                                const scx = cols * 0.78, scy = rows * 0.36
                                const R = Math.min(44, height * 0.2)
                                const bx = Math.ceil(R / cw) + 1, by = Math.ceil(R / chh) + 1
                                const dayA = (1 - night) * (1 - Math.min(1, cloud * 0.6 + rain * 0.3))
                                const nightA = night * (1 - cloud * 0.7)

                                if (dayA > 0.04) {
                                    for (let i = 0; i < 16; i++) {
                                        const ang = i * Math.PI / 8 + t * 0.25
                                        const len = 16 + 9 * Math.sin(t * 2.2 + i * 1.7)
                                        const q = ((ang % Math.PI) + Math.PI) % Math.PI
                                        const sym = ["-", "\\", "|", "/"][Math.round(q / (Math.PI / 4)) % 4]
                                        for (let d = R + 9; d < R + 9 + len; d += 9) {
                                            put(scx + Math.cos(ang) * d / cw, scy + Math.sin(ang) * d / chh,
                                                sym, 8, dayA * (0.95 - (d - R - 9) / len * 0.5))
                                        }
                                    }
                                    for (let dr = -by; dr <= by; dr++) {
                                        for (let dc = -bx; dc <= bx; dc++) {
                                            const px = dc * cw, py = dr * chh
                                            const d = Math.sqrt(px * px + py * py) / R
                                            if (d > 1) continue
                                            const w = d + 0.06 * Math.sin(t * 2 + dc * 0.9 + dr)
                                            put(scx + dc, scy + dr,
                                                w < 0.35 ? "@" : (w < 0.65 ? "O" : (w < 0.88 ? "o" : "*")),
                                                1, dayA)
                                        }
                                    }
                                }
                                if (nightA > 0.04) {
                                    for (let dr = -by; dr <= by; dr++) {
                                        for (let dc = -bx; dc <= bx; dc++) {
                                            const px = dc * cw, py = dr * chh
                                            const d1 = Math.sqrt(px * px + py * py) / (R * 0.85)
                                            const qx = px - R * 0.5, qy = py + R * 0.15
                                            const d2 = Math.sqrt(qx * qx + qy * qy) / (R * 0.78)
                                            if (d1 <= 1 && d2 > 1)
                                                put(scx + dc, scy + dr, d1 < 0.6 ? "@" : "O", 1, nightA)
                                        }
                                    }
                                }

                                // Drifting clouds, count follows cloud cover
                                const span = cols + 50
                                const drift = (1.2 + wind * 0.12) * (wdir >= 0 ? 1 : -1)
                                for (let i = 0; i < cloudDefs.length; i++) {
                                    const cd = cloudDefs[i]
                                    const vis = Math.max(0, Math.min(1, cloud * 6 - i))
                                    if (vis < 0.04) continue
                                    const ccx = ((cd.x * span + t * cd.v * drift) % span + span) % span - 25
                                    const ccy = 1.5 + cd.y * rows * 0.55
                                    const ca = Math.min(1, vis * (0.55 + 0.35 * cloud) + flash * 0.4)
                                    const s = cd.s
                                    for (let r = Math.floor(ccy - 3 * s); r <= Math.ceil(ccy + 2.2 * s); r++) {
                                        for (let c = Math.floor(ccx - 18 * s); c <= Math.ceil(ccx + 18 * s); c++) {
                                            let best = 9
                                            for (const lb of lobes) {
                                                const ex = (c - ccx - lb.ox * s) / (lb.rx * s)
                                                const ey = (r - ccy - lb.oy * s) / (lb.ry * s)
                                                best = Math.min(best, ex * ex + ey * ey)
                                            }
                                            if (best >= 1) continue
                                            if (r > ccy + 1.2 * s) continue
                                            put(c, r, best < 0.3 ? "#" : (best < 0.62 ? "%" : (best < 0.85 ? "o" : "~")), 2, ca)
                                        }
                                    }
                                }

                                // Storm deck
                                const deck = Math.max(0, (cloud - 0.6) / 0.4)
                                const deckRows = Math.round(1 + deck * 2 + rain * 1.5)
                                if (deck > 0.04) {
                                    for (let r = 0; r < deckRows; r++) {
                                        for (let c = 0; c < cols; c++) {
                                            const n = Math.sin(c * 0.3 + t * 0.4 + r * 2) + Math.sin(c * 0.09 - t * 0.2 + r)
                                            if (r === deckRows - 1 && n < -0.2) continue
                                            put(c, r, n > 0.7 ? "%" : (n > -0.3 ? "o" : "~"), 2,
                                                Math.min(1, deck * 0.8 + flash * 0.4))
                                        }
                                    }
                                }
                                const deckBottom = deck > 0.04 ? deckRows : 2

                                // Fog
                                if (fog > 0.04) {
                                    for (let r = Math.floor(rows * 0.3); r < rows; r++) {
                                        for (let c = 0; c < cols; c++) {
                                            const n = Math.sin(c * 0.28 + t * 0.5 + r * 1.9) + Math.sin(c * 0.11 - t * 0.32 + r * 0.8)
                                            if (n > 0.1) put(c, r, n > 1 ? "=" : (n > 0.5 ? "-" : "_"), 7, fog * (0.25 + 0.25 * r / rows))
                                        }
                                    }
                                }

                                // Rain
                                const rtgt = Math.round(rain * cols * 1.1)
                                const rspd = 9 + rain * 9
                                while (drops.length < rtgt)
                                    drops.push({ x: Math.random() * cols,
                                                 y: deckBottom + Math.random() * Math.max(1, rows - deckBottom),
                                                 v: rspd * (0.7 + Math.random() * 0.6) })
                                if (drops.length > rtgt) drops.length = rtgt
                                if (rain > 0.04) {
                                    for (let c = 0; c < cols; c++) put(c, rows - 1, "_", 7, 0.25 * rain)
                                }
                                for (const dp of drops) {
                                    dp.y += dp.v * dt
                                    dp.x = ((dp.x + slant * dp.v * dt) % cols + cols) % cols
                                    if (dp.y >= rows - 1) {
                                        if (splashes.length < 80) splashes.push({ x: dp.x, life: 0.3 })
                                        dp.y = deckBottom + Math.random() * 1.5
                                        dp.x = Math.random() * cols
                                        continue
                                    }
                                    const sym = rain < 0.4 ? "'" : (Math.abs(slant) < 0.15 ? "|" : (slant > 0 ? "\\" : "/"))
                                    put(dp.x, dp.y, sym, 3, 0.5 + 0.5 * rain)
                                    if (rain > 0.6) put(dp.x - slant, dp.y - 1, sym, 3, 0.3)
                                }
                                for (let i = splashes.length - 1; i >= 0; i--) {
                                    const sp = splashes[i]
                                    sp.life -= dt
                                    if (sp.life <= 0) { splashes.splice(i, 1); continue }
                                    put(sp.x, rows - 1, sp.life > 0.15 ? "o" : ".", 3, sp.life / 0.3)
                                }

                                // Snow
                                const stgt = Math.round(snow * cols * 0.7)
                                while (flakes.length < stgt)
                                    flakes.push({ x: Math.random() * cols,
                                                  y: deckBottom + Math.random() * Math.max(1, rows - deckBottom),
                                                  v: 1.2 + Math.random() * 1.8, p: Math.random() * 6.28 })
                                if (flakes.length > stgt) flakes.length = stgt
                                for (const f of flakes) {
                                    f.y += f.v * dt
                                    f.x = ((f.x + (Math.sin(t * 1.4 + f.p) * 1.6 + slant * 3) * dt) % cols + cols) % cols
                                    if (f.y >= rows) { f.y = deckBottom; f.x = Math.random() * cols }
                                    put(f.x, f.y, f.v > 2.4 ? "*" : (f.v > 1.8 ? "+" : "."), 4, 0.9)
                                }

                                // Lightning
                                if (storm > 0.5 && t > nextBolt) {
                                    const pts = []
                                    let lx = cols * (0.15 + Math.random() * 0.7)
                                    for (let r = deckBottom; r < rows - 1; r++) {
                                        const step = Math.random() < 0.5 ? -1 : 1
                                        pts.push({ x: lx, y: r, s: step < 0 ? "/" : "\\" })
                                        lx += step
                                    }
                                    bolt = { pts: pts, life: 0.35 }
                                    flash = 1
                                    nextBolt = t + 2.5 + Math.random() * 5
                                }
                                if (bolt) {
                                    bolt.life -= dt
                                    if (bolt.life <= 0) bolt = null
                                    else for (const p of bolt.pts) put(p.x, p.y, p.s, 6, bolt.life / 0.35 + 0.3)
                                }

                                // Draw the grid
                                ctx.font = "13px " + root.mono
                                ctx.textBaseline = "top"
                                const pal = [null, root.hex(Theme.accentHi), root.hex(Theme.fgDim), root.hex(Theme.accent),
                                             root.hex(Theme.fg), root.hex(Theme.fgDim), root.hex(Theme.accentHi),
                                             root.hex(Theme.fgDim), root.hex(Theme.accent)]
                                const ox = (width - cols * cw) / 2
                                let lastK = -1
                                for (let i = 0; i < N; i++) {
                                    if (G[i] === " ") continue
                                    const kd = K[i]
                                    if (kd !== lastK) { ctx.fillStyle = pal[kd]; lastK = kd }
                                    ctx.globalAlpha = A[i]
                                    ctx.fillText(G[i], ox + (i % cols) * cw, Math.floor(i / cols) * chh)
                                }
                                ctx.globalAlpha = 1
                            }
                        }
                    }

                    // ── Hero: big temperature on the left, high/low on the right ──
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            Text {
                                text: root.wx ? root.cond(root.wx.code).toUpperCase()
                                      : (root.err !== "" ? root.err : "LOADING…")
                                color: root.err !== "" && !root.wx ? Theme.bad : Theme.fgDim
                                font.family: root.mono
                                font.pixelSize: 11
                                font.letterSpacing: 2.5
                            }
                            Text {
                                textFormat: Text.RichText
                                font.family: root.mono
                                opacity: root.wx ? root.lp(0, 1) : 1
                                text: root.wx ? root.tempHtml(root.wx.temp, 80, 26, Theme.accentHi)
                                      : root.sp("--", 80, Theme.accentHi, 600)
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.useF = !root.useF
                                }
                            }
                        }

                        ColumnLayout {
                            visible: root.wx !== null
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            spacing: 10
                            StatBlock { label: "HIGH"; value: root.wx ? root.conv(root.wx.hi) + "°" : "–" }
                            StatBlock { label: "LOW"; value: root.wx ? root.conv(root.wx.lo) + "°" : "–" }
                            StatBlock { label: "FEELS LIKE"; value: root.wx ? root.conv(root.wx.feels) + "°" : "–" }
                        }
                    }

                    // ── Stat chips ──
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 3
                        rowSpacing: 8
                        columnSpacing: 8
                        visible: root.wx !== null

                        Repeater {
                            model: root.wx ? [
                                { k: "HUMIDITY", h: root.numUnit(root.wx.hum, "%", 20, 10, Theme.fg) },
                                { k: "WIND " + root.compass(root.wx.dir), h: root.numUnit(Math.round(root.wx.wind), "km/h", 20, 10, Theme.fg) },
                                { k: "RAIN CHANCE", h: root.numUnit(root.wx.pop, "%", 20, 10, Theme.fg) },
                                { k: "SUNRISE", h: root.numUnit(root.wx.sunrise, "", 20, 10, Theme.fg) },
                                { k: "SUNSET", h: root.numUnit(root.wx.sunset, "", 20, 10, Theme.fg) },
                                { k: "UPDATED", h: root.numUnit(root.agoMs(root.updatedAt, win.tick), "", 14, 10, Theme.fg) }
                            ] : []

                            Glass {
                                id: chip
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.preferredHeight: 58
                                radius: 16
                                opacity: root.lp(index, 6)

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 2
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: chip.modelData.k
                                        color: Theme.fgDim
                                        font.family: root.mono
                                        font.pixelSize: 8
                                        font.letterSpacing: 1.2
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        textFormat: Text.RichText
                                        font.family: root.mono
                                        text: chip.modelData.h
                                    }
                                }
                            }
                        }
                    }

                    // ── 24h sparkline, made of block characters ──
                    Glass {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 76
                        radius: 18
                        visible: root.wx !== null

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "NEXT 24 HOURS"
                                    color: Theme.fgDim
                                    font.family: root.mono
                                    font.pixelSize: 9
                                    font.letterSpacing: 1.4
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    textFormat: Text.RichText
                                    font.family: root.mono
                                    text: root.wx
                                        ? root.sp(root.conv(root.wx.sparkLo), 12, Theme.fg, 600) + root.sp("&deg; &ndash; ", 9, Theme.fgDim, 400)
                                          + root.sp(root.conv(root.wx.sparkHi), 12, Theme.fg, 600) + root.sp("&deg;", 9, Theme.fgDim, 400)
                                        : ""
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: root.wx ? root.wx.spark : ""
                                color: Theme.accent
                                font.family: root.mono
                                font.pixelSize: 24
                                font.letterSpacing: 3
                                fontSizeMode: Text.Fit
                                minimumPixelSize: 10
                                opacity: root.progress
                            }
                        }
                    }

                    // ── 5-day strip ──
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: root.wx !== null

                        Repeater {
                            model: root.wx ? root.wx.days : []

                            Glass {
                                id: dayCard
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.preferredHeight: 104
                                radius: 18
                                opacity: root.lp(index, 5)

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 3

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: dayCard.modelData.name.toUpperCase()
                                        color: Theme.fg
                                        font.family: root.mono
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        font.letterSpacing: 1.2
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        text: root.cond(dayCard.modelData.code)
                                        color: Theme.fgDim
                                        font.family: root.mono
                                        font.pixelSize: 9
                                        elide: Text.ElideRight
                                    }
                                    Item { Layout.fillHeight: true }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        textFormat: Text.RichText
                                        font.family: root.mono
                                        text: root.hiLo(dayCard.modelData.hi, dayCard.modelData.lo)
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: dayCard.modelData.pop + "% rain"
                                        color: dayCard.modelData.pop >= 40 ? Theme.accentHi : Theme.fgDim
                                        font.family: root.mono
                                        font.pixelSize: 9
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Open-Meteo  ·  click the temperature or press U for °F/°C"
                        color: Theme.fgDim
                        font.family: root.mono
                        font.pixelSize: 9
                    }
}
}
                }
            }
        }
    }
}
