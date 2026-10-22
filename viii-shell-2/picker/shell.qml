// File: ~/viii-shell-2/picker/shell.qml
// The theme picker, "cover flow" style: wide wallpaper cards in a row, the selected
// one in the middle (and animated, when the theme has a loop.gif).
//
// It is NOT left running: `viii-theme --picker` (your keybind) starts it, it
// scans ~/viii-shell-2/themes, and it quits when you apply or press Esc. While
// closed it uses no memory and no CPU. Pressing the keybind again closes it.
//
// Keys:  ← → ↑ ↓ (or h j k l)  browse        1-9  jump to a theme
//        Enter  apply and close              Space  apply and stay open
//        Esc  close
// Mouse: click a card or a dot to select it, click the selected card to apply,
//        scroll to browse, click the dark background to close.
//
// Needs Qt 6.6+ and QtQuick.Effects.
//
// Performance notes (what changed vs. the first version):
//  - images are decoded at card size (sourceSize), not full resolution
//  - images load once and stay loaded (no reload while scrolling past them)
//  - only the selected card runs an AnimatedImage, and only after the slide settles
//  - ONE shared rounded-corner mask instead of one (4x MSAA) mask per card
//  - the masked "face" is static while you browse; dimming is drawn on top instead,
//    so the effect layers are not re-rendered every frame
//  - no per-frame color animation inside the masked content

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string themesDir: home + "/viii-shell-2/themes"
    readonly property string switcher: home + "/.local/bin/viii-theme"
    readonly property string mono: "JetBrainsMono Nerd Font"

    // Spring ("liquid stretch") settings. The picker is a separate shell and can't read
    // Theme.qml, so keep these equal to springStiffness / springDamping there.
    readonly property real springK: 3.2
    readonly property real springD: 0.30

    // ------------------------------------------------------------ theme list
    // Filled by `viii-theme --scan`: one JSON line per theme folder.
    property var themes: []
    property var pending: []
    property string currentName: ""
    property bool loaded: false
    property int sel: 0

    // true once the row has stopped sliding; the gif only starts playing then,
    // so decoding never competes with the slide animation.
    property bool settled: false
    Timer { id: settleTimer; interval: 560; onTriggered: root.settled = true }

    // Unwrapped position: grows past the list length so the row always slides the short way.
    property int dialIdx: 0
    property real pos: dialIdx
    // no animation for the very first placement (it used to slide in from 0 on open)
    Behavior on pos {
        enabled: root.loaded
        NumberAnimation { duration: 520; easing.type: Easing.OutBack; easing.overshoot: 0.7 }
    }

    readonly property var fallback: ({
        name: "", label: "No themes found", image: "",
        bg: "#10141c", surface: "#1c243a", line: "#2b4560",
        fg: "#e5e5e5", fgDim: "#8892b0", accent: "#3b82f6", accentHi: "#60a5fa"
    })
    readonly property var cur: themes.length > 0 ? themes[Math.min(sel, themes.length - 1)] : fallback
    readonly property bool curAnimated: cur.image !== "" && cur.image.toLowerCase().endsWith(".gif")

    // Everything in the picker is tinted with the theme you are previewing.
    property color accent: cur.accent
    property color accentHi: cur.accentHi
    property color bgc: cur.bg
    property color fg: cur.fg
    property color fgDim: cur.fgDim
    Behavior on accent   { ColorAnimation { duration: 350 } }
    Behavior on accentHi { ColorAnimation { duration: 350 } }
    Behavior on bgc      { ColorAnimation { duration: 350 } }
    Behavior on fg       { ColorAnimation { duration: 350 } }
    Behavior on fgDim    { ColorAnimation { duration: 350 } }

    property string status: "Pick a theme"
    property color statusColor: Qt.rgba(1, 1, 1, 0.4)
    property string lastErr: ""
    property bool closeAfterApply: false

    // fade in on open, fade out before quitting
    property real shown: 0
    property bool closing: false
    Behavior on shown { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Component.onCompleted: shown = 1

    // small "poke" of the whole row whenever the selection changes
    property real pop: 1
    Behavior on pop { SpringAnimation { spring: root.springK; damping: root.springD; epsilon: 0.001 } }
    onSelChanged: {
        pop = 0.97
        popRelease.restart()
        settled = false
        settleTimer.restart()
    }
    Timer { id: popRelease; interval: 70; onTriggered: root.pop = 1 }

    // -------------------------------------------------------------- actions
    function onScanLine(line) {
        var o
        try { o = JSON.parse(line) } catch (e) { return }
        if (o.current !== undefined) { currentName = o.current; return }
        if (!o.name) return
        var p = o.p || {}
        pending.push({
            name: o.name,
            label: p.label || o.name,
            // loop.gif if the theme has one, otherwise its bg.* (chosen by `viii-theme --scan`)
            image: o.bg ? "file://" + themesDir + "/" + o.name + "/" + o.bg : "",
            bg: p.bg || "#10141c",
            surface: p.surface || "#1c243a",
            line: p.line || "#2b4560",
            fg: p.fg || "#e5e5e5",
            fgDim: p.fgDim || "#8892b0",
            accent: p.accent || "#3b82f6",
            accentHi: p.accentHi || p.accent || "#60a5fa"
        })
    }

    function finishScan() {
        themes = pending
        for (var i = 0; i < themes.length; i++) {
            if (themes[i].name === currentName) sel = i
        }
        dialIdx = sel
        loaded = true
        settleTimer.restart()
        if (themes.length === 0) status = "No theme folders with a palette.json in " + themesDir
    }

    function go(i) {
        var n = themes.length
        if (n === 0) return
        var target = ((i % n) + n) % n
        // shortest way round the row
        var delta = target - sel
        if (delta > n / 2) delta -= n
        if (delta < -n / 2) delta += n
        sel = target
        dialIdx += delta
    }

    function apply(closeWhenDone) {
        if (themes.length === 0 || closing || runner.running) return
        lastErr = ""
        closeAfterApply = closeWhenDone
        status = "Applying " + cur.label + "…"
        statusColor = cur.accent
        runner.command = ["bash", switcher, cur.name]
        runner.running = true
    }

    function dismiss() {
        if (closing) return
        closing = true
        shown = 0
        quitTimer.start()
    }

    Timer { id: quitTimer; interval: 240; onTriggered: Qt.quit() }

    // `qs -p ~/viii-shell-2/picker ipc call picker dismiss` closes it (the keybind toggle uses this)
    IpcHandler {
        target: "picker"
        function dismiss(): void { root.dismiss() }
    }

    Process {
        id: scanner
        command: ["bash", root.switcher, "--scan"]
        running: true
        stdout: SplitParser { onRead: (line) => root.onScanLine(line) }
        onExited: root.finishScan()
    }

    Process {
        id: runner
        stderr: StdioCollector {
            onStreamFinished: {
                var t = text.trim()
                if (t !== "") {
                    root.lastErr = t
                    root.status = "Error: " + t.split("\n")[0]
                    root.statusColor = "#ff6b70"
                }
            }
        }
        onExited: (code, st) => {
            if (code !== 0 && root.lastErr === "") {
                root.status = "Failed (exit code " + code + ")"
                root.statusColor = "#ff6b70"
            } else if (root.lastErr === "") {
                root.currentName = root.cur.name
                root.status = "Applied " + root.cur.label
                root.statusColor = "#7ee787"
                if (root.closeAfterApply) root.dismiss()
            }
        }
    }

    // ----------------------------------------------------------------- window
    PanelWindow {
        id: win

        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "viii-picker"
        color: "transparent"

        // one scale factor for everything, so it fits small and large screens
        readonly property real u: Math.max(0.6, Math.min(1.4, Math.min(width / 1600, height / 900)))
        // size of the wallpaper cards (16:9)
        readonly property real cw: 620 * u
        readonly property real ch: cw * 9 / 16
        readonly property real radius: 30 * u

        // ONE rounded-corner mask shared by every card (rendered to a texture once)
        Rectangle {
            id: sharedMask
            width: win.cw
            height: win.ch
            radius: win.radius
            color: "white"
            visible: false
            layer.enabled: true
            layer.smooth: true
        }

        // dark tinted backdrop that deepens towards the bottom
        Rectangle {
            anchors.fill: parent
            opacity: root.shown
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(root.bgc.r, root.bgc.g, root.bgc.b, 0.80) }
                GradientStop { position: 1.0; color: Qt.rgba(root.bgc.r * 0.45, root.bgc.g * 0.45, root.bgc.b * 0.45, 0.95) }
            }
        }

        // click the backdrop to close, scroll to browse
        MouseArea {
            anchors.fill: parent
            onClicked: root.dismiss()
            onWheel: (w) => root.go(root.sel + (w.angleDelta.y > 0 ? -1 : 1))
        }

        Item {
            id: stage
            anchors.fill: parent
            focus: true
            opacity: root.shown
            Component.onCompleted: forceActiveFocus()

            Keys.onPressed: (e) => {
                var k = e.key
                if (k === Qt.Key_Escape) root.dismiss()
                else if (k === Qt.Key_Left || k === Qt.Key_Up || k === Qt.Key_H || k === Qt.Key_K) root.go(root.sel - 1)
                else if (k === Qt.Key_Right || k === Qt.Key_Down || k === Qt.Key_L || k === Qt.Key_J) root.go(root.sel + 1)
                else if (k === Qt.Key_Home) root.go(0)
                else if (k === Qt.Key_End) root.go(root.themes.length - 1)
                else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.apply(true)
                else if (k === Qt.Key_Space) root.apply(false)
                else if (k >= Qt.Key_1 && k <= Qt.Key_9 && k - Qt.Key_1 < root.themes.length) root.go(k - Qt.Key_1)
            }

            // small caption at the top
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 34 * win.u
                text: "THEMES  ·  " + root.themes.length
                color: root.fgDim
                font.family: root.mono
                font.pixelSize: 11 * win.u
                font.letterSpacing: 3 * win.u
            }

            Column {
                id: col
                anchors.centerIn: parent
                spacing: 26 * win.u

                // ── The cover flow ──
                Item {
                    id: flow
                    width: win.width
                    height: win.ch
                    scale: root.pop

                    // scroll anywhere on the row to browse (cards sit on top and handle clicks)
                    MouseArea {
                        anchors.fill: parent
                        onWheel: (w) => root.go(root.sel + (w.angleDelta.y > 0 ? -1 : 1))
                    }

                    Repeater {
                        model: root.themes
                        delegate: Item {
                            id: slot
                            required property int index
                            required property var modelData

                            readonly property int n: root.themes.length
                            // signed distance from the middle, wrapped so it is always the short way round
                            readonly property real off: {
                                var d = index - root.pos
                                return n > 0 ? d - n * Math.round(d / n) : d
                            }
                            readonly property real ab: Math.abs(off)
                            readonly property real sgn: off < 0 ? -1 : 1
                            readonly property bool isSel: index === root.sel
                            readonly property bool applied: modelData.name === root.currentName
                            readonly property bool isGif: modelData.image.toLowerCase().endsWith(".gif")
                            readonly property real near: Math.max(0, 1 - ab)             // 1 in the middle, 0 a step away
                            readonly property real farA: Math.min(ab, 1)                 // first step out
                            readonly property real farB: Math.max(0, Math.min(ab, 2) - 1) // second step out

                            // load the picture the first time the card gets close, then keep it
                            // (so scrolling back and forth never re-decodes anything)
                            property bool want: false
                            onAbChanged: if (!want && ab < 3.2) want = true
                            Component.onCompleted: want = ab < 3.2

                            width: win.cw
                            height: win.ch
                            x: flow.width / 2 + sgn * (farA * 0.80 + farB * 0.40) * win.cw - width / 2
                            y: 0
                            scale: 1 - 0.26 * farA - 0.12 * farB
                            z: 10 - ab
                            visible: ab < 2.6
                            opacity: Math.max(0, 1 - 0.38 * ab)

                            // soft outer ring around the card in the middle
                            Rectangle {
                                visible: slot.near > 0.02
                                anchors.centerIn: parent
                                width: parent.width + 20 * win.u
                                height: parent.height + 20 * win.u
                                radius: win.radius + 10 * win.u
                                color: "transparent"
                                border.width: 2 * win.u
                                border.color: Qt.alpha(slot.modelData.accent, 0.30 * slot.near)
                            }

                            // the picture. Static while browsing, so its texture is rendered once.
                            Item {
                                id: face
                                anchors.fill: parent
                                visible: false

                                // constant color (was bound to the animated theme color = re-render every frame)
                                Rectangle { anchors.fill: parent; color: Qt.lighter(slot.modelData.bg, 1.6) }

                                // still image (also the first frame of a gif), decoded at card size
                                Image {
                                    anchors.fill: parent
                                    source: slot.want ? slot.modelData.image : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    smooth: false              // keeps pixel art crisp
                                    sourceSize.width: Math.round(win.cw * 1.25)
                                }

                                // the animation only exists for the selected card, once it has settled
                                Loader {
                                    anchors.fill: parent
                                    active: slot.isGif && slot.isSel && root.settled && !root.closing
                                    sourceComponent: AnimatedImage {
                                        source: slot.modelData.image
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: false
                                        smooth: false
                                        playing: true
                                        sourceSize.width: Math.round(win.cw * 1.25)
                                    }
                                }

                                // darken the bottom edge a little
                                Rectangle {
                                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                    height: parent.height * 0.35
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
                                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.45) }
                                    }
                                }
                            }

                            MultiEffect {
                                anchors.fill: parent
                                source: face
                                autoPaddingEnabled: false
                                maskEnabled: true
                                maskSource: sharedMask
                            }

                            // dim the cards that are not selected (drawn ON TOP of the masked
                            // picture, so the picture's texture does not change while sliding)
                            Rectangle {
                                visible: slot.farA > 0.01
                                anchors.fill: parent
                                radius: win.radius
                                color: "black"
                                opacity: 0.45 * slot.farA
                            }

                            // glass edge in the theme's own accent
                            Rectangle {
                                anchors.fill: parent
                                radius: win.radius
                                color: "transparent"
                                border.width: (1 + 1.5 * slot.near) * win.u
                                border.color: Qt.alpha(slot.modelData.accent, 0.15 + 0.75 * slot.near)
                            }

                            // "active" badge on the theme that is currently applied
                            Rectangle {
                                visible: slot.applied
                                x: 16 * win.u
                                y: 16 * win.u
                                height: 26 * win.u
                                width: badgeText.implicitWidth + 28 * win.u
                                radius: height / 2
                                color: Qt.rgba(0, 0, 0, 0.55)
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.18)
                                Rectangle {
                                    x: 10 * win.u
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 7 * win.u
                                    height: 7 * win.u
                                    radius: width / 2
                                    color: "#7ee787"
                                }
                                Text {
                                    id: badgeText
                                    x: 22 * win.u
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "ACTIVE"
                                    color: "#e6ffe9"
                                    font.family: root.mono
                                    font.pixelSize: 9 * win.u
                                    font.letterSpacing: 1.5 * win.u
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: slot.isSel ? root.apply(true) : root.go(slot.index)
                            }
                        }
                    }

                    // shown instead of cards when there are no themes
                    Text {
                        anchors.centerIn: parent
                        visible: root.loaded && root.themes.length === 0
                        text: "Add a folder with\npalette.json + loop.gif (or bg.jpg) to\n~/viii-shell-2/themes"
                        horizontalAlignment: Text.AlignHCenter
                        color: root.fg
                        font.family: root.mono
                        font.pixelSize: 13 * win.u
                    }
                }

                // ── name + details of the selected theme ──
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6 * win.u

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 520 * win.u
                        horizontalAlignment: Text.AlignHCenter
                        text: root.cur.label
                        color: root.fg
                        font.family: root.mono
                        font.pixelSize: 26 * win.u
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.themes.length > 0
                              ? (root.sel + 1) + " / " + root.themes.length + "   ·   "
                                + (root.curAnimated ? "animated" : "still")
                                + (root.cur.name !== "" && root.cur.name === root.currentName ? "   ·   active" : "")
                              : ""
                        color: root.accent
                        font.family: root.mono
                        font.pixelSize: 11 * win.u
                        font.letterSpacing: 1.5 * win.u
                    }
                }

                // ── one dot per theme, in that theme's accent color ──
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10 * win.u
                    Repeater {
                        model: root.themes
                        delegate: Rectangle {
                            required property int index
                            required property var modelData
                            readonly property bool isSel: index === root.sel
                            width: (isSel ? 34 : 13) * win.u
                            height: 13 * win.u
                            radius: height / 2
                            color: modelData.accent
                            opacity: isSel ? 1 : 0.55
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.28)
                            Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 220 } }
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4 * win.u
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.go(parent.index)
                            }
                        }
                    }
                }

                // ── hints pill ──
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 660 * win.u
                    height: 42 * win.u
                    radius: height / 2
                    color: Qt.rgba(1, 1, 1, 0.07)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.12)

                    Text {
                        anchors.centerIn: parent
                        text: "← → browse  ·  ↵ apply & close  ·  space apply  ·  esc close"
                        color: root.fgDim
                        font.family: root.mono
                        font.pixelSize: 11 * win.u
                    }
                }

                // ── status ──
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8 * win.u
                    Rectangle {
                        width: 8 * win.u
                        height: 8 * win.u
                        radius: width / 2
                        color: root.statusColor
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: root.status
                        color: root.fgDim
                        font.family: root.mono
                        font.pixelSize: 11 * win.u
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }
}
