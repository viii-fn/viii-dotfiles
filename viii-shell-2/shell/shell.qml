// File: ~/viii-shell-2/shell/shell.qml

import Quickshell

ShellRoot {
    // Reading Theme.name here makes Quickshell create the Theme singleton at
    // startup, which loads the active palette and registers the "theme" IPC
    // target that viii-theme uses to switch palettes without a restart.
    readonly property string activeTheme: Theme.name

    // One Island per monitor. Quickshell.screens is the list of connected screens.
    Variants {
        model: Quickshell.screens

        Island {
            // Variants hands each copy the screen it belongs to as "modelData".
            required property var modelData
            screen: modelData       // tells this copy which monitor to appear on
        }
    }

    // Lock is not wrapped: WlSessionLock already makes a lock surface per monitor by itself.
    MusicPanel {}
    AudioPanel {}
    ScreenTimeLogger {}
    DpiPanel {}
    ScreenTimePanel {}
    TrimPanel {}
    OmniLauncher {}
    GalleryPanel {}
    NotesPanel {}
    WeatherPanel {}
    QuickSettings {}
}
