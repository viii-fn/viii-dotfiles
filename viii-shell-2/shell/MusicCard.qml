// File: ~/viii-shell-2/shell/MusicCard.qml
// The music panel itself (player pick, title cleanup, synced lyrics: the same
// logic as before). It only exists while the panel is open: MusicPanel.qml
// creates it on the first toggle and destroys it shortly after you close it.

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Effects

Scope {
    id: root

    property bool shown: false           // set by MusicPanel.qml

    // 0 = hidden, 1 = fully open. Starts at 0 and fades/scales in once created.
    property real appear: 0
    Behavior on appear { NumberAnimation { duration: 0; easing.type: Easing.OutCubic } }
    Component.onCompleted: {
        appear = Qt.binding(() => root.shown ? 1 : 0)
        // Lyrics used to be fetched in the background; now fetch when the card opens.
        if (key !== "") { status = "Loading lyrics…"; debounce.restart() }
    }

    // Preferred player: Spotify -> Amberol -> Active MPRIS player -> First available
    readonly property var player: {
        const ps = Mpris.players.values
        if (ps.length === 0) return null

        for (let i = 0; i < ps.length; i++) {
            if (ps[i].identity.toLowerCase().indexOf("spotify") >= 0) return ps[i]
        }
        for (let i = 0; i < ps.length; i++) {
            const id = ps[i].identity.toLowerCase()
            if (id.indexOf("amberol") >= 0 || id.indexOf("io.bassi.amberol") >= 0) return ps[i]
        }
        for (let i = 0; i < ps.length; i++) {
            if (ps[i].isPlaying) return ps[i]
        }
        return ps[0]
    }

    // Normalized title & artist for local media (e.g. Amberol, MPV, VLC)
    readonly property string parsedTitle: {
        if (!player || !player.trackTitle) return ""
        let t = player.trackTitle
        if (t.startsWith("file://")) {
            t = decodeURIComponent(t.substring(t.lastIndexOf("/") + 1))
        }
        t = t.replace(/\.(mp3|flac|m4a|ogg|wav|opus|aac)$/i, "")
        if ((!player.trackArtist || player.trackArtist.length === 0) && t.indexOf(" - ") !== -1) {
            return t.split(" - ").slice(1).join(" - ").trim()
        }
        return t
    }

    readonly property string parsedArtist: {
        if (!player) return ""
        if (player.trackArtist && player.trackArtist.length > 0) return player.trackArtist
        if (player.trackTitle) {
            let t = player.trackTitle
            if (t.startsWith("file://")) {
                t = decodeURIComponent(t.substring(t.lastIndexOf("/") + 1))
            }
            if (t.indexOf(" - ") !== -1) {
                return t.split(" - ")[0].trim()
            }
        }
        return ""
    }

    // --- Lyrics (LRCLIB) ---------------------------------------------------
    property var lines: []
    property string status: ""
    property bool again: false
    readonly property string key: player ? parsedArtist + "|" + parsedTitle : ""

    onKeyChanged: { lines = []; status = key ? "Loading lyrics…" : ""; debounce.restart() }
    Timer { id: debounce; interval: 400; onTriggered: root.fetchLyrics() }

    function fetchLyrics() {
        if (!parsedTitle) return
        if (lrc.running) { again = true; return }

        let args = [
            "curl", "-s", "-G", "-A", "quickshell-player", "https://lrclib.net/api/search",
            "--data-urlencode", "track_name=" + parsedTitle
        ]
        if (parsedArtist) {
            args.push("--data-urlencode", "artist_name=" + parsedArtist)
        }

        lrc.command = args
        lrc.running = true
    }

    Process {
        id: lrc
        stdout: StdioCollector { onStreamFinished: root.parseLyrics(text) }
        onExited: if (root.again) { root.again = false; root.fetchLyrics() }
    }

    function parseLyrics(raw) {
        try {
            const results = JSON.parse(raw)
            let best = null, bestDiff = 1e9
            const len = player ? player.length : 0
            for (const r of results) {
                if (!r.syncedLyrics) continue
                const diff = len > 0 ? Math.abs((r.duration || 0) - len) : 0
                if (diff < bestDiff) { best = r; bestDiff = diff }
            }
            if (!best) { status = "No synced lyrics found"; return }
            const out = []
            for (const l of best.syncedLyrics.split("\n")) {
                const m = l.match(/^\[(\d+):(\d+(?:\.\d+)?)\](.*)$/)
                if (m) out.push({ t: parseInt(m[1]) * 60 + parseFloat(m[2]), text: m[3].trim() })
            }
            lines = out
            status = out.length ? "" : "No synced lyrics found"
        } catch (e) { status = "No lyrics found" }
    }

    readonly property int idx: {
        const pos = player ? player.position : 0
        let i = -1
        for (let k = 0; k < lines.length; k++) { if (lines[k].t <= pos + 0.3) i = k; else break }
        return i
    }
    function lineAt(i) { return (i >= 0 && i < lines.length) ? lines[i].text : "" }
    function fmt(s) { return Math.floor(s / 60) + ":" + ("0" + Math.floor(s % 60)).slice(-2) }

    Timer {
        interval: 250; repeat: true
        running: root.shown && root.player !== null && root.player.isPlaying
        onTriggered: root.player.positionChanged()
    }

    // --- The window ---------------------------------------------------------
    FloatingWindow {
        id: win
        title: "Music"
        visible: true
        implicitWidth: panel.width
        implicitHeight: panel.height
        color: "transparent"

        Rectangle {
            id: panel
            x: 0
            y: 0
            width: 580
            height: Math.max(leftCol.implicitHeight, lyricsBox.implicitHeight) + 40
            radius: 28
            color: Qt.alpha(Theme.panel, 0.82)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.16)
            opacity: root.appear

            // Specular sheen across the top
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius - 1
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
                    GradientStop { position: 0.3; color: Qt.rgba(1, 1, 1, 0.0) }
                }
            }


            Row {
                anchors.centerIn: parent
                width: parent.width - 40
                spacing: 20

                // LEFT SIDE: Controls, Album Art & Meta
                Column {
                    id: leftCol
                    width: 180
                    spacing: 10

                    // Album art with rounded corners
                    Item {
                        width: parent.width
                        height: parent.width / 1.1547

                        Item {
                            id: artStack
                            anchors.fill: parent
                            visible: false
                            Rectangle { anchors.fill: parent; color: Theme.surface }
                            Text {
                                anchors.centerIn: parent
                                text: "♪"; font.pixelSize: 48; color: Theme.fgDim
                                visible: art.status !== Image.Ready
                            }
                            Image {
                                id: art
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectCrop
                                sourceSize: Qt.size(360, 360)
                                source: root.player ? (root.player.trackArtUrl || "") : ""
                            }
                        }
                        Rectangle {
                            id: artMask
                            anchors.fill: parent
                            radius: 22
                            visible: false
                            layer.enabled: true
                            layer.samples: 4
                            color: "white"
                        }
                        MultiEffect {
                            anchors.fill: parent
                            source: artStack
                            maskEnabled: true
                            maskSource: artMask
                        }
                        // thin light edge
                        Rectangle {
                            anchors.fill: parent
                            radius: 22
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.22)
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 2
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 14; font.weight: Font.Bold
                            color: Theme.fg
                            text: root.parsedTitle !== "" ? root.parsedTitle : "Nothing playing"
                        }
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11
                            color: Theme.fgDim
                            text: root.parsedArtist
                        }
                    }

                    // Progress bar (click to seek)
                    Column {
                        width: parent.width
                        spacing: 2
                        HexSlider {
                            width: parent.width
                            live: false
                            value: (root.player && root.player.length > 0)
                                   ? Math.min(1, root.player.position / root.player.length) : 0
                            onMoved: v => {
                                if (root.player && root.player.canSeek)
                                    root.player.position = v * root.player.length
                            }
                        }
                        Item {
                            width: parent.width; height: 12
                            Text { anchors.left: parent.left; font.pixelSize: 10; color: Theme.fgDim
                                   text: root.player ? root.fmt(root.player.position) : "0:00" }
                            Text { anchors.right: parent.right; font.pixelSize: 10; color: Theme.fgDim
                                   text: root.player ? root.fmt(root.player.length) : "0:00" }
                        }
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 10
                        IconBtn {
                            width: 36; height: 36; radius: 18
                            glyph: "\uf048"; glyphSize: 13; tone: Theme.fg
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: if (root.player) root.player.previous()
                        }
                        Rectangle {
                            width: 46; height: 46; radius: 23
                            color: Theme.accent
                            anchors.verticalCenter: parent.verticalCenter
                            scale: playHit.pressed ? 0.94 : 1
                            Behavior on scale { NumberAnimation { duration: 80 } }
                            Text {
                                anchors.centerIn: parent
                                text: (root.player && root.player.isPlaying) ? "\uf04c" : "\uf04b"
                                color: Theme.accentText
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 17
                            }
                            MouseArea {
                                id: playHit
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.player) root.player.togglePlaying()
                            }
                        }
                        IconBtn {
                            width: 36; height: 36; radius: 18
                            glyph: "\uf051"; glyphSize: 13; tone: Theme.fg
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: if (root.player) root.player.next()
                        }
                    }                    
                }

                // RIGHT SIDE: Synced Lyrics
                Item {
                    id: lyricsBox
                    width: parent.width - leftCol.width - parent.spacing
                    height: leftCol.implicitHeight
                    clip: true

                    Text {
                        anchors.centerIn: parent
                        visible: root.lines.length === 0
                        text: root.status
                        color: Theme.fgDim; font.pixelSize: 12
                    }

                    Column {
                        anchors.centerIn: parent
                        width: parent.width
                        spacing: 12
                        visible: root.lines.length > 0

                        Repeater {
                            model: 5
                            delegate: Text {
                                required property int index
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: index === 2 ? 15 : 12
                                font.weight: index === 2 ? Font.Bold : Font.Normal
                                color: index === 2 ? Theme.accentHi : Theme.fg
                                opacity: index === 2 ? 1 : (Math.abs(index - 2) === 1 ? 0.45 : 0.2)
                                text: root.lineAt(root.idx + index - 2)
                            }
                        }
                    }
                }
            }
        }
    }
}
