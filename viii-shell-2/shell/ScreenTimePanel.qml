// File: ~/viii-shell-2/shell/ScreenTime.qml
// Screen Time, glass style. Two pages, no scrolling:
//   page 0 "Screen Time": big number (left), stacked app bar, app grid, week waveform
//   page 1 "Activity":    git-style heatmap + streak stats
// Switch pages with the calendar button in the header, or press A.

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool shown: false
    property bool alive: false
    readonly property int closeMs: 0
    readonly property string mono: "JetBrainsMono Nerd Font"

    onShownChanged: {
        if (shown) {
            unload.stop()
            page = 0
            alive = true
        } else {
            unload.restart()
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

    // --- Data ---------------------------------------------------------------
    property int page: 0
    property int range: 1
    property int offset: 0
    property var days: []
    property var apps: []
    property real progress: 0
    property int hoverIdx: -1

    // Heatmap data (built in buildHeat)
    readonly property int heatWeeks: 17          // columns in the heatmap
    property var heat: []                        // [{ label, days: [{ date, secs, future, ago }] }]
    property var heatStats: ({ active: 0, total: 0, current: 0, longest: 0, bestSecs: 0, bestDate: "" })
    property string heatTip: "Hover a day for details"

    // Daily goal (6h). Change to taste.
    readonly property int goalDay: 10 * 3600
    readonly property int goal: range === 7 ? goalDay * 7 : goalDay
    readonly property real goalFrac: totalSecs / goal

    property int totalSecs: {
        if (days.length === 0) return 0
        if (range === 1) return days[Math.max(0, days.length - 1 - offset)].secs
        return days.reduce((s, x) => s + x.secs, 0)
    }
    property int maxDay: Math.max(1, ...days.map(x => x.secs))
    property int denom: Math.max(1, totalSecs)
    property int avgDay: days.length > 0 ? Math.round(days.reduce((s, x) => s + x.secs, 0) / days.length) : 0
    property int goalHit: days.filter(x => x.secs >= goalDay).length
    property int deltaPct: {
        if (range === 7 || avgDay <= 0) return 0
        return Math.round((totalSecs - avgDay) / avgDay * 100)
    }
    readonly property bool canOlder: range === 1 && days.length > 0 && offset < days.length - 1
    readonly property bool canNewer: range === 1 && offset > 0
    readonly property var palette: Theme.chart
    readonly property var views: [
        { label: "Day", r: 1 },
        { label: "Week", r: 7 }
    ]

    // 3700 -> "1h 01m". Minutes are padded to 2 digits when hours show, so the
    // text doesn't change width when minutes go from 9 to 10.
    function fmt(s) {
        const h = Math.floor(s / 3600)
        const m = Math.floor((s % 3600) / 60)
        if (h > 0) return h + "h " + ("0" + m).slice(-2) + "m"
        if (m > 0) return m + "m"
        return s + "s"
    }
    // Same as fmt, but for COUNTING UP: `f` is the final value. The layout (hours+minutes,
    // minutes only, or seconds only) is chosen from `f`, so the unit never changes mid-count.
    //   fmtTo(1500, 7380)  ->  "0h 25m"      (7380 s = 2h 03m, so it counts in hours + minutes)
    function fmtTo(s, f) {
        const h = Math.floor(s / 3600)
        const m = Math.floor((s % 3600) / 60)
        if (f >= 3600) return h + "h " + ("0" + m).slice(-2) + "m"
        if (f >= 60) return m + "m"
        return s + "s"
    }
    function hex(c) {
        const h = v => ("0" + Math.round(v * 255).toString(16)).slice(-2)
        return "#" + h(c.r) + h(c.g) + h(c.b)
    }
    // Big digits, small units, shared baseline.
    function durHtml(s, f, ns, us, nc, uc) {
        const num = v => '<span style="font-size:' + ns + 'px; font-weight:600; color:' + hex(nc) + ';">' + v + '</span>'
        const unit = v => '<span style="font-size:' + us + 'px; color:' + hex(uc) + ';">' + v + '</span>'
        // Pads on the left with blank slots until the value is as long as the final one.
        // A space is exactly as wide as a digit in a monospace font, so nothing shifts.
        const slots = (v, finalV) => {
            let blanks = ""
            for (let i = String(v).length; i < String(finalV).length; i++) blanks += "&nbsp;"
            return blanks + v
        }
        const h = Math.floor(s / 3600)
        const m = Math.floor((s % 3600) / 60)
        const fh = Math.floor(f / 3600)
        const fm = Math.floor((f % 3600) / 60)
        if (fh > 0) return num(slots(h, fh)) + unit("h") + "&nbsp;" + num(("0" + m).slice(-2)) + unit("m")
        if (fm > 0) return num(slots(m, fm)) + unit("m")
        return num(slots(s, f)) + unit("s")
    }
    function dayName(iso) {
        return ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][new Date(iso + "T00:00:00").getDay()]
    }
    function pretty(n) {
        const p = n.split(".")
        const last = p[p.length - 1]
        return last.charAt(0).toUpperCase() + last.slice(1)
    }
    function viewTitle() {
        if (range === 7) return "LAST 7 DAYS"
        if (offset === 0) return "TODAY"
        if (offset === 1) return "YESTERDAY"
        const i = days.length - 1 - offset
        if (i >= 0 && days[i]) return days[i].label.toUpperCase() + " · " + offset + " DAYS AGO"
        return offset + " DAYS AGO"
    }
    function isoDate(dt) {
        return dt.getFullYear() + "-" + ("0" + (dt.getMonth() + 1)).slice(-2) + "-" + ("0" + dt.getDate()).slice(-2)
    }
    // How bright a heatmap cell is, relative to the daily goal.
    function heatOpacity(s) {
        if (s <= 0) return 0
        const r = s / goalDay
        if (r < 0.25) return 0.3
        if (r < 0.5) return 0.5
        if (r < 0.9) return 0.75
        return 1
    }
    // Turn { "2026-10-12": secs, ... } into week columns (Sunday on top) plus streak stats.
    function buildHeat(h) {
        const today = new Date()
        today.setHours(0, 0, 0, 0)
        const start = new Date(today)
        start.setDate(today.getDate() - today.getDay() - (heatWeeks - 1) * 7)

        const weeks = []
        let prevMonth = -1
        let active = 0, total = 0, run = 0, longest = 0, bestSecs = 0, bestDate = ""

        for (let w = 0; w < heatWeeks; w++) {
            const wd = []
            let label = ""
            for (let d = 0; d < 7; d++) {
                const dt = new Date(start)
                dt.setDate(start.getDate() + w * 7 + d)
                const iso = isoDate(dt)
                const future = dt > today
                const secs = future ? 0 : (h[iso] || 0)

                if (d === 0 && dt.getMonth() !== prevMonth) {
                    label = Qt.formatDate(dt, "MMM")
                    prevMonth = dt.getMonth()
                }
                if (!future) {
                    total++
                    if (secs > 0) {
                        active++
                        run++
                        if (run > longest) longest = run
                    } else {
                        run = 0
                    }
                    if (secs > bestSecs) { bestSecs = secs; bestDate = iso }
                }
                wd.push({ date: iso, secs: secs, future: future, ago: Math.round((today - dt) / 86400000) })
            }
            weeks.push({ label: label, days: wd })
        }

        // Current streak: walk back from today (an empty today doesn't break it yet)
        let current = 0
        for (let i = 0; i < heatWeeks * 7; i++) {
            const dt = new Date(today)
            dt.setDate(today.getDate() - i)
            const s = h[isoDate(dt)] || 0
            if (s > 0) current++
            else if (i > 0) break
        }

        heat = weeks
        heatStats = { active: active, total: total, current: current, longest: longest, bestSecs: bestSecs, bestDate: bestDate }
    }
    function parse(text) {
        const d = [], a = [], h = {}
        for (const line of text.split("\n")) {
            const p = line.split("\t")
            if (p.length < 3) continue
            if (p[0] === "DAY") d.push({ label: dayName(p[1]), secs: parseInt(p[2]) })
            else if (p[0] === "APP") a.push({ name: p[1], secs: parseInt(p[2]) })
            else if (p[0] === "HIST") h[p[1]] = parseInt(p[2])
        }
        days = d
        apps = a
        buildHeat(h)
    }
    // Staggered 0..1 progress for item i of n, so things animate in one after another.
    function lp(i, n) {
        return Math.max(0, Math.min(1, progress * (1 + 0.08 * (n - 1)) - i * 0.08))
    }
    function refresh() {
        anim.stop()
        progress = 0
        report.running = true
    }
    function setView(r, o) {
        range = r
        offset = o
        if (root.shown) refresh()
    }
    // d = +1 goes one day older, d = -1 one day newer
    function stepDay(d) {
        if (range !== 1) return
        const n = offset + d
        if (n < 0 || n > days.length - 1) return
        setView(1, n)
    }

    IpcHandler {
        target: "screentime"
        function toggle(): void {
            root.shown = !root.shown
            if (root.shown) root.refresh()
            else anim.stop()
        }
    }

    NumberAnimation {
        id: anim
        target: root
        property: "progress"
        from: 0
        to: 1
        duration: 1300
        easing.type: Easing.OutCubic
    }

    Process {
        id: report
        command: [Quickshell.env("HOME") + "/.local/bin/screentime-report", String(root.range), String(root.offset), String(root.heatWeeks)]
        stdout: StdioCollector {
            onStreamFinished: {
                root.parse(text)
                if (root.shown) anim.restart()
            }
        }
    }

    // --- The window -----------------------------------------------------------
    LazyLoader {
        active: root.alive

        FloatingWindow {
            id: win
            visible: root.shown
            title: "Screen Time"
            implicitWidth: 560
            implicitHeight: 740
            color: "transparent"
            onVisibleChanged: if (!visible) { anim.stop(); root.shown = false }

            Shortcut { sequence: "Escape"; onActivated: root.shown = false }
            Shortcut { sequence: "Left"; onActivated: root.stepDay(1) }
            Shortcut { sequence: "Right"; onActivated: root.stepDay(-1) }
            Shortcut { sequence: "R"; onActivated: root.refresh() }
            Shortcut { sequence: "A"; onActivated: root.page = root.page === 0 ? 1 : 0 }

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
                            text: root.page === 0 ? "Screen Time" : "Activity"
                            color: Theme.fg
                            font.family: root.mono
                            font.pixelSize: 18
                            font.weight: Font.DemiBold
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: Qt.formatDateTime(clock.date, "HH:mm  ·  ddd d MMM")
                            color: Theme.fgDim
                            font.family: root.mono
                            font.pixelSize: 11
                        }
                        IconBtn {
                            glyph: "\uf021"
                            onClicked: root.refresh()
                        }
                        IconBtn {
                            glyph: root.page === 0 ? "\uf073" : "\uf053"
                            tone: Theme.accentHi
                            onClicked: root.page = root.page === 0 ? 1 : 0
                        }
                    }

                    StackLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        currentIndex: root.page

                        // ════════════ PAGE 0: OVERVIEW ════════════
                        ColumnLayout {
                            spacing: 12

                            // Day / Week switch + day arrows
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Glass {
                                    Layout.preferredWidth: 150
                                    Layout.preferredHeight: 34
                                    radius: 17

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 3
                                        spacing: 3

                                        Repeater {
                                            model: root.views

                                            Item {
                                                id: seg
                                                required property var modelData
                                                readonly property bool active: root.range === modelData.r
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true

                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: 14
                                                    color: seg.active
                                                        ? Qt.alpha(Theme.accent, 0.22)
                                                        : (segHit.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                                                    border.width: seg.active ? 1 : 0
                                                    border.color: Theme.accent
                                                    Behavior on color { ColorAnimation { duration: 120 } }
                                                }
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: seg.modelData.label
                                                    color: seg.active ? Theme.accentHi : Theme.fgDim
                                                    font.family: root.mono
                                                    font.pixelSize: 11
                                                    font.weight: seg.active ? Font.DemiBold : Font.Normal
                                                }
                                                MouseArea {
                                                    id: segHit
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: if (root.range !== seg.modelData.r) root.setView(seg.modelData.r, 0)
                                                }
                                            }
                                        }
                                    }
                                }
                                Item { Layout.fillWidth: true }
                                IconBtn {
                                    glyph: "\uf053"
                                    opacity: root.canOlder ? 1 : 0.3
                                    onClicked: root.stepDay(1)
                                }
                                IconBtn {
                                    glyph: "\uf054"
                                    opacity: root.canNewer ? 1 : 0.3
                                    onClicked: root.stepDay(-1)
                                }
                            }

                            // Hero: big number on the left, small stats on the right
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    Text {
                                        text: root.viewTitle()
                                        color: Theme.fgDim
                                        font.family: root.mono
                                        font.pixelSize: 11
                                        font.letterSpacing: 2.5
                                    }
                                    Text {
                                        textFormat: Text.RichText
                                        font.family: root.mono
                                        text: root.durHtml(Math.round(root.totalSecs * root.progress), root.totalSecs, 80, 26, Theme.accentHi, Theme.fgDim)
                                    }
                                    Text {
                                        visible: root.range === 1 && root.avgDay > 0 && root.deltaPct !== 0
                                        text: (root.deltaPct > 0 ? "▲ " : "▼ ") + Math.abs(root.deltaPct) + "% vs your daily average"
                                        color: root.deltaPct > 0 ? Theme.accentHi : Theme.fgDim
                                        font.family: root.mono
                                        font.pixelSize: 11
                                    }
                                }

                                ColumnLayout {
                                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                    spacing: 10
                                    StatBlock { label: "PEAK DAY"; value: root.maxDay > 1 ? root.fmt(root.maxDay) : "–" }
                                    StatBlock { label: "DAILY AVG"; value: root.fmt(root.avgDay) }
                                    StatBlock { label: "GOAL DAYS"; value: root.goalHit + " / " + root.days.length }
                                }
                            }

                            // Goal progress: slim bar + text
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Rectangle {
                                    id: goalTrack
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 6
                                    radius: 3
                                    color: Qt.alpha(Theme.surfaceHi, 0.7)

                                    Rectangle {
                                        width: parent.width * Math.min(1, root.goalFrac * root.progress)
                                        height: parent.height
                                        radius: 3
                                        color: Theme.accent
                                    }
                                }
                                Text {
                                    text: Math.round(root.goalFrac * 100) + "% of " + root.fmt(root.goal) + " goal"
                                    color: Theme.fgDim
                                    font.family: root.mono
                                    font.pixelSize: 10
                                }
                            }

                            // Stacked app bar (thick): top 6 apps
                            // Stacked app bar: every app, tiny ones get a minimum sliver
                            // Stacked app bar: every app fits inside the bar, tiny ones keep a minimum sliver
                            Rectangle {
                                id: shareHost
                                Layout.fillWidth: true
                                Layout.preferredHeight: 28
                                radius: height / 2
                                color: Qt.alpha(Theme.surfaceHi, 0.5)
                                visible: root.apps.length > 0
                                clip: true
                            
                                readonly property real gap: 2
                                readonly property real minW: 4
                                readonly property int n: root.apps.length
                            
                                // Space left after the gaps and every app's guaranteed minimum width.
                                // Only this leftover is shared out by time, so the total can never exceed the bar.
                                readonly property real spare: Math.max(0, width - Math.max(0, n - 1) * gap - n * minW)
                            
                                // Use whichever is larger, so the shares never add up to more than 100%
                                readonly property real shareTotal: Math.max(root.denom, root.apps.reduce((s, a) => s + a.secs, 0))
                            
                                Row {
                                    anchors.fill: parent
                                    spacing: shareHost.gap
                            
                                    Repeater {
                                        model: root.apps
                            
                                        Rectangle {
                                            required property var modelData
                                            required property int index
                                            height: shareHost.height
                                            radius: height / 2
                                            // minimum + proportional share of the spare space
                                            width: shareHost.minW + shareHost.spare * (modelData.secs / shareHost.shareTotal) * root.progress
                                            color: root.palette[index % root.palette.length]
                                            opacity: index < root.palette.length ? 1 : 0.6
                                        }
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: root.apps.length === 0
                                text: "No activity recorded for this period.\nThe tracker logs active applications once a minute."
                                color: Theme.fgDim
                                font.family: root.mono
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }

                            // App grid: each name takes its color from the bar above
                            // App grid: 2 rows, flowing left to right, scrolls horizontally.
                            // Each name takes its color from the bar above.
                            Item {
                                id: appArea
                                Layout.fillWidth: true
                                Layout.preferredHeight: 2 * 46 + 8 + (appFlick.contentWidth > appFlick.width + 1 ? 12 : 0)
                                visible: root.apps.length > 0
                            
                                // Each cell is half the visible width, so 2 columns show at a time
                                readonly property real cellW: (appFlick.width - 8) / 2
                            
                                Flickable {
                                    id: appFlick
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    height: 2 * 46 + 8
                                    clip: true
                                    contentWidth: appGrid.width
                                    contentHeight: height
                                    flickableDirection: Flickable.HorizontalFlick
                                    boundsBehavior: Flickable.StopAtBounds
                            
                                    // Mouse wheel / touchpad scrolls sideways (Flickable only does vertical by default)
                                    WheelHandler {
                                        onWheel: event => {
                                            const d = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
                                            const maxX = Math.max(0, appFlick.contentWidth - appFlick.width)
                                            appFlick.contentX = Math.max(0, Math.min(maxX, appFlick.contentX - d))
                                        }
                                    }
                            
                                    Grid {
                                        id: appGrid
                                        rows: 2
                                        flow: Grid.TopToBottom        // fill down the column first, then move right
                                        rowSpacing: 8
                                        columnSpacing: 8
                                        // columns needed = ceil(apps / 2); width = columns * cell + gaps
                                        width: Math.ceil(root.apps.length / 2) * appArea.cellW
                                               + Math.max(0, Math.ceil(root.apps.length / 2) - 1) * columnSpacing
                            
                                        Repeater {
                                            model: root.apps
                            
                                            Glass {
                                                id: cell
                                                required property var modelData
                                                required property int index
                                                readonly property color tone: root.palette[index % root.palette.length]
                                                width: appArea.cellW
                                                height: 46
                                                radius: 14
                                                // Cap the stagger at 6 so far-away cells don't animate in late
                                                opacity: root.lp(Math.min(index, 5), 6)
                            
                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 14
                                                    anchors.rightMargin: 14
                                                    spacing: 8
                            
                                                    Rectangle {
                                                        Layout.preferredWidth: 8
                                                        Layout.preferredHeight: 8
                                                        radius: 4
                                                        color: cell.tone
                                                    }
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: root.pretty(cell.modelData.name)
                                                        color: cell.tone
                                                        font.family: root.mono
                                                        font.pixelSize: 13
                                                        font.weight: Font.DemiBold
                                                        elide: Text.ElideRight
                                                    }
                                                    ColumnLayout {
                                                        spacing: 0
                                                        Text {
                                                            Layout.alignment: Qt.AlignRight
                                                            text: root.fmtTo(Math.round(cell.modelData.secs * root.progress), cell.modelData.secs)
                                                            color: Theme.fg
                                                            font.family: root.mono
                                                            font.pixelSize: 12
                                                        }
                                                        Text {
                                                            Layout.alignment: Qt.AlignRight
                                                            text: Math.round(cell.modelData.secs / root.denom * 100 * root.progress) + "%"
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
                            
                                // Scroll bar for the app grid: drag the thumb, or click the track to jump.
                                // The Item is 12px tall (easy to hit); the visible bar inside stays thin.
                                // 12px is also exactly the extra height appArea reserves when scrollable.
                                Item {
                                    id: scrollBar
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 12
                                    visible: appFlick.contentWidth > appFlick.width + 1
                                
                                    // How far the content can scroll, and how big / how far the thumb moves
                                    readonly property real maxX: Math.max(1, appFlick.contentWidth - appFlick.width)
                                    readonly property real thumbW: Math.max(24, width * appFlick.width / Math.max(1, appFlick.contentWidth))
                                    readonly property real travel: Math.max(1, width - thumbW)
                                
                                    // Track
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        height: 4
                                        radius: 2
                                        color: Qt.alpha(Theme.surfaceHi, 0.5)
                                    }
                                
                                    // Thumb: its position is driven by contentX, so trackpad scrolling still moves it
                                    Rectangle {
                                        id: thumb
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: scrollBar.thumbW
                                        height: (barMouse.pressed || barMouse.containsMouse) ? 6 : 4
                                        radius: height / 2
                                        color: barMouse.pressed ? Theme.accentHi : Theme.accent
                                        x: scrollBar.travel * appFlick.contentX / scrollBar.maxX
                                        Behavior on height { NumberAnimation { duration: 100 } }
                                    }
                                
                                    MouseArea {
                                        id: barMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                
                                        // Where inside the thumb you grabbed it, so it doesn't jump under the cursor
                                        property real grabOffset: 0
                                
                                        // Turn a mouse x position into a contentX (clamped between 0 and the max)
                                        function scrollTo(mx) {
                                            const frac = Math.max(0, Math.min(1, (mx - grabOffset) / scrollBar.travel))
                                            appFlick.contentX = frac * scrollBar.maxX
                                        }
                                
                                        onPressed: mouse => {
                                            const onThumb = mouse.x >= thumb.x && mouse.x <= thumb.x + thumb.width
                                            // On the thumb: keep your grab point. On the empty track: center the thumb there.
                                            grabOffset = onThumb ? mouse.x - thumb.x : scrollBar.thumbW / 2
                                            scrollTo(mouse.x)
                                        }
                                        onPositionChanged: mouse => { if (pressed) scrollTo(mouse.x) }
                                    }
                                }
                            }

                            // Week waveform: one smooth wave flowing through every day.
                            // Click a point to open that day.
                            Glass {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: 150
                                radius: 20

                                Item {
                                    id: wave
                                    anchors.fill: parent
                                    anchors.margins: 14

                                    readonly property int n: root.days.length
                                    readonly property real padX: 16
                                    readonly property real topY: 22               // room for the value label
                                    readonly property real baseY: height - 24     // room for the day labels

                                    // x / y of day i (y rises with progress, so the wave "grows" in)
                                    function px(i) { return n < 2 ? width / 2 : padX + i * (width - 2 * padX) / (n - 1) }
                                    function py(i) {
                                        return baseY - (root.days[i].secs / root.maxDay) * (baseY - topY) * root.progress
                                    }

                                    // SVG path: cubic curves whose control points sit halfway between
                                    // two days at each day's height. That makes every day a smooth
                                    // crest/trough and the wave flows from one day into the next.
                                    readonly property string linePath: {
                                        if (n === 0) return ""
                                        let d = "M" + px(0) + "," + py(0)
                                        for (let i = 1; i < n; i++) {
                                            const mx = (px(i - 1) + px(i)) / 2
                                            d += " C" + mx + "," + py(i - 1) + " " + mx + "," + py(i) + " " + px(i) + "," + py(i)
                                        }
                                        return d
                                    }
                                    // Same curve, closed down to the baseline for the soft fill.
                                    readonly property string areaPath: n === 0 ? ""
                                        : linePath + " L" + px(n - 1) + "," + baseY + " L" + px(0) + "," + baseY + " Z"

                                    Shape {
                                        anchors.fill: parent
                                        preferredRendererType: Shape.CurveRenderer

                                        ShapePath {
                                            fillColor: Qt.alpha(Theme.accent, 0.16)
                                            strokeWidth: -1                      // no outline, fill only
                                            PathSvg { path: wave.areaPath }
                                        }
                                        ShapePath {
                                            fillColor: "transparent"
                                            strokeColor: Theme.accent
                                            strokeWidth: 2.5
                                            capStyle: ShapePath.RoundCap
                                            joinStyle: ShapePath.RoundJoin
                                            PathSvg { path: wave.linePath }
                                        }
                                    }

                                    // One column per day: dot, value label, day name, mouse area
                                    Repeater {
                                        model: root.days

                                        Item {
                                            id: dayCol
                                            required property var modelData
                                            required property int index
                                            readonly property bool selectedDay: root.range === 1
                                                ? index === root.days.length - 1 - root.offset
                                                : index === root.days.length - 1
                                            readonly property bool focused: selectedDay || root.hoverIdx === index

                                            width: wave.width / Math.max(1, root.days.length)
                                            height: wave.height
                                            x: wave.px(index) - width / 2

                                            // dot on the wave
                                            Rectangle {
                                                width: dayCol.selectedDay ? 10 : 6
                                                height: width
                                                radius: width / 2
                                                x: dayCol.width / 2 - width / 2
                                                y: wave.py(dayCol.index) - height / 2
                                                color: dayCol.selectedDay ? Theme.accentHi : Theme.fgDim
                                                opacity: dayCol.focused ? 1 : 0.6
                                            }
                                            // value above the dot (selected or hovered day only)
                                            Text {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                y: wave.py(dayCol.index) - 24
                                                text: root.fmtTo(Math.round(dayCol.modelData.secs * root.progress), dayCol.modelData.secs)
                                                color: dayCol.selectedDay ? Theme.accentHi : Theme.fg
                                                font.family: root.mono
                                                font.pixelSize: 10
                                                opacity: dayCol.focused ? 1 : 0
                                                Behavior on opacity { NumberAnimation { duration: 0} }
                                            }
                                            // day name at the bottom
                                            Text {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                anchors.bottom: parent.bottom
                                                text: dayCol.modelData.label
                                                color: dayCol.selectedDay ? Theme.fg : Theme.fgDim
                                                font.family: root.mono
                                                font.pixelSize: 10
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onEntered: root.hoverIdx = dayCol.index
                                                onExited: if (root.hoverIdx === dayCol.index) root.hoverIdx = -1
                                                onClicked: root.setView(1, root.days.length - 1 - dayCol.index)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ════════════ PAGE 1: ACTIVITY ════════════
                        ColumnLayout {
                            spacing: 12

                            // Heatmap card (Sunday on top, one column per week)
                            Glass {
                                id: heatCard
                                Layout.fillWidth: true
                                Layout.preferredHeight: heatCol.implicitHeight + 32
                                radius: 20

                                ColumnLayout {
                                    id: heatCol
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 10

                                    // Cell size from the available width (16 = day-label column + gap)
                                    readonly property real cw: Math.max(8, Math.floor((width - 16 - (root.heatWeeks - 1) * 3) / root.heatWeeks))

                                    Row {
                                        Layout.alignment: Qt.AlignHCenter
                                        spacing: 4

                                        // Day labels (M / W / F)
                                        Column {
                                            spacing: 3
                                            width: 12
                                            Item { width: 12; height: 14 }
                                            Repeater {
                                                model: 7
                                                Item {
                                                    id: dl
                                                    required property int index
                                                    width: 12
                                                    height: heatCol.cw
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: dl.index === 1 ? "M" : dl.index === 3 ? "W" : dl.index === 5 ? "F" : ""
                                                        color: Theme.fgDim
                                                        font.family: root.mono
                                                        font.pixelSize: 8
                                                    }
                                                }
                                            }
                                        }

                                        // Week columns
                                        Row {
                                            spacing: 3
                                            Repeater {
                                                model: root.heat

                                                Column {
                                                    id: wk
                                                    required property var modelData
                                                    required property int index
                                                    spacing: 3

                                                    // month label above the first week of each month
                                                    Item {
                                                        width: heatCol.cw
                                                        height: 14
                                                        Text {
                                                            text: wk.modelData.label
                                                            color: Theme.fgDim
                                                            font.family: root.mono
                                                            font.pixelSize: 8
                                                        }
                                                    }

                                                    Repeater {
                                                        model: wk.modelData.days

                                                        Item {
                                                            id: hc
                                                            required property var modelData
                                                            width: heatCol.cw
                                                            height: heatCol.cw
                                                            opacity: hc.modelData.future ? 0 : 1

                                                            // empty cell
                                                            Rectangle {
                                                                anchors.fill: parent
                                                                radius: 6
                                                                color: Theme.surfaceHi
                                                                opacity: 0.55
                                                            }
                                                            // activity overlay: brighter = more time
                                                            Rectangle {
                                                                anchors.fill: parent
                                                                radius: 6
                                                                color: hc.modelData.ago === 0 ? Theme.accentHi : Theme.accent
                                                                opacity: root.heatOpacity(hc.modelData.secs) * root.lp(wk.index, root.heatWeeks)
                                                            }
                                                            MouseArea {
                                                                anchors.fill: parent
                                                                hoverEnabled: true
                                                                enabled: !hc.modelData.future
                                                                cursorShape: hc.modelData.ago <= 6 ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                                onEntered: root.heatTip = Qt.formatDate(new Date(hc.modelData.date + "T00:00:00"), "ddd d MMM yyyy")
                                                                    + "  ·  " + (hc.modelData.secs > 0 ? root.fmt(hc.modelData.secs) : "no activity")
                                                                onExited: root.heatTip = "Hover a day for details"
                                                                // days from the last week open on the overview page
                                                                onClicked: if (hc.modelData.ago <= 6) { root.page = 0; root.setView(1, hc.modelData.ago) }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Hover details
                                    Text {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        text: root.heatTip
                                        color: Theme.accentHi
                                        font.family: root.mono
                                        font.pixelSize: 11
                                    }

                                    // Legend: less -> more
                                    Row {
                                        Layout.alignment: Qt.AlignRight
                                        spacing: 4

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "less"
                                            color: Theme.fgDim
                                            font.family: root.mono
                                            font.pixelSize: 8
                                        }
                                        Repeater {
                                            model: [0, 0.3, 0.5, 0.75, 1]

                                            Item {
                                                id: lg
                                                required property real modelData
                                                width: 11
                                                height: 11
                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: 3
                                                    color: Theme.surfaceHi
                                                    opacity: 0.55
                                                }
                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: 3
                                                    color: Theme.accent
                                                    opacity: lg.modelData
                                                }
                                            }
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "more"
                                            color: Theme.fgDim
                                            font.family: root.mono
                                            font.pixelSize: 8
                                        }
                                    }
                                }
                            }

                            // Streak stats
                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                rowSpacing: 10
                                columnSpacing: 10

                                Repeater {
                                    model: [
                                        { k: "CURRENT STREAK", v: root.heatStats.current + " days" },
                                        { k: "LONGEST STREAK", v: root.heatStats.longest + " days" },
                                        { k: "ACTIVE DAYS", v: root.heatStats.active + " / " + root.heatStats.total },
                                        { k: "BEST DAY", v: root.heatStats.bestSecs > 0
                                            ? root.fmt(root.heatStats.bestSecs) + "  ·  " + Qt.formatDate(new Date(root.heatStats.bestDate + "T00:00:00"), "d MMM")
                                            : "–" }
                                    ]

                                    Glass {
                                        id: stat
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        Layout.preferredHeight: 72
                                        radius: 18

                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            spacing: 3
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: stat.modelData.k
                                                color: Theme.fgDim
                                                font.family: root.mono
                                                font.pixelSize: 8
                                                font.letterSpacing: 1.2
                                            }
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: stat.modelData.v
                                                color: Theme.fg
                                                font.family: root.mono
                                                font.pixelSize: 18
                                                font.weight: Font.DemiBold
                                            }
                                        }
                                    }
                                }
                            }

                            Item { Layout.fillHeight: true }   // pushes everything to the top
                        }
                    }
                }
            }
        }
    }
}
