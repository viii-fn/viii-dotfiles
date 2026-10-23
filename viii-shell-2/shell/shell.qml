// File: ~/viii-shell-2/shell/shell.qml

import Quickshell

ShellRoot {
    // Reading Theme.name here makes Quickshell create the Theme singleton at
    // startup, which loads the active palette and registers the "theme" IPC
    // target that viii-theme uses to switch palettes without a restart.
    readonly property string activeTheme: Theme.name

    // One Notch per monitor. Quickshell.screens is the list of connected screens.
    // NOTE: each Notch runs its own NotificationServer and IPC targets, so with
    // two monitors only one copy can own them. If you use several screens, change
    // the model to [Quickshell.screens[0]].
    Variants {
        model: Quickshell.screens

        Notch {
            required property var modelData
            screen: modelData
        }
    }

    // Lock is not wrapped: WlSessionLock already makes a lock surface per monitor by itself.
    ScreenTimeLogger {}

    // ── Still separate windows, to be ported into the notch next ──
    TrimPanel {}
    GalleryPanel {}
    NotesPanel {}

    // Replaced by the notch: Island, MusicPanel, AudioPanel, DpiPanel, QuickSettings,
    // ScreenTimePanel, WeatherPanel, OmniLauncher
    // (music, audio output, display scale and quick toggles now live in the notch).
}
