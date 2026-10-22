// File: ~/viii-shell-2/shell/GalleryPanel.qml
// Gallery, lightbox style: the picture fills the whole window, everything else floats on it
// and fades away when the mouse is still. Sharp corners, hairlines, small caps.
//   qs ipc call gallery toggle | show | hide
//   qs ipc call gallery open /path/to/folder
// Keys: Left/Right browse, Home/End jump, Enter open in swayimg, C copy path, Esc close
//       E edit mode, Ctrl+Z undo (edit mode)
// Editing needs ImageMagick 7 (the `magick` command).

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool shown: false
    property bool alive: false
    readonly property int closeMs: 0
    readonly property string mono: "JetBrainsMono Nerd Font"

    property string dir: Quickshell.env("HOME") + "/Pictures"
    property var files: []
    property int idx: 0
    readonly property var cur: files.length > 0 ? files[Math.max(0, Math.min(idx, files.length - 1))] : null

    // ── Edit state ──
    property bool editing: false
    property string tool: "transform"      // "transform" | "crop"
    property var hist: []                  // temp files, last one = current working image
    property int editN: 0
    property bool busy: false
    property real imgAspect: 1             // painted image width / height
    // Live (not yet applied) transform, previewed in QML
    property real fAngle: 0
    property real fSkewX: 0
    property real fSkewY: 0
    readonly property bool dirty: fAngle !== 0 || fSkewX !== 0 || fSkewY !== 0
    // Crop frame as fractions of the image (0..1)
    property real cropL: 0.1
    property real cropT: 0.1
    property real cropR: 0.9
    property real cropB: 0.9
    readonly property string tmp: "/tmp/viii-gallery"
    readonly property string shownPath: hist.length > 0 ? hist[hist.length - 1] : (cur ? cur.path : "")

    onShownChanged: {
        if (shown) { unload.stop(); alive = true; scan.running = true }
        else { editing = false; resetEdit(); unload.restart() }
    }
    // A different picture means a fresh edit session
    onCurChanged: resetEdit()

    Timer {
        id: unload
        interval: root.closeMs
        onTriggered: {
            root.alive = false
            Quickshell.execDetached(["rm", "-rf", root.tmp])
        }
    }

    IpcHandler {
        target: "gallery"
        function toggle(): void { root.shown = !root.shown }
        function show(): void { root.shown = true }
        function hide(): void { root.shown = false }
        function open(path: string): void {
            root.dir = path
            root.shown = true
            root.reload()
        }
    }

    function reload() { root.idx = 0; scan.running = true }
    function step(d) {
        if (files.length === 0 || editing) return
        idx = ((idx + d) % files.length + files.length) % files.length
    }
    function openExternal() { if (cur) Quickshell.execDetached(["swayimg", cur.path]) }
    function copyPath() {
        if (cur) Quickshell.execDetached(["sh", "-c", "printf %s \"$1\" | wl-copy", "sh", cur.path])
    }
    function hex(c) {
        const h = v => ("0" + Math.round(v * 255).toString(16)).slice(-2)
        return "#" + h(c.r) + h(c.g) + h(c.b)
    }
    function url(p) {
        return "file://" + p.split("/").map(encodeURIComponent).join("/")
    }
    function base(p) { return p.split("/").pop() }
    function folderName() {
        const p = dir.split("/").filter(x => x !== "")
        return p.length > 0 ? p[p.length - 1] : "/"
    }
    function pad(n, w) { return ("000" + n).slice(-w) }
    // Big number, small unit
    function sizeHtml(b, ns, us) {
        const num = v => '<span style="font-size:' + ns + 'px; font-weight:600; color:' + hex(Theme.fg) + ';">' + v + '</span>'
        const unit = v => '<span style="font-size:' + us + 'px; color:' + hex(Theme.fgDim) + ';">' + v + '</span>'
        if (b >= 1048576) return num((b / 1048576).toFixed(1)) + unit("&nbsp;MB")
        return num(Math.max(1, Math.round(b / 1024))) + unit("&nbsp;KB")
    }
    function ago(t) {
        const s = Math.max(0, Date.now() / 1000 - t)
        if (s < 3600) return Math.max(1, Math.floor(s / 60)) + "m ago"
        if (s < 86400) return Math.floor(s / 3600) + "h ago"
        if (s < 86400 * 30) return Math.floor(s / 86400) + "d ago"
        return new Date(t * 1000).toISOString().slice(0, 10)
    }

    // ───────────────────────── Editing ─────────────────────────

    function toggleEdit() {
        if (files.length === 0) return
        editing = !editing
        if (editing) { tool = "transform"; resetLive(); resetCrop() }
    }
    function resetLive() { fAngle = 0; fSkewX = 0; fSkewY = 0 }
    function resetCrop() { cropL = 0.1; cropT = 0.1; cropR = 0.9; cropB = 0.9 }
    function resetEdit() { hist = []; resetLive(); resetCrop() }
    function undo() { if (hist.length > 0 && !busy) hist = hist.slice(0, -1) }

    // 2x2 matrix [a, b, c, d] for: skew X, then skew Y, then rotate (all about the centre).
    // The QML preview and the ImageMagick export both use this, so they match.
    function affine(ang, sx, sy) {
        const r = Math.PI / 180
        const c = Math.cos(ang * r), s = Math.sin(ang * r)
        const tx = Math.tan(sx * r), ty = Math.tan(sy * r)
        return [c - s * ty,
                c * tx - s * (1 + ty * tx),
                s + c * ty,
                s * tx + c * (1 + ty * tx)]
    }
    // Preview matrix, pivoting on the item centre and shrunk so the result still fits the window
    function calcMat(ang, sx, sy, pw, ph, W, H) {
        const m = affine(ang, sx, sy)
        const hw = pw / 2, hh = ph / 2
        const ex = Math.abs(m[0]) * hw + Math.abs(m[1]) * hh
        const ey = Math.abs(m[2]) * hw + Math.abs(m[3]) * hh
        const k = (ex > 0 && ey > 0) ? Math.min(1, (W / 2) / ex, (H / 2) / ey) : 1
        const a = m[0] * k, b = m[1] * k, c = m[2] * k, d = m[3] * k
        return Qt.matrix4x4(a, b, 0, W / 2 - a * W / 2 - b * H / 2,
                            c, d, 0, H / 2 - c * W / 2 - d * H / 2,
                            0, 0, 1, 0,
                            0, 0, 0, 1)
    }
    function setAspect(a) {
        if (a <= 0) { resetCrop(); return }
        const fr = a / imgAspect            // wanted crop width / crop height, in fractions
        let w = fr >= 1 ? 1 : fr
        let h = fr >= 1 ? 1 / fr : 1
        w *= 0.9
        h *= 0.9
        cropL = (1 - w) / 2
        cropR = cropL + w
        cropT = (1 - h) / 2
        cropB = cropT + h
    }

    function nextOut() { editN = editN + 1; return tmp + "/edit-" + editN + ".png" }

    function launch(cmd, out, isSave, kind) {
        busy = true
        editProc.forPath = cur ? cur.path : ""
        editProc.out = out
        editProc.isSave = isSave
        editProc.kind = kind
        editProc.command = cmd
        editProc.running = true
    }
    // Run `magick <current image> <ops...> <out>`
    function runIm(ops, out, isSave, kind) {
        if (busy || !shownPath) return
        const script = 'mkdir -p /tmp/viii-gallery; src=$1; out=$2; shift 2; exec magick "${src}[0]" "$@" "$out"'
        launch(["sh", "-c", script, "sh", shownPath, out].concat(ops), out, isSave, kind)
    }
    function rotate90(deg) { runIm(["-rotate", String(deg)], nextOut(), false, "other") }
    function flipH() { runIm(["-flop"], nextOut(), false, "other") }
    function flipV() { runIm(["-flip"], nextOut(), false, "other") }

    function applyTransform() {
        if (!dirty) return
        const m = affine(fAngle, fSkewX, fSkewY)
        // ImageMagick order is sx,rx,ry,sy,tx,ty  ->  a,c,b,d,0,0
        const s = [m[0], m[2], m[1], m[3]].map(v => v.toFixed(8)).join(",") + ",0,0"
        runIm(["-alpha", "set", "-background", "none", "-virtual-pixel", "transparent",
               "+distort", "AffineProjection", s, "+repage"], nextOut(), false, "transform")
    }

    function applyCrop() {
        if (busy || !shownPath) return
        if (cropR - cropL < 0.01 || cropB - cropT < 0.01) return
        const q = v => String(Math.round(v * 10000))
        // Read the real pixel size with identify, then crop with integer maths (fractions are in 1/10000)
        const script = 'mkdir -p /tmp/viii-gallery; '
            + 'w=$(magick identify -format "%w" "${1}[0]"); h=$(magick identify -format "%h" "${1}[0]"); '
            + 'exec magick "${1}[0]" -crop "$((w*($5-$3)/10000))x$((h*($6-$4)/10000))+$((w*$3/10000))+$((h*$4/10000))" +repage "$2"'
        const out = nextOut()
        launch(["sh", "-c", script, "sh", shownPath, out, q(cropL), q(cropT), q(cropR), q(cropB)], out, false, "crop")
    }

    function save(overwrite) {
        if (hist.length === 0 || busy || !cur) return
        const p = cur.path
        const dot = p.lastIndexOf(".")
        const hasExt = dot > p.lastIndexOf("/") + 1
        const stem = hasExt ? p.slice(0, dot) : p
        let ext = hasExt ? p.slice(dot) : ".png"
        if (ext.toLowerCase() === ".gif") ext = ".png"      // animation is not kept
        const out = overwrite ? stem + ext : stem + "-edit-" + Math.floor(Date.now() / 1000) + ext
        // JPEG has no transparency: flatten onto black and keep quality high
        const flat = /\.jpe?g$/i.test(out)
            ? ["-background", "black", "-alpha", "remove", "-alpha", "off", "-quality", "95"] : []
        runIm(flat, out, true, "other")
    }

    Process {
        id: editProc
        property string forPath: ""
        property string out: ""
        property bool isSave: false
        property string kind: "other"
        onExited: (code, status) => {
            root.busy = false
            if (code !== 0) return
            if (isSave) { root.reload(); return }
            // Ignore the result if the user already moved to another picture
            if (!root.cur || root.cur.path !== forPath) return
            root.hist = root.hist.concat([out])
            if (kind === "transform") root.resetLive()
            else if (kind === "crop") root.resetCrop()
        }
    }

    // Text button with an underline that draws in on hover
    component Act: Item {
        id: act
        property string label: ""
        property bool strong: false
        signal clicked()
        implicitWidth: lbl.implicitWidth
        implicitHeight: 26
        Text {
            id: lbl
            anchors.verticalCenter: parent.verticalCenter
            text: act.label
            color: (act.strong || hit.containsMouse) ? Theme.accentHi : Theme.fg
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 10
            font.letterSpacing: 2
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        Rectangle {
            anchors.bottom: parent.bottom
            height: 1
            width: hit.containsMouse ? parent.width : 0
            color: Theme.accentHi
            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }
        MouseArea {
            id: hit
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: act.clicked()
        }
    }

    // Hairline slider. Click or drag to set, double-click to zero.
    component Slide: Item {
        id: sl
        property string label: ""
        property real value: 0
        property real from: -45
        property real to: 45
        signal moved(real v)
        implicitWidth: 200
        implicitHeight: 34

        Text {
            anchors.left: parent.left
            anchors.top: parent.top
            text: sl.label
            color: Theme.fgDim
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 9
            font.letterSpacing: 2.5
        }
        Text {
            anchors.right: parent.right
            anchors.top: parent.top
            text: sl.value.toFixed(1) + "°"
            color: sl.value !== 0 ? Theme.accentHi : Theme.fg
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 9
        }
        Rectangle {
            id: trk
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 7
            height: 1
            color: Qt.rgba(1, 1, 1, 0.3)
        }
        Rectangle {   // zero tick
            x: (-sl.from) / (sl.to - sl.from) * trk.width
            anchors.verticalCenter: trk.verticalCenter
            width: 1
            height: 7
            color: Qt.rgba(1, 1, 1, 0.4)
        }
        Rectangle {   // knob
            width: 9
            height: 9
            rotation: 45
            color: Theme.accentHi
            x: (sl.value - sl.from) / (sl.to - sl.from) * trk.width - width / 2
            anchors.verticalCenter: trk.verticalCenter
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            function setFrom(mx) {
                const f = Math.max(0, Math.min(1, mx / width))
                sl.moved(Math.round((sl.from + f * (sl.to - sl.from)) * 2) / 2)
            }
            onPressed: (m) => setFrom(m.x)
            onPositionChanged: (m) => { if (pressed) setFrom(m.x) }
            onDoubleClicked: sl.moved(0)
        }
    }

    Process {
        id: scan
        command: ["find", root.dir, "-maxdepth", "2", "-type", "f",
                  "(", "-iname", "*.png", "-o", "-iname", "*.jpg", "-o", "-iname", "*.jpeg",
                  "-o", "-iname", "*.webp", "-o", "-iname", "*.gif", "-o", "-iname", "*.bmp", ")",
                  "-printf", "%T@\t%s\t%p\n"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                for (const line of text.split("\n")) {
                    const p = line.split("\t")
                    if (p.length < 3) continue
                    out.push({ t: parseFloat(p[0]), size: parseInt(p[1]), path: p.slice(2).join("\t") })
                }
                out.sort((a, b) => b.t - a.t)
                root.files = out
                root.idx = 0
            }
        }
    }

    LazyLoader {
        active: root.alive

        FloatingWindow {
            id: win
            visible: root.shown
            title: "Gallery"
            implicitWidth: 880
            implicitHeight: 700
            color: "transparent"
            onVisibleChanged: if (!visible) root.shown = false

            // Overlay visibility: shows on mouse movement, hides after a pause
            property bool ui: true
            readonly property bool showUi: ui || root.files.length === 0

            Timer {
                id: hideTimer
                interval: 2600
                onTriggered: win.ui = false
            }
            Component.onCompleted: hideTimer.restart()

            Shortcut { sequence: "Home"; onActivated: if (!root.editing) root.idx = 0 }
            Shortcut { sequence: "End"; onActivated: if (!root.editing) root.idx = Math.max(0, root.files.length - 1) }
            Shortcut { sequence: "C"; onActivated: root.copyPath() }
            Shortcut { sequence: "E"; onActivated: root.toggleEdit() }
            Shortcut { sequence: "Ctrl+Z"; onActivated: root.undo() }

            Rectangle {
                id: body
                anchors.fill: parent
                color: Qt.darker(Theme.panel, 1.7)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.14)
                focus: true
                clip: true
                Keys.onEscapePressed: { if (root.editing) root.editing = false; else root.shown = false }
                Keys.onLeftPressed: root.step(-1)
                Keys.onRightPressed: root.step(1)
                Keys.onReturnPressed: root.openExternal()

                HoverHandler {
                    onPointChanged: { win.ui = true; hideTimer.restart() }
                }
                WheelHandler {
                    onWheel: (e) => { root.step(e.angleDelta.y > 0 ? -1 : 1); win.ui = true; hideTimer.restart() }
                }

                // ── The picture, edge to edge ──
                Image {
                    id: big
                    anchors.fill: parent
                    anchors.margins: 1
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: false
                    sourceSize.width: 1800
                    sourceSize.height: 1400
                    source: root.shownPath !== "" ? root.url(root.shownPath) : ""
                    opacity: status === Image.Ready ? 1 : 0
                    scale: status === Image.Ready ? 1 : 1.015
                    Behavior on opacity { NumberAnimation { duration: 0} }
                    Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

                    // Aspect of the picture as drawn, used by the crop presets
                    property real asp: paintedHeight > 0 ? paintedWidth / paintedHeight : 1
                    onAspChanged: root.imgAspect = asp

                    // Live preview of angle + skew (only on the transform tool)
                    property matrix4x4 mat: root.calcMat(
                        root.editing && root.tool === "transform" ? root.fAngle : 0,
                        root.editing && root.tool === "transform" ? root.fSkewX : 0,
                        root.editing && root.tool === "transform" ? root.fSkewY : 0,
                        paintedWidth, paintedHeight, width, height)
                    transform: Matrix4x4 { matrix: big.mat }
                }

                Text {
                    anchors.centerIn: parent
                    visible: root.files.length === 0
                    text: "NO IMAGES IN  " + root.dir
                    color: Theme.fgDim
                    font.family: root.mono
                    font.pixelSize: 11
                    font.letterSpacing: 3
                }

                // ── Crop frame, laid exactly over the drawn picture ──
                Item {
                    id: cropLayer
                    visible: root.editing && root.tool === "crop" && big.status === Image.Ready
                    x: big.x + (big.width - big.paintedWidth) / 2
                    y: big.y + (big.height - big.paintedHeight) / 2
                    width: big.paintedWidth
                    height: big.paintedHeight

                    // Dimmed outside
                    Rectangle { x: 0; y: 0; width: parent.width; height: parent.height * root.cropT; color: Qt.rgba(0, 0, 0, 0.6) }
                    Rectangle { x: 0; y: parent.height * root.cropB; width: parent.width; height: parent.height * (1 - root.cropB); color: Qt.rgba(0, 0, 0, 0.6) }
                    Rectangle { x: 0; y: parent.height * root.cropT; width: parent.width * root.cropL; height: parent.height * (root.cropB - root.cropT); color: Qt.rgba(0, 0, 0, 0.6) }
                    Rectangle { x: parent.width * root.cropR; y: parent.height * root.cropT; width: parent.width * (1 - root.cropR); height: parent.height * (root.cropB - root.cropT); color: Qt.rgba(0, 0, 0, 0.6) }

                    // The frame
                    Rectangle {
                        id: sel
                        x: parent.width * root.cropL
                        y: parent.height * root.cropT
                        width: parent.width * (root.cropR - root.cropL)
                        height: parent.height * (root.cropB - root.cropT)
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.9)

                        // Rule-of-thirds guides
                        Rectangle { x: parent.width / 3; width: 1; height: parent.height; color: Qt.rgba(1, 1, 1, 0.25) }
                        Rectangle { x: parent.width * 2 / 3; width: 1; height: parent.height; color: Qt.rgba(1, 1, 1, 0.25) }
                        Rectangle { y: parent.height / 3; height: 1; width: parent.width; color: Qt.rgba(1, 1, 1, 0.25) }
                        Rectangle { y: parent.height * 2 / 3; height: 1; width: parent.width; color: Qt.rgba(1, 1, 1, 0.25) }

                        // Corner marks
                        Repeater {
                            model: [[0, 0], [1, 0], [0, 1], [1, 1]]
                            Rectangle {
                                required property var modelData
                                width: 9
                                height: 9
                                x: sel.width * modelData[0] - 4
                                y: sel.height * modelData[1] - 4
                                color: Theme.accentHi
                            }
                        }
                    }

                    MouseArea {
                        id: cropMouse
                        anchors.fill: parent
                        property string mode: ""
                        property real sx: 0
                        property real sy: 0
                        property real l0: 0
                        property real t0: 0
                        property real r0: 0
                        property real b0: 0
                        function clamp01(v) { return Math.max(0, Math.min(1, v)) }

                        onPressed: (m) => {
                            const fx = clamp01(m.x / width), fy = clamp01(m.y / height)
                            const gx = 14 / width, gy = 14 / height
                            const L = root.cropL, T = root.cropT, R = root.cropR, B = root.cropB
                            let md = ""
                            if (fx > L - gx && fx < R + gx && fy > T - gy && fy < B + gy) {
                                // near an edge or corner -> resize that side(s)
                                if (Math.abs(fy - T) < gy) md += "t"
                                else if (Math.abs(fy - B) < gy) md += "b"
                                if (Math.abs(fx - L) < gx) md += "l"
                                else if (Math.abs(fx - R) < gx) md += "r"
                                // well inside -> move the whole frame
                                if (md === "" && fx > L && fx < R && fy > T && fy < B) md = "move"
                            }
                            if (md === "") md = "new"     // outside -> draw a fresh frame
                            mode = md
                            sx = fx; sy = fy
                            l0 = L; t0 = T; r0 = R; b0 = B
                        }
                        onPositionChanged: (m) => {
                            if (!pressed) return
                            const fx = clamp01(m.x / width), fy = clamp01(m.y / height)
                            const minS = 0.03
                            if (mode === "move") {
                                const w = r0 - l0, h = b0 - t0
                                const nl = Math.max(0, Math.min(1 - w, l0 + fx - sx))
                                const nt = Math.max(0, Math.min(1 - h, t0 + fy - sy))
                                root.cropL = nl; root.cropR = nl + w
                                root.cropT = nt; root.cropB = nt + h
                            } else if (mode === "new") {
                                root.cropL = Math.min(sx, fx); root.cropR = Math.max(sx, fx)
                                root.cropT = Math.min(sy, fy); root.cropB = Math.max(sy, fy)
                            } else {
                                if (mode.indexOf("l") >= 0) root.cropL = Math.min(fx, root.cropR - minS)
                                if (mode.indexOf("r") >= 0) root.cropR = Math.max(fx, root.cropL + minS)
                                if (mode.indexOf("t") >= 0) root.cropT = Math.min(fy, root.cropB - minS)
                                if (mode.indexOf("b") >= 0) root.cropB = Math.max(fy, root.cropT + minS)
                            }
                        }
                    }
                }

                // ── Click zones with edge arrows (off while editing) ──
                MouseArea {
                    id: leftZone
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.topMargin: 90
                    anchors.bottomMargin: 200
                    width: 110
                    hoverEnabled: true
                    visible: root.files.length > 1 && !root.editing
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.step(-1)
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 22
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\uf053"
                        color: Theme.fg
                        font.family: root.mono
                        font.pixelSize: 22
                        opacity: leftZone.containsMouse ? 1 : (win.showUi ? 0.35 : 0)
                        Behavior on opacity { NumberAnimation { duration: 0} }
                    }
                }
                MouseArea {
                    id: rightZone
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.topMargin: 90
                    anchors.bottomMargin: 200
                    width: 110
                    hoverEnabled: true
                    visible: root.files.length > 1 && !root.editing
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.step(1)
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 22
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\uf054"
                        color: Theme.fg
                        font.family: root.mono
                        font.pixelSize: 22
                        opacity: rightZone.containsMouse ? 1 : (win.showUi ? 0.35 : 0)
                        Behavior on opacity { NumberAnimation { duration: 0} }
                    }
                }

                // ── Top bar: folder + counter ──
                Item {
                    id: topBar
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 96
                    opacity: win.showUi ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 0} }

                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.72) }
                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0) }
                        }
                    }

                    ColumnLayout {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.leftMargin: 28
                        anchors.topMargin: 22
                        spacing: 2
                        Text {
                            text: "GALLERY"
                            color: Theme.accentHi
                            font.family: root.mono
                            font.pixelSize: 9
                            font.letterSpacing: 4
                        }
                        Text {
                            text: root.folderName()
                            color: Theme.fg
                            font.family: root.mono
                            font.pixelSize: 24
                            font.weight: Font.Light
                        }
                    }

                    RowLayout {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.rightMargin: 28
                        anchors.topMargin: 26
                        spacing: 22

                        Text {
                            visible: root.files.length > 0
                            textFormat: Text.RichText
                            font.family: root.mono
                            text: '<span style="font-size:24px; font-weight:300; color:' + root.hex(Theme.fg) + ';">'
                                  + root.pad(root.idx + 1, 2)
                                  + '</span><span style="font-size:11px; color:' + root.hex(Theme.fgDim) + ';">&nbsp;/&nbsp;'
                                  + root.pad(root.files.length, 2) + '</span>'
                        }
                        Act { label: "EDIT"; strong: root.editing; visible: root.files.length > 0; onClicked: root.toggleEdit() }
                        Act { label: "REFRESH"; onClicked: root.reload() }
                    }
                }

                // ── Bottom bar: details, actions, filmstrip ──
                Item {
                    id: bottomBar
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 190
                    opacity: win.showUi ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 0} }

                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
                            GradientStop { position: 0.55; color: Qt.rgba(0, 0, 0, 0.72) }
                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.88) }
                        }
                    }

                    // Info row
                    RowLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: 28
                        anchors.rightMargin: 28
                        anchors.topMargin: 38
                        spacing: 22
                        visible: root.cur !== null

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                Layout.fillWidth: true
                                text: root.cur ? root.base(root.cur.path) : ""
                                color: Theme.fg
                                font.family: root.mono
                                font.pixelSize: 15
                                elide: Text.ElideMiddle
                            }
                            Text {
                                text: root.cur ? root.ago(root.cur.t).toUpperCase() : ""
                                color: Theme.fgDim
                                font.family: root.mono
                                font.pixelSize: 9
                                font.letterSpacing: 2.5
                            }
                        }
                        Text {
                            textFormat: Text.RichText
                            font.family: root.mono
                            text: root.cur ? root.sizeHtml(root.cur.size, 22, 10) : ""
                        }
                        Act { label: "COPY PATH"; onClicked: root.copyPath() }
                        Act { label: "OPEN IN SWAYIMG  \uf08e"; strong: true; onClicked: root.openExternal() }
                    }

                    // Filmstrip: the selected frame opens up, the rest stay narrow
                    ListView {
                        id: strip
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 22
                        height: 56
                        orientation: ListView.Horizontal
                        clip: true
                        spacing: 4
                        model: root.files
                        currentIndex: root.idx
                        highlightMoveDuration: 260
                        preferredHighlightBegin: width / 2 - 42
                        preferredHighlightEnd: width / 2 + 42
                        highlightRangeMode: ListView.ApplyRange
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Item {
                            id: th
                            required property var modelData
                            required property int index
                            readonly property bool sel: index === root.idx
                            width: sel ? 84 : 36
                            height: 56
                            Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                            Image {
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: 180
                                sourceSize.height: 120
                                source: root.url(th.modelData.path)
                                opacity: th.sel ? 1 : (tHit.containsMouse ? 0.85 : 0.45)
                                Behavior on opacity { NumberAnimation { duration: 0} }
                            }
                            // Selection underline
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: 2
                                color: Theme.accentHi
                                opacity: th.sel ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 0} }
                            }
                            MouseArea {
                                id: tHit
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (!root.editing) root.idx = th.index
                                onDoubleClicked: Quickshell.execDetached(["swayimg", th.modelData.path])
                            }
                        }
                    }
                }

                // ── Edit panel ──
                Rectangle {
                    id: editPanel
                    visible: root.editing && root.files.length > 0
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: 28
                    anchors.topMargin: 104
                    width: 252
                    height: col.implicitHeight + 36
                    color: Qt.rgba(0, 0, 0, 0.66)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.14)

                    ColumnLayout {
                        id: col
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 12

                        // Tool tabs
                        RowLayout {
                            spacing: 18
                            Act { label: "TRANSFORM"; strong: root.tool === "transform"; onClicked: root.tool = "transform" }
                            Act { label: "CROP"; strong: root.tool === "crop"; onClicked: { root.tool = "crop"; root.resetCrop() } }
                        }
                        Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(1, 1, 1, 0.12) }

                        // ── Transform tool ──
                        ColumnLayout {
                            visible: root.tool === "transform"
                            Layout.fillWidth: true
                            spacing: 10

                            RowLayout {
                                spacing: 22
                                Act { label: "ROTATE L"; onClicked: root.rotate90(270) }
                                Act { label: "ROTATE R"; onClicked: root.rotate90(90) }
                            }
                            RowLayout {
                                spacing: 22
                                Act { label: "FLIP H"; onClicked: root.flipH() }
                                Act { label: "FLIP V"; onClicked: root.flipV() }
                            }

                            HairSlider { Layout.fillWidth: true; label: "ANGLE"; value: root.fAngle; from: -45; to: 45; onMoved: (v) => root.fAngle = v }
                            HairSlider { Layout.fillWidth: true; label: "SKEW X"; value: root.fSkewX; from: -45; to: 45; onMoved: (v) => root.fSkewX = v }
                            HairSlider { Layout.fillWidth: true; label: "SKEW Y"; value: root.fSkewY; from: -45; to: 45; onMoved: (v) => root.fSkewY = v }

                            RowLayout {
                                spacing: 22
                                Act { label: "APPLY"; strong: root.dirty; enabled: root.dirty; opacity: enabled ? 1 : 0.3; onClicked: root.applyTransform() }
                                Act { label: "RESET"; onClicked: root.resetLive() }
                            }
                        }

                        // ── Crop tool ──
                        ColumnLayout {
                            visible: root.tool === "crop"
                            Layout.fillWidth: true
                            spacing: 10

                            Text {
                                Layout.fillWidth: true
                                text: "DRAG THE FRAME TO MOVE IT. DRAG CORNERS OR EDGES TO RESIZE. DRAG OUTSIDE TO DRAW A NEW ONE."
                                wrapMode: Text.WordWrap
                                color: Theme.fgDim
                                font.family: root.mono
                                font.pixelSize: 9
                                font.letterSpacing: 1.5
                            }
                            RowLayout {
                                spacing: 14
                                Repeater {
                                    model: [{ l: "FREE", a: 0 }, { l: "1:1", a: 1 }, { l: "4:3", a: 4 / 3 }, { l: "16:9", a: 16 / 9 }]
                                    Act {
                                        required property var modelData
                                        label: modelData.l
                                        onClicked: root.setAspect(modelData.a)
                                    }
                                }
                            }
                            RowLayout {
                                spacing: 22
                                Act { label: "APPLY CROP"; strong: true; onClicked: root.applyCrop() }
                                Act { label: "RESET"; onClicked: root.resetCrop() }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(1, 1, 1, 0.12) }

                        // ── History + save ──
                        RowLayout {
                            spacing: 14
                            Act { label: "UNDO"; enabled: root.hist.length > 0 && !root.busy; opacity: enabled ? 1 : 0.3; onClicked: root.undo() }
                            Text {
                                text: root.busy ? "WORKING…" : (root.hist.length + (root.hist.length === 1 ? " EDIT" : " EDITS"))
                                color: Theme.fgDim
                                font.family: root.mono
                                font.pixelSize: 9
                                font.letterSpacing: 2
                            }
                        }
                        RowLayout {
                            spacing: 22
                            Act { label: "SAVE COPY"; strong: true; enabled: root.hist.length > 0 && !root.busy; opacity: enabled ? 1 : 0.3; onClicked: root.save(false) }
                            Act { label: "REPLACE"; enabled: root.hist.length > 0 && !root.busy; opacity: enabled ? 1 : 0.3; onClicked: root.save(true) }
                        }
                    }
                }
            }
        }
    }
}
