import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import Quickshell

// Video-first trim workspace, glass style. Created on demand by TrimPanel.qml.
// Segment state and ffmpeg export are owned by TrimPanel; this file is UI,
// preview playback (skips cut parts, applies per-segment speed) and shortcuts.
FloatingWindow {
    id: win

    property var panel
    readonly property var cur: panel && panel.sel >= 0 && panel.sel < panel.segments.length
                               ? panel.segments[panel.sel] : null

    visible: true
    title: "Trim"
    implicitWidth: 900
    implicitHeight: 740
    color: "transparent"

    onVisibleChanged: if (!visible && panel) panel.closeWin()

    // Preview behavior: while playing, jump over cut segments and match the
    // current segment's speed. (Position updates are ~100ms granular, so
    // boundaries in the preview are approximate; export is exact.)
    function enforce() {
        if (!panel || panel.segments.length === 0) return
        if (player.playbackState !== MediaPlayer.PlayingState) return
        var segs = panel.segments
        var idx = panel.segIndexAt(player.position)
        if (idx < 0) return
        var g = segs[idx]
        if (!g.keep) {
            for (var i = idx + 1; i < segs.length; i++) {
                if (segs[i].keep) { player.position = segs[i].s; return }
            }
            player.pause()   // nothing kept after this point
            return
        }
        if (player.playbackRate !== g.speed) player.playbackRate = g.speed
    }

    MediaPlayer {
        id: player
        source: win.panel ? "file://" + win.panel.file : ""
        videoOutput: out
        audioOutput: AudioOutput {}
        onDurationChanged: {
            if (win.panel && duration > 0 && win.panel.segments.length === 0)
                win.panel.initSegments(duration)
        }
        onHasAudioChanged: if (win.panel) win.panel.hasAudio = hasAudio
        onPositionChanged: win.enforce()
        Component.onCompleted: {
            if (win.panel) win.panel.hasAudio = hasAudio
            play()
        }
    }

    Shortcut { sequence: "Escape"; onActivated: if (win.panel) win.panel.closeWin() }
    Shortcut { sequence: "Space"; onActivated: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play() }
    Shortcut { sequence: "S"; onActivated: if (win.panel) win.panel.splitAt(player.position) }
    Shortcut { sequence: "X"; onActivated: if (win.panel) win.panel.toggleKeep() }
    Shortcut { sequence: "Delete"; onActivated: if (win.panel) win.panel.toggleKeep() }
    Shortcut { sequence: "J"; onActivated: if (win.panel) win.panel.mergeNext() }
    Shortcut { sequence: "I"; onActivated: if (win.panel) win.panel.cutBefore(player.position) }
    Shortcut { sequence: "O"; onActivated: if (win.panel) win.panel.cutAfter(player.position) }
    Shortcut { sequence: "]"; onActivated: if (win.panel) win.panel.stepSpeed(1) }
    Shortcut { sequence: "["; onActivated: if (win.panel) win.panel.stepSpeed(-1) }
    Shortcut { sequence: "Left"; onActivated: player.position = Math.max(0, player.position - 1000) }
    Shortcut { sequence: "Right"; onActivated: player.position = Math.min(player.duration, player.position + 1000) }

    // Glass body (no radius or border of its own: labwc rounds and outlines the window)
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Theme.panel, 0.82)

        // Specular sheen across the top
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
                GradientStop { position: 0.2; color: Qt.rgba(1, 1, 1, 0.0) }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 14

            // ── Header: icon, title + file name, play state ──
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Text {
                    text: "\uf03d"
                    color: Theme.accentHi
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 18
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: "Trim"
                        color: Theme.fg
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: win.panel ? win.panel.file.split("/").pop() : "No video selected"
                        color: Theme.fgDim
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }
                }

                Glass {
                    Layout.preferredWidth: 96
                    Layout.preferredHeight: 30
                    radius: 15
                    Row {
                        anchors.centerIn: parent
                        spacing: 7
                        Rectangle {
                            width: 8
                            height: 8
                            radius: 4
                            anchors.verticalCenter: parent.verticalCenter
                            color: player.playbackState === MediaPlayer.PlayingState ? Theme.good : Theme.fgDim
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: player.playbackState === MediaPlayer.PlayingState ? "Playing" : "Ready"
                            color: Theme.fgDim
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                        }
                    }
                }
            }

            // ── Preview stage ──
            Glass {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 230
                radius: 20
                color: Qt.rgba(0, 0, 0, 0.30)

                Item {
                    anchors.fill: parent
                    anchors.margins: 8

                    VideoOutput {
                        id: out
                        anchors.fill: parent
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !player.hasVideo
                        text: "Waiting for video…"
                        color: Theme.fgDim
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                    }
                }
            }

            // ── Timeline ──
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "Click a segment to select · drag to scrub"
                        color: Theme.fgDim
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: win.panel ? win.panel.fmt(player.position) + " / " + win.panel.fmt(player.duration) : "00:00.000"
                        color: Theme.accentHi
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                    }
                }

                // Segment strip: one block per segment, playhead on top
                Item {
                    id: tl
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    readonly property real dur: win.panel ? win.panel.duration : 0

                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: Qt.rgba(1, 1, 1, 0.06)
                    }

                    Repeater {
                        model: win.panel ? win.panel.segments : []
                        delegate: Rectangle {
                            id: seg
                            required property var modelData
                            required property int index
                            readonly property bool selected: win.panel !== null && win.panel.sel === index

                            x: tl.dur > 0 ? tl.width * modelData.s / tl.dur : 0
                            width: tl.dur > 0
                                   ? Math.max(2, tl.width * (modelData.e - modelData.s) / tl.dur - 2) : 0
                            height: tl.height
                            radius: 8
                            color: modelData.keep
                                   ? Qt.alpha(Theme.accent, seg.selected ? 0.85 : 0.45)
                                   : Qt.alpha(Theme.bad, 0.16)
                            border.width: seg.selected ? 2 : 0
                            border.color: Theme.fg

                            Text {
                                anchors.centerIn: parent
                                visible: seg.width > 34
                                text: !seg.modelData.keep ? "CUT"
                                      : (seg.modelData.speed !== 1 ? seg.modelData.speed + "x" : "")
                                color: seg.modelData.keep ? Theme.accentText : Theme.bad
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    // playhead
                    Rectangle {
                        z: 5
                        y: -4
                        width: 2
                        height: tl.height + 8
                        radius: 1
                        x: tl.dur > 0 ? tl.width * player.position / tl.dur - 1 : 0
                        color: Theme.fg
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        function seekTo(mx) {
                            var f = Math.max(0, Math.min(1, mx / width))
                            player.position = f * player.duration
                            return f * player.duration
                        }
                        onPressed: (m) => {
                            var ms = seekTo(m.x)
                            if (win.panel) win.panel.selectAt(ms)
                        }
                        onPositionChanged: (m) => { if (pressed) seekTo(m.x) }
                    }
                }

                // SELECTED / SPEED / OUTPUT
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: [
                            { label: "SELECTED", color: Theme.good,
                              value: win.cur && win.panel
                                     ? win.panel.fmt(win.cur.s) + " → " + win.panel.fmt(win.cur.e)
                                       + (win.cur.keep ? "" : "  (cut)")
                                     : "—" },
                            { label: "SPEED", color: Theme.accentHi,
                              value: win.cur ? win.cur.speed + "x" : "—" },
                            { label: "OUTPUT", color: Theme.accentHi,
                              value: win.panel
                                     ? win.panel.fmt(win.panel.outMs()) + "  ·  "
                                       + win.panel.keptSegs().length + " clip"
                                       + (win.panel.keptSegs().length === 1 ? "" : "s")
                                     : "00:00.000" }
                        ]
                        delegate: Glass {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.preferredHeight: 54
                            radius: 16

                            Column {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 14
                                spacing: 4
                                Text {
                                    text: modelData.label
                                    color: modelData.color
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 9
                                    font.letterSpacing: 1
                                }
                                Text {
                                    text: modelData.value
                                    color: Theme.fg
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                }
                            }
                        }
                    }
                }
            }

            // ── Controls row 1: transport, edit tools, export ──
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                IconBtn {
                    width: 38; height: 38; radius: 19
                    glyph: "\uf04a"; glyphSize: 13
                    tone: Theme.fg
                    onClicked: player.position = Math.max(0, player.position - 5000)
                }

                // play / pause: round accent button
                Rectangle {
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    radius: 22
                    color: Theme.accent
                    scale: playHit.pressed ? 0.94 : 1
                    Behavior on scale { NumberAnimation { duration: 80 } }
                    Text {
                        anchors.centerIn: parent
                        text: player.playbackState === MediaPlayer.PlayingState ? "\uf04c" : "\uf04b"
                        color: Theme.accentText
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 15
                    }
                    MouseArea {
                        id: playHit
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play()
                    }
                }

                IconBtn {
                    width: 38; height: 38; radius: 19
                    glyph: "\uf04e"; glyphSize: 13
                    tone: Theme.fg
                    onClicked: player.position = Math.min(player.duration, player.position + 5000)
                }

                Rectangle {
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 28
                    Layout.leftMargin: 4
                    Layout.rightMargin: 4
                    color: Qt.rgba(1, 1, 1, 0.14)
                }

                PillBtn {
                    text: "SPLIT  [S]"
                    onClicked: if (win.panel) win.panel.splitAt(player.position)
                }
                PillBtn {
                    text: win.cur && !win.cur.keep ? "RESTORE  [X]" : "CUT  [X]"
                    onClicked: if (win.panel) win.panel.toggleKeep()
                }
                PillBtn {
                    text: "JOIN  [J]"
                    onClicked: if (win.panel) win.panel.mergeNext()
                }

                Item { Layout.fillWidth: true }

                PillBtn {
                    text: "EXPORT  ↗"
                    primary: true
                    enabled: win.panel ? (!win.panel.exporting && win.panel.keptSegs().length > 0) : false
                    onClicked: if (win.panel) win.panel.doExport()
                }
            }

            // ── Controls row 2: per-segment speed, reset, exact ──
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "SPEED  [ ]"
                    color: Theme.fgDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    Layout.rightMargin: 4
                }

                Repeater {
                    model: win.panel ? win.panel.speeds : []
                    delegate: PillBtn {
                        required property var modelData
                        text: modelData + "x"
                        primary: win.cur !== null && win.cur.speed === modelData
                        onClicked: if (win.panel) win.panel.setSpeed(modelData)
                    }
                }

                Item { Layout.fillWidth: true }

                PillBtn {
                    text: "RESET"
                    onClicked: if (win.panel) win.panel.resetEdits()
                }

                CheckBox {
                    id: exactBox
                    checked: win.panel ? win.panel.exact : false
                    text: "EXACT"
                    onToggled: if (win.panel) win.panel.exact = checked
                    indicator: Rectangle {
                        x: exactBox.leftPadding
                        y: exactBox.height / 2 - height / 2
                        width: 20
                        height: 20
                        radius: 6
                        color: exactBox.checked ? Theme.accent : Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1
                        border.color: exactBox.checked ? Theme.accent : Qt.rgba(1, 1, 1, 0.18)
                        Text {
                            anchors.centerIn: parent
                            text: exactBox.checked ? "✓" : ""
                            color: Theme.accentText
                            font.pixelSize: 12
                        }
                    }
                    contentItem: Text {
                        text: exactBox.text
                        color: Theme.fgDim
                        leftPadding: exactBox.indicator.width + 8
                        verticalAlignment: Text.AlignVCenter
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                    }
                }
            }

            // ── Export state (visible, never blocks the editor) ──
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 8
                    Layout.preferredHeight: 8
                    radius: 4
                    color: win.panel && win.panel.exporting ? Theme.accent : Theme.fgDim
                }
                Text {
                    Layout.fillWidth: true
                    text: win.panel && win.panel.status !== "" ? win.panel.status
                          : (win.panel && !win.panel.isSimple()
                             ? "Multiple clips or speed changes: export re-encodes and joins kept clips in order."
                             : (win.panel && win.panel.exact
                                ? "Exact mode re-encodes for frame-accurate cuts."
                                : "Fast mode copies streams; cuts may snap to keyframes."))
                    color: win.panel && win.panel.status.indexOf("failed") >= 0 ? Theme.bad : Theme.fgDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    elide: Text.ElideMiddle
                }
                Text {
                    text: win.panel && win.panel.exporting ? "Exporting…" : "MP4 / FFMPEG"
                    color: Theme.fgDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                }
            }
        }
    }
}
