// File: ~/viii-shell-2/shell/MusicPanel.qml
// Tiny always-present part of the music panel: the IPC target and the
// lazy loader. The real panel (MusicCard.qml) is created on the first
// `qsctl music toggle` and destroyed shortly after the panel closes, so it
// costs nothing while you are not using it.
import Quickshell
import Quickshell.Io
import QtQuick

Scope {
    id: root

    property bool shown: false           // what the keybind toggles
    property bool alive: false           // true while MusicCard exists (open + closing)
    readonly property int closeMs: 0   // leave time for the close animation

    onShownChanged: {
        if (shown) { unload.stop(); alive = true }
        else unload.restart()
    }
    Timer { id: unload; interval: root.closeMs; onTriggered: root.alive = false }

    IpcHandler {
        target: "music"
        function toggle(): void { root.shown = !root.shown }
    }

    LazyLoader {
        active: root.alive
        MusicCard { shown: root.shown }
    }
}
