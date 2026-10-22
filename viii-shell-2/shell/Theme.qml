// File: ~/viii-shell-2/shell/Theme.qml
// The single source of colors for the whole shell.
//
// How it works:
//   1. On startup it reads the theme name from ~/.local/state/viii-shell/current
//   2. It loads ~/viii-shell-2/themes/<name>/palette.json
//   3. Every component binds to Theme.accent, Theme.bg, ... instead of a hex code
//   4. `viii-theme <name>` calls the "theme" IPC target below -> name changes ->
//      the new palette loads -> every color fades to its new value at once
//   5. Editing a palette.json while the shell runs updates the colors live.
//
// Missing keys in a palette.json simply keep their previous value.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // ---------------------------------------------------------------- paths
    readonly property string home: Quickshell.env("HOME")
    readonly property string themesDir: home + "/viii-shell-2/themes"
    readonly property string stateFile: home + "/.local/state/viii-shell/current"

    // ---------------------------------------------------------------- state
    property string name: ""        // active theme folder name, e.g. "atmos"
    property string label: ""       // display name from palette.json
    property bool ready: false      // false until the first palette is applied (no fade at startup)
    property int fadeMs: 700        // how long a theme-to-theme color fade lasts

    // ---------------------------------------------------------------- colors
    // Defaults are the old "atmos" look, so the shell is never unstyled.
    property color bg: "#10141c"            // panel background (alpha applied separately)
    property real  bgAlpha: 0.92
    property color surface: "#1c243a"       // chips, buttons, active-row highlight
    property color surfaceHi: "#26304d"     // hover / pressed surface
    property color line: "#2b4560"          // borders and dividers
    property color fg: "#e5e5e5"            // main text
    property color fgDim: "#8892b0"         // secondary text
    property color accent: "#3b82f6"        // the theme's signature color
    property color accentHi: "#60a5fa"      // lighter accent (hover, highlights)
    property color accentText: "#10141c"      // text drawn ON TOP of an accent fill
    property color good: "#3b82f6"          // charging, connected, success
    property color bad: "#ff5555"           // errors, wrong password
    property var   chart: ["#3b82f6", "#7fd4ff", "#ffd479", "#ff9fb2", "#c3a6ff", "#ffb07a", "#e5e5e5", "#888888"]

    // bg with its alpha baked in; follows the fade because it binds to the animated values
    readonly property color panel: Qt.rgba(bg.r, bg.g, bg.b, bgAlpha)

    // ---------------------------------------------------------------- fades
    // One Behavior per property. They only run once `ready` is true, so the
    // very first palette appears instantly instead of fading in from the defaults.
    Behavior on bg        { enabled: root.ready; ColorAnimation  { duration: root.fadeMs; easing.type: Easing.InOutQuad } }
    Behavior on bgAlpha   { enabled: root.ready; NumberAnimation { duration: root.fadeMs; easing.type: Easing.InOutQuad } }
    Behavior on surface   { enabled: root.ready; ColorAnimation  { duration: root.fadeMs; easing.type: Easing.InOutQuad } }
    Behavior on surfaceHi { enabled: root.ready; ColorAnimation  { duration: root.fadeMs; easing.type: Easing.InOutQuad } }
    Behavior on line      { enabled: root.ready; ColorAnimation  { duration: root.fadeMs; easing.type: Easing.InOutQuad } }
    Behavior on fg        { enabled: root.ready; ColorAnimation  { duration: root.fadeMs; easing.type: Easing.InOutQuad } }
    Behavior on fgDim     { enabled: root.ready; ColorAnimation  { duration: root.fadeMs; easing.type: Easing.InOutQuad } }
    Behavior on accent    { enabled: root.ready; ColorAnimation  { duration: root.fadeMs; easing.type: Easing.InOutQuad } }
    Behavior on accentHi  { enabled: root.ready; ColorAnimation  { duration: root.fadeMs; easing.type: Easing.InOutQuad } }
    Behavior on accentText  { enabled: root.ready; ColorAnimation  { duration: root.fadeMs; easing.type: Easing.InOutQuad } }
    Behavior on good      { enabled: root.ready; ColorAnimation  { duration: root.fadeMs; easing.type: Easing.InOutQuad } }
    Behavior on bad       { enabled: root.ready; ColorAnimation  { duration: root.fadeMs; easing.type: Easing.InOutQuad } }

    // ---------------------------------------------------------------- loading
    // Use a palette value if the file has it, otherwise keep the current one.
    function pick(value, current) {
        return (value === undefined || value === null || value === "") ? current : value
    }

    function applyPalette(raw) {
        var p
        try {
            p = JSON.parse(raw)
        } catch (e) {
            console.warn("Theme: palette.json is not valid JSON:", e)
            return
        }

        label     = pick(p.label, name)
        bgAlpha   = pick(p.bgAlpha, bgAlpha)
        bg        = pick(p.bg, bg)
        surface   = pick(p.surface, surface)
        surfaceHi = pick(p.surfaceHi, surfaceHi)
        line      = pick(p.line, line)
        fg        = pick(p.fg, fg)
        fgDim     = pick(p.fgDim, fgDim)
        accent    = pick(p.accent, accent)
        accentHi  = pick(p.accentHi, accentHi)
        accentText  = pick(p.onAccent, accentText)
        good      = pick(p.good, good)
        bad       = pick(p.bad, bad)
        chart     = pick(p.chart, chart)

        // Turn the fades on only AFTER the first palette is in place.
        if (!ready) Qt.callLater(function() { root.ready = true })
    }

    // Which theme to start with: whatever viii-theme last wrote to the state file.
    FileView {
        path: root.stateFile
        onLoaded: {
            var n = text().trim()
            if (n !== "" && root.name === "") root.name = n
        }
    }

    // The palette itself. Changing `name` changes `path`, which reloads the file.
    // watchChanges means editing palette.json updates the running shell live.
    FileView {
        path: root.name !== "" ? root.themesDir + "/" + root.name + "/palette.json" : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.applyPalette(text())
        onLoadFailed: (error) => console.warn("Theme: could not load", path, error)
    }

    // qs -p ~/viii-shell-2/shell ipc call theme setTheme <name>
    IpcHandler {
        target: "theme"
        function setTheme(theme: string): void { root.name = theme }
        function getTheme(): string { return root.name }
    }
}
