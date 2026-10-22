import QtQuick
import Quickshell
import Quickshell.Io

// Lightweight controller: state, IPC and ffmpeg only.
// TrimWindow (including QtMultimedia/player decoders) is created only
// when a video is opened. No QtMultimedia here.
//
// Edit model: the video is a list of contiguous segments covering the whole
// clip. Each segment is { s, e, speed, keep } (times in ms). Split at the
// playhead, cut the parts you don't want, change speed per segment; export
// joins all kept segments in order.
Scope {
    id: root

    property string file: ""
    property bool exact: false
    property string status: ""
    property bool exporting: ff.running
    property var win: null   // the open TrimWindow, or null when closed

    property var segments: []     // always reassign (never mutate) to notify bindings
    property int sel: -1          // selected segment index
    property real duration: 0
    property bool hasAudio: true  // set by TrimWindow from the player

    readonly property var speeds: [0.25, 0.5, 1, 1.5, 2, 4, 8]

    // 83250 ms -> "01:23.250"
    function fmt(ms) {
        var t = Math.max(0, Math.floor(ms))
        var m = Math.floor(t / 60000)
        var s = Math.floor((t % 60000) / 1000)
        return String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0")
             + "." + String(t % 1000).padStart(3, "0")
    }

    // video.mp4 -> video_trim.mp4 (saved next to the original)
    function outPath() {
        return file.replace(/(\.[^./]+)$/, "_trim$1")
    }

    function closeWin() {
        if (win) {
            var w = win
            win = null          // clear first so onVisibleChanged can't re-enter
            w.destroy()
        }
    }

    function openFile(p) {
        closeWin()
        file = p
        segments = []
        sel = -1
        duration = 0
        status = ""
        // Compiled only now, so QtMultimedia loads on first open, not at login
        var c = Qt.createComponent("TrimWindow.qml")
        if (c.status === Component.Ready)
            win = c.createObject(root, { panel: root })
        else
            console.log("TrimWindow error:", c.errorString())
    }

    // ───────────── Segment editing ─────────────

    function initSegments(d) {
        duration = d
        segments = [{ s: 0, e: d, speed: 1, keep: true }]
        sel = 0
    }

    function segIndexAt(ms) {
        if (segments.length === 0) return -1
        for (var i = 0; i < segments.length; i++)
            if (ms >= segments[i].s && ms < segments[i].e) return i
        return segments.length - 1   // at/after the very end
    }

    function selectAt(ms) { sel = segIndexAt(ms) }

    function splitAt(ms) {
        var i = segIndexAt(ms)
        if (i < 0) return
        var g = segments[i]
        if (ms - g.s < 100 || g.e - ms < 100) return   // too close to an edge
        var a = segments.slice()
        a.splice(i, 1,
            { s: g.s, e: ms,  speed: g.speed, keep: g.keep },
            { s: ms,  e: g.e, speed: g.speed, keep: g.keep })
        segments = a
        sel = i + 1
    }

    function toggleKeep() {
        if (sel < 0 || sel >= segments.length) return
        var a = segments.slice()
        var g = a[sel]
        a[sel] = { s: g.s, e: g.e, speed: g.speed, keep: !g.keep }
        segments = a
    }

    function setSpeed(sp) {
        if (sel < 0 || sel >= segments.length) return
        var a = segments.slice()
        var g = a[sel]
        a[sel] = { s: g.s, e: g.e, speed: sp, keep: g.keep }
        segments = a
    }

    function stepSpeed(d) {
        if (sel < 0 || sel >= segments.length) return
        var i = speeds.indexOf(segments[sel].speed)
        if (i < 0) i = 2
        setSpeed(speeds[Math.max(0, Math.min(speeds.length - 1, i + d))])
    }

    // Merge selected segment with the next one (undo a split). Takes the
    // selected segment's speed/keep state.
    function mergeNext() {
        if (sel < 0 || sel >= segments.length - 1) return
        var a = segments.slice()
        var g = a[sel], n = a[sel + 1]
        a.splice(sel, 2, { s: g.s, e: n.e, speed: g.speed, keep: g.keep })
        segments = a
    }

    // "I": drop everything before the playhead
    function cutBefore(ms) {
        splitAt(ms)
        var a = segments.map(function (g) {
            return g.e <= ms + 1 ? { s: g.s, e: g.e, speed: g.speed, keep: false } : g
        })
        segments = a
        sel = segIndexAt(ms + 1)
    }

    // "O": drop everything after the playhead
    function cutAfter(ms) {
        splitAt(ms)
        var a = segments.map(function (g) {
            return g.s >= ms - 1 ? { s: g.s, e: g.e, speed: g.speed, keep: false } : g
        })
        segments = a
        sel = segIndexAt(ms - 1)
    }

    function resetEdits() {
        if (duration > 0) initSegments(duration)
    }

    function keptSegs() {
        return segments.filter(function (g) { return g.keep })
    }

    // Output length in ms, accounting for cuts and speed
    function outMs() {
        var t = 0
        for (var i = 0; i < segments.length; i++) {
            var g = segments[i]
            if (g.keep) t += (g.e - g.s) / g.speed
        }
        return t
    }

    // One kept segment at 1x = old fast path (stream copy possible)
    function isSimple() {
        var k = keptSegs()
        return k.length === 1 && k[0].speed === 1
    }

    // atempo only accepts 0.5..2.0 on older ffmpeg, so chain it
    function atempoChain(sp) {
        if (sp === 1) return "anull"
        var parts = []
        var r = sp
        while (r > 2.0 + 1e-6) { parts.push("atempo=2.0"); r /= 2.0 }
        while (r < 0.5 - 1e-6) { parts.push("atempo=0.5"); r /= 0.5 }
        parts.push("atempo=" + r.toFixed(4))
        return parts.join(",")
    }

    // ───────────── Export ─────────────

    function doExport() {
        var k = keptSegs()
        if (k.length === 0) { status = "Nothing to export (everything is cut)"; return }

        var cmd
        if (isSimple()) {
            var g0 = k[0]
            var ss = (g0.s / 1000).toFixed(3)
            var dur = ((g0.e - g0.s) / 1000).toFixed(3)
            cmd = ["ffmpeg", "-y", "-ss", ss, "-i", file, "-t", dur]
            if (exact)
                cmd = cmd.concat(["-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-c:a", "aac"])
            else
                cmd = cmd.concat(["-c", "copy"])   // instant + lossless, snaps to keyframes
            cmd.push(outPath())
        } else {
            // Multi-segment and/or speed changes: trim each piece, retime it,
            // then concat. Always re-encodes.
            var f = []
            var labels = ""
            for (var i = 0; i < k.length; i++) {
                var g = k[i]
                var a0 = (g.s / 1000).toFixed(3)
                var a1 = (g.e / 1000).toFixed(3)
                f.push("[0:v]trim=start=" + a0 + ":end=" + a1
                       + ",setpts=(PTS-STARTPTS)/" + g.speed + "[v" + i + "]")
                if (hasAudio)
                    f.push("[0:a]atrim=start=" + a0 + ":end=" + a1
                           + ",asetpts=PTS-STARTPTS," + atempoChain(g.speed) + "[a" + i + "]")
                labels += "[v" + i + "]" + (hasAudio ? "[a" + i + "]" : "")
            }
            f.push(labels + "concat=n=" + k.length + ":v=1:a=" + (hasAudio ? 1 : 0)
                   + "[v]" + (hasAudio ? "[a]" : ""))

            cmd = ["ffmpeg", "-y", "-i", file, "-filter_complex", f.join(";"), "-map", "[v]"]
            if (hasAudio) cmd = cmd.concat(["-map", "[a]"])
            cmd = cmd.concat(["-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-pix_fmt", "yuv420p"])
            if (hasAudio) cmd = cmd.concat(["-c:a", "aac"])
            cmd.push(outPath())
        }

        ff.command = cmd
        status = "Exporting..."
        ff.running = true
    }

    Process {
        id: ff
        onExited: (code, st) => {
            root.status = code === 0 ? "Saved: " + root.outPath() : "ffmpeg failed (code " + code + ")"
        }
    }

    // File picker, only runs when you press the keybind with nothing open
    Process {
        id: picker
        command: ["zenity", "--file-selection", "--title=Pick a video"]
        stdout: StdioCollector {
            onStreamFinished: {
                var p = text.trim()
                if (p !== "") root.openFile(p)
            }
        }
    }

    // qs ipc call trim toggle        -> pick a file, or close if open
    // qs ipc call trim open <path>   -> open a specific file
    IpcHandler {
        target: "trim"
        function toggle(): void {
            if (root.win) root.closeWin()
            else picker.running = true
        }
        function open(path: string): void {
            root.openFile(path)
        }
    }
}
