// File: ~/viii-shell-2/shell/DpiPanel.qml
// Tiny always-present part of the display-scale panel: the IPC target and the
// lazy loader. DpiWindow.qml (the real panel) exists only while it is open.
//   qsctl dpi toggle
import Quickshell
import Quickshell.Io
import QtQuick

Scope {
    id: root

    property bool shown: false
    property bool alive: false
    readonly property int closeMs: 0

    onShownChanged: {
        if (shown) { unload.stop(); alive = true }
        else unload.restart()
    }
    Timer { id: unload; interval: root.closeMs; onTriggered: root.alive = false }

    IpcHandler {
        target: "dpi"
        function toggle(): void { root.shown = !root.shown }
    }

    LazyLoader {
        active: root.alive
        DpiWindow {
            shown: root.shown
            onCloseRequested: root.shown = false
        }
    }
}
