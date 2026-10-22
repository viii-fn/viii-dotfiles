// File: ~/viii-shell-2/lock/shell.qml
// Lockscreen. Started by `viii-lock lock` (keybind Super+L).
//
// - Real session lock (ext-session-lock): labwc keeps every output locked until this
//   process unlocks it, so a crash cannot expose the desktop.
// - One surface per display, same layout on all of them. Content is scaled to each
//   screen's size, the wallpaper is cropped (never stretched).
// - Colors follow the active theme: `viii-lock lock` copies the current theme's
//   palette.json to ~/.config/viii-lock/palette.json right before starting this.
// - Quits right after a successful unlock, so it uses 0 RAM while you work.
//
// Needs Qt 6.6+ and QtQuick.Effects.

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam

ShellRoot {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string user: Quickshell.env("USER")
    readonly property string dataDir: "file://" + home + "/.config/viii-lock"
    readonly property string mono: "JetBrainsMono Nerd Font"

    // ---------------------------------------------------------------- palette
    FileView { id: palFile; path: root.home + "/.config/viii-lock/palette.json"; blockLoading: true }

    property var pal: ({})
    function loadPal() {
        try { return JSON.parse(palFile.text()) } catch (e) { return ({}) }
    }

    // Fallbacks are only used when no palette file exists.
    readonly property color bg: pal.bg || "#10141c"
    readonly property color fg: pal.fg || "#e5e5e5"
    readonly property color fgDim: pal.fgDim || "#8892b0"
    readonly property color accent: pal.accent || "#3b82f6"
    readonly property color accentHi: pal.accentHi || pal.accent || "#60a5fa"
    readonly property color bad: pal.bad || "#ff6b70"

    // ---------------------------------------------------------------- state
    property string password: ""
    property bool failed: false
    property int failCount: 0
    property bool unlocked: false
    readonly property bool busy: pam.active

    Component.onCompleted: pal = loadPal()

    function submit() {
        if (busy || password === "") return
        failed = false
        pam.start()
    }

    function typeKey(e) {
        if (busy) return
        failed = false
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
            submit()
        } else if (e.key === Qt.Key_Backspace) {
            password = password.slice(0, -1)
        } else if (e.key === Qt.Key_Escape
                   || ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_U)) {
            password = ""
        } else if (e.text.length > 0 && e.text.charCodeAt(0) >= 32 && password.length < 256) {
            password += e.text
        }
    }

    // Updates once a minute: almost no wakeups while locked.
    SystemClock { id: clock; precision: SystemClock.Minutes }

    PamContext {
        id: pam
        config: "login"      // /etc/pam.d/login

        onPamMessage: { if (responseRequired) respond(root.password) }

        onCompleted: (result) => {
            root.password = ""
            if (result === PamResult.Success) {
                root.unlocked = true
                // Safety net: if a normal quit ever hangs, this kills the lock process a moment later.
                Quickshell.execDetached(["sh", "-c", "sleep 2; pkill -f viii-shell-2/lock"])
            } else {
                root.failed = true
                root.failCount += 1
            }
        }
        onError: {
            root.password = ""
            root.failed = true
            root.failCount += 1
        }
    }

    // Give Wayland a moment to receive the unlock before the process exits.
    Timer { id: quitTimer; interval: 200; onTriggered: Qt.quit() }

    WlSessionLock {
        id: lock
        locked: !root.unlocked

        // Also fires if the compositor refuses the lock: then there is nothing to show, so exit.
        onLockedChanged: { if (!locked) quitTimer.start() }

        // Quickshell creates one of these for every display.
        WlSessionLockSurface {
            id: surf
            color: root.bg

            // one scale factor so every display gets the same layout, only bigger or smaller
            readonly property real u: Math.max(0.6, Math.min(1.8, Math.min(width / 1600, height / 900)))

            Item {
                id: keys
                anchors.fill: parent
                focus: true
                Component.onCompleted: forceActiveFocus()
                Keys.onPressed: (e) => { root.typeKey(e); e.accepted = true }

                // click anywhere to take keyboard focus on this display
                MouseArea {
                    anchors.fill: parent
                    onClicked: keys.forceActiveFocus()
                }

                // ---- wallpaper: cropped to fill, decoded once and shared by all displays
                Rectangle {
                    anchors.fill: parent
                    color: root.bg
                }
                Image {
                    id: wall
                    anchors.fill: parent
                    source: root.dataDir + "/wallpaper"
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 1920
                    visible: status === Image.Ready
                }
                // darken so the text stays readable on any picture
                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, wall.status === Image.Ready ? 0.75 : 0)
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 30 * surf.u

                    // ---- clock
                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 2 * surf.u

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.formatDateTime(clock.date, "HH:mm")
                            color: root.fg
                            font.family: root.mono
                            font.pixelSize: 96 * surf.u
                            font.weight: Font.DemiBold
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.formatDateTime(clock.date, "dddd, d MMMM")
                            color: root.fgDim
                            font.family: root.mono
                            font.pixelSize: 16 * surf.u
                        }
                    }

                    // ---- glass card (same look as the launcher)
                    Rectangle {
                        id: card
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 400 * surf.u
                        height: inner.implicitHeight + 56 * surf.u
                        radius: 36 * surf.u
                        color: Qt.alpha(root.bg, 0.62)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.14)

                        transform: Translate { id: shakeT }
                        SequentialAnimation {
                            id: shake
                            NumberAnimation { target: shakeT; property: "x"; to: -16 * surf.u; duration: 50 }
                            NumberAnimation { target: shakeT; property: "x"; to: 16 * surf.u; duration: 80 }
                            NumberAnimation { target: shakeT; property: "x"; to: -10 * surf.u; duration: 70 }
                            NumberAnimation { target: shakeT; property: "x"; to: 0; duration: 60 }
                        }
                        Connections {
                            target: root
                            function onFailCountChanged() { shake.restart() }
                        }

                        // Specular sheen across the top
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 1
                            radius: parent.radius - 1
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
                                GradientStop { position: 0.25; color: Qt.rgba(1, 1, 1, 0.0) }
                            }
                        }

                        Column {
                            id: inner
                            anchors.centerIn: parent
                            width: 336 * surf.u
                            spacing: 14 * surf.u

                            // ---- profile image
                            Item {
                                id: avatar
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 112 * surf.u
                                height: 112 * surf.u

                                Rectangle {
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: Qt.alpha(root.accent, 0.25)
                                    border.width: 2 * surf.u
                                    border.color: Qt.alpha(root.accentHi, 0.70)
                                }

                                Image {
                                    id: pic
                                    anchors.fill: parent
                                    anchors.margins: 4 * surf.u
                                    source: root.dataDir + "/avatar"
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    sourceSize.width: 256
                                    sourceSize.height: 256
                                    visible: false
                                }
                                Rectangle {
                                    id: picMask
                                    anchors.fill: pic
                                    radius: width / 2
                                    visible: false
                                    layer.enabled: true
                                    layer.samples: 4
                                    color: "white"
                                }
                                MultiEffect {
                                    anchors.fill: pic
                                    source: pic
                                    maskEnabled: true
                                    maskSource: picMask
                                    visible: pic.status === Image.Ready
                                }

                                // fallback when no image is set: first letter of the username
                                Text {
                                    anchors.centerIn: parent
                                    visible: pic.status !== Image.Ready
                                    text: root.user.charAt(0).toUpperCase()
                                    color: root.accentHi
                                    font.family: root.mono
                                    font.pixelSize: 48 * surf.u
                                    font.weight: Font.DemiBold
                                }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.user
                                color: root.fg
                                font.family: root.mono
                                font.pixelSize: 15 * surf.u
                                font.weight: Font.DemiBold
                            }

                            // ---- password pill (same shape as the launcher search bar)
                            Rectangle {
                                width: parent.width
                                height: 42 * surf.u
                                radius: height / 2
                                color: Qt.rgba(1, 1, 1, 0.07)
                                border.width: 1
                                border.color: root.failed
                                    ? Qt.alpha(root.bad, 0.80)
                                    : Qt.alpha(root.accent, 0.70)

                                Text {
                                    anchors.centerIn: parent
                                    visible: root.password === "" && !root.busy
                                    text: "Password"
                                    color: root.fgDim
                                    font.family: root.mono
                                    font.pixelSize: 12 * surf.u
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: root.password !== "" || root.busy
                                    text: root.busy ? "Checking…" : "•".repeat(Math.min(root.password.length, 28))
                                    color: root.busy ? root.fgDim : root.fg
                                    font.family: root.mono
                                    font.pixelSize: (root.busy ? 12 : 18) * surf.u
                                    font.letterSpacing: root.busy ? 0 : 3 * surf.u
                                }
                            }

                            // fixed height so the card does not jump when the message changes
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                height: 14 * surf.u
                                text: root.failed ? "Wrong password" : "Enter to unlock"
                                color: root.failed ? root.bad : root.fgDim
                                font.family: root.mono
                                font.pixelSize: 10 * surf.u
                            }
                        }
                    }
                }
            }
        }
    }
}
