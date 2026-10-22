import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    Process { id: logger }

    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: {
            const t = ToplevelManager.activeToplevel
            if (!t || t.appId === "") return
            logger.command = [
                "sh", "-c",
                'mkdir -p ~/.local/share/screentime && echo "$0|60" >> ~/.local/share/screentime/$(date +%F).log',
                t.appId
            ]
            logger.running = true
        }
    }
}
