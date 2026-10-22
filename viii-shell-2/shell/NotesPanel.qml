// File: ~/viii-shell-2/shell/NotesPanel.qml
// Notes, glass style. Sidebar (search + list) on the left, editor on the right.
//   qs ipc call notes toggle | show | hide | newNote | daily
// Keys: Ctrl+N new, Ctrl+S save, Ctrl+F search, Ctrl+D delete (press twice), Esc close

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

    property string dir: Quickshell.env("HOME") + "/Documents/Notes"
    property var allNotes: []
    property string curPath: ""
    property bool dirty: false
    property bool endNext: false
    property bool armed: false
    property string query: ""
    property var matches: null
    readonly property var curEntry: allNotes.find(n => n.path === curPath) || null

    onShownChanged: {
        if (shown) { unload.stop(); alive = true; listProc.running = true }
        else unload.restart()
    }
    Timer { id: unload; interval: root.closeMs; onTriggered: root.alive = false }
    Timer { id: armTimer; interval: 2500; onTriggered: root.armed = false }
    Timer { id: searchTimer; interval: 200; onTriggered: root.runSearch() }

    onQueryChanged: {
        matches = null
        rebuild()
        if (query.trim() !== "") searchTimer.restart()
    }

    IpcHandler {
        target: "notes"
        function toggle(): void { root.shown = !root.shown }
        function show(): void { root.shown = true }
        function hide(): void { root.shown = false }
        function newNote(): void {
            root.shown = true
            root.createNote(root.dir + "/note-" + root.stamp() + ".md", "")
        }
        function daily(): void {
            root.shown = true
            root.createNote(root.dir + "/daily-" + root.isoDate() + ".md", "# " + root.isoDate() + "\n\n")
        }
    }

    ListModel { id: noteModel }

    // ── helpers ──
    function pad(n) { return (n < 10 ? "0" : "") + n }
    function isoDate() {
        const d = new Date()
        return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
    }
    function stamp() {
        const d = new Date()
        return isoDate().replace(/-/g, "") + "-" + pad(d.getHours()) + pad(d.getMinutes()) + pad(d.getSeconds())
    }
    function hex(c) {
        const h = v => ("0" + Math.round(v * 255).toString(16)).slice(-2)
        return "#" + h(c.r) + h(c.g) + h(c.b)
    }
    // Big number, small unit
    function statHtml(v, u, ns, us, nc) {
        return '<span style="font-size:' + ns + 'px; font-weight:600; color:' + hex(nc) + ';">' + v + '</span>'
             + '<span style="font-size:' + us + 'px; color:' + hex(Theme.fgDim) + ';">&nbsp;' + u + '</span>'
    }
    function ago(t) {
        const s = Math.max(0, Date.now() / 1000 - t)
        if (s < 60) return "now"
        if (s < 3600) return Math.floor(s / 60) + "m"
        if (s < 86400) return Math.floor(s / 3600) + "h"
        if (s < 86400 * 30) return Math.floor(s / 86400) + "d"
        return new Date(t * 1000).toISOString().slice(5, 10)
    }
    function clean(s) {
        const r = s.replace(/^[#>\-\*\s]+/, "").trim().slice(0, 80)
        return r === "" ? "Untitled" : r
    }

    // ── model ──
    function rebuild() {
        const q = query.trim().toLowerCase()
        const rows = []
        for (const n of allNotes) {
            if (q !== "") {
                const hit = n.title.toLowerCase().includes(q)
                    || n.preview.toLowerCase().includes(q)
                    || (matches !== null && matches[n.path] === true)
                if (!hit) continue
            }
            rows.push({ notePath: n.path, noteTitle: n.title, notePreview: n.preview, noteT: n.t })
        }
        if (noteModel.count === rows.length) {
            for (let i = 0; i < rows.length; i++) noteModel.set(i, rows[i])
        } else {
            noteModel.clear()
            for (const r of rows) noteModel.append(r)
        }
    }

    function parseList(text) {
        const out = []
        for (const line of text.split("\n")) {
            const p = line.split("\t")
            if (p.length < 2 || p[1] === "") continue
            out.push({
                path: dir + "/" + p[1],
                t: parseFloat(p[0]) || 0,
                title: clean(p[2] || ""),
                preview: (p[3] || "").trim()
            })
        }
        out.sort((a, b) => b.t - a.t)
        allNotes = out
        if (curPath === "" && out.length > 0) curPath = out[0].path
        rebuild()
    }

    // Update the sidebar entry for a note we just saved (no rescan, no scroll jump)
    function touchEntry(path, text) {
        const lines = text.split("\n").filter(l => l.trim() !== "")
        const list = allNotes.slice()
        let e = list.find(n => n.path === path)
        if (!e) { e = { path: path }; list.push(e) }
        e.title = clean(lines.length > 0 ? lines[0] : "")
        e.preview = lines.length > 1 ? lines[1].trim().slice(0, 90) : ""
        e.t = Date.now() / 1000
        list.sort((a, b) => b.t - a.t)
        allNotes = list
        rebuild()
    }

    function flush() { if (loader.item) loader.item.saveNow() }

    function openNote(path) {
        if (path === curPath) return
        flush()
        endNext = false
        armed = false
        curPath = path
    }

    function createNote(path, seed) {
        flush()
        creator.notePath = path
        creator.seed = seed
        creator.running = true
    }

    function removeCurrent() {
        if (curPath === "") return
        dirty = false
        deleter.notePath = curPath
        deleter.running = true
    }

    function runSearch() {
        if (query.trim() === "") return
        if (searchProc.running) { searchProc.again = true; return }
        searchProc.again = false
        searchProc.running = true
    }

    // ── processes ──
    Process {
        id: listProc
        command: ["sh", "-c",
            'mkdir -p "$1"; cd "$1" 2>/dev/null || exit 0; '
            + 'for f in *.md; do [ -f "$f" ] || continue; '
            + 't=$(stat -c %Y "$f"); '
            + 'l1=$(grep -m1 -v "^[[:space:]]*$" "$f" | cut -c1-80 | tr "\\t" " "); '
            + 'l2=$(grep -v "^[[:space:]]*$" "$f" | sed -n 2p | cut -c1-90 | tr "\\t" " "); '
            + 'printf "%s\\t%s\\t%s\\t%s\\n" "$t" "$f" "$l1" "$l2"; done',
            "sh", root.dir]
        stdout: StdioCollector { onStreamFinished: root.parseList(text) }
    }

    Process {
        id: searchProc
        property bool again: false
        command: ["sh", "-c", 'grep -lFi -- "$1" "$2"/*.md 2>/dev/null', "sh", root.query.trim(), root.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = {}
                for (const l of text.split("\n")) if (l !== "") m[l] = true
                root.matches = m
                root.rebuild()
            }
        }
        onExited: if (again) root.runSearch()
    }

    Process {
        id: creator
        property string notePath: ""
        property string seed: ""
        command: ["sh", "-c", 'mkdir -p "$1"; [ -e "$2" ] || printf "%s" "$3" > "$2"',
                  "sh", root.dir, notePath, seed]
        onExited: {
            root.dirty = false
            root.endNext = true
            root.armed = false
            root.curPath = creator.notePath
            listProc.running = true
        }
    }

    Process {
        id: deleter
        property string notePath: ""
        command: ["sh", "-c", 'mkdir -p "$1/.trash" && mv -- "$2" "$1/.trash/"',
                  "sh", root.dir, notePath]
        onExited: {
            const gone = deleter.notePath
            root.allNotes = root.allNotes.filter(n => n.path !== gone)
            root.curPath = root.allNotes.length > 0 ? root.allNotes[0].path : ""
            root.rebuild()
        }
    }

    // ── window ──
    LazyLoader {
        id: loader
        active: root.alive

        FloatingWindow {
            id: win
            visible: root.shown
            title: "Notes"
            implicitWidth: 920
            implicitHeight: 620
            color: "transparent"

            property bool loading: false

            readonly property int words: {
                const t = editor.text.trim()
                return t === "" ? 0 : t.split(/\s+/).length
            }

            function saveNow() {
                if (!root.dirty || root.curPath === "") return
                fv.setText(editor.text)
                root.dirty = false
                root.touchEntry(root.curPath, editor.text)
            }

            Component.onCompleted: editor.forceActiveFocus()
            onVisibleChanged: {
                if (!visible) { saveNow(); root.shown = false }
                else editor.forceActiveFocus()
            }

            Shortcut { sequence: "Ctrl+N"; onActivated: root.createNote(root.dir + "/note-" + root.stamp() + ".md", "") }
            Shortcut { sequence: "Ctrl+S"; onActivated: win.saveNow() }
            Shortcut { sequence: "Ctrl+F"; onActivated: search.forceActiveFocus() }
            Shortcut {
                sequence: "Ctrl+D"
                onActivated: {
                    if (root.curPath === "") return
                    if (!root.armed) { root.armed = true; armTimer.restart() }
                    else { root.armed = false; root.removeCurrent() }
                }
            }

            Timer { id: saveTimer; interval: 700; onTriggered: win.saveNow() }

            FileView {
                id: fv
                path: root.curPath
                blockWrites: true
                onLoaded: {
                    win.loading = true
                    editor.text = fv.text()
                    win.loading = false
                    editor.cursorPosition = root.endNext ? editor.text.length : 0
                    root.endNext = false
                    editor.forceActiveFocus()
                }
            }

            Connections {
                target: root
                function onCurPathChanged() {
                    if (root.curPath === "") {
                        win.loading = true
                        editor.text = ""
                        win.loading = false
                    }
                }
            }

            // Glass body
            Rectangle {
                anchors.fill: parent
                color: Qt.alpha(Theme.panel, 0.82)
                focus: true
                Keys.onEscapePressed: root.shown = false

                // Specular sheen across the top
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
                        GradientStop { position: 0.25; color: Qt.rgba(1, 1, 1, 0.0) }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 0

                    // ───────── Sidebar ─────────
                    ColumnLayout {
                        Layout.preferredWidth: 270
                        Layout.fillHeight: true
                        spacing: 12

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Text {
                                text: "Notes"
                                color: Theme.fg
                                font.family: root.mono
                                font.pixelSize: 18
                                font.weight: Font.DemiBold
                            }
                            Text {
                                Layout.fillWidth: true
                                text: root.allNotes.length
                                color: Theme.fgDim
                                font.family: root.mono
                                font.pixelSize: 11
                            }
                            IconBtn {
                                glyph: "\uf067"
                                tone: Theme.accentHi
                                onClicked: root.createNote(root.dir + "/note-" + root.stamp() + ".md", "")
                            }
                        }

                        // Search pill
                        Glass {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 38
                            radius: 19

                            // Focus ring
                            Rectangle {
                                anchors.fill: parent
                                radius: 19
                                color: "transparent"
                                border.width: 1
                                border.color: Theme.accent
                                opacity: search.activeFocus ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 0} }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 8
                                Text {
                                    text: "\uf002"
                                    color: Theme.fgDim
                                    font.family: root.mono
                                    font.pixelSize: 11
                                }
                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: search.text === ""
                                        text: "Search notes"
                                        color: Theme.fgDim
                                        font.family: root.mono
                                        font.pixelSize: 11
                                    }
                                    TextInput {
                                        id: search
                                        anchors.fill: parent
                                        verticalAlignment: TextInput.AlignVCenter
                                        color: Theme.fg
                                        font.family: root.mono
                                        font.pixelSize: 12
                                        clip: true
                                        onTextChanged: root.query = text
                                        onAccepted: {
                                            if (noteModel.count > 0) root.openNote(noteModel.get(0).notePath)
                                            editor.forceActiveFocus()
                                        }
                                        Keys.onEscapePressed: (e) => {
                                            if (text !== "") { text = ""; e.accepted = true }
                                        }
                                    }
                                }
                            }
                        }

                        ListView {
                            id: list
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 6
                            model: noteModel
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: Item {
                                id: it
                                required property string notePath
                                required property string noteTitle
                                required property string notePreview
                                required property real noteT
                                readonly property bool sel: notePath === root.curPath

                                width: list.width
                                height: 64

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 16
                                    color: it.sel
                                        ? Qt.alpha(Theme.accent, 0.22)
                                        : (hit.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(1, 1, 1, 0.04))
                                    border.width: it.sel ? 1 : 0
                                    border.color: Theme.accent
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 12
                                    anchors.topMargin: 9
                                    anchors.bottomMargin: 9
                                    spacing: 3

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Text {
                                            Layout.fillWidth: true
                                            text: it.noteTitle
                                            color: it.sel ? Theme.accentHi : Theme.fg
                                            font.family: root.mono
                                            font.pixelSize: 13
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: root.ago(it.noteT)
                                            color: Theme.fgDim
                                            font.family: root.mono
                                            font.pixelSize: 9
                                        }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: it.notePreview !== "" ? it.notePreview : "Empty note"
                                        color: Theme.fgDim
                                        font.family: root.mono
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                    }
                                }

                                MouseArea {
                                    id: hit
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.openNote(it.notePath); editor.forceActiveFocus() }
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: noteModel.count === 0
                                text: root.query.trim() !== "" ? "No matches" : "No notes yet"
                                color: Theme.fgDim
                                font.family: root.mono
                                font.pixelSize: 11
                            }
                        }
                    }

                    // Divider
                    Rectangle {
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        Layout.leftMargin: 18
                        Layout.rightMargin: 18
                        color: Qt.rgba(1, 1, 1, 0.10)
                    }

                    // ───────── Editor ─────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 12
                        visible: root.curPath !== ""

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Text {
                                Layout.fillWidth: true
                                text: root.curEntry ? "Edited " + root.ago(root.curEntry.t) + (root.ago(root.curEntry.t) === "now" ? "" : " ago") : ""
                                color: Theme.fgDim
                                font.family: root.mono
                                font.pixelSize: 11
                            }

                            Rectangle {
                                Layout.preferredWidth: 7
                                Layout.preferredHeight: 7
                                Layout.alignment: Qt.AlignVCenter
                                radius: 4
                                color: root.dirty ? Theme.fgDim : Theme.accent
                                Behavior on color { ColorAnimation { duration: 160 } }
                            }
                            Text {
                                text: root.dirty ? "Editing" : "Saved"
                                color: root.dirty ? Theme.fgDim : Theme.accentHi
                                font.family: root.mono
                                font.pixelSize: 11
                            }

                            Rectangle {
                                Layout.preferredWidth: root.armed ? 96 : 34
                                Layout.preferredHeight: 34
                                radius: 17
                                color: root.armed
                                    ? Qt.rgba(Theme.bad.r, Theme.bad.g, Theme.bad.b, 0.25)
                                    : (delHit.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06))
                                border.width: 1
                                border.color: root.armed ? Theme.bad : Qt.rgba(1, 1, 1, 0.12)
                                Behavior on Layout.preferredWidth { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                Text {
                                    anchors.centerIn: parent
                                    text: root.armed ? "\uf1f8  Confirm" : "\uf1f8"
                                    color: root.armed || delHit.containsMouse ? Theme.bad : Theme.fgDim
                                    font.family: root.mono
                                    font.pixelSize: 11
                                }
                                MouseArea {
                                    id: delHit
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (!root.armed) { root.armed = true; armTimer.restart() }
                                        else { root.armed = false; root.removeCurrent() }
                                    }
                                }
                            }
                        }

                        // Editor card
                        Glass {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 20

                            Text {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.leftMargin: 20
                                anchors.topMargin: 18
                                visible: editor.text === ""
                                text: "Start typing…"
                                color: Theme.fgDim
                                opacity: 0.6
                                font.family: root.mono
                                font.pixelSize: 14
                            }

                            Flickable {
                                id: flick
                                anchors.fill: parent
                                anchors.margins: 14
                                clip: true
                                contentWidth: width
                                contentHeight: Math.max(editor.implicitHeight, height)
                                boundsBehavior: Flickable.StopAtBounds

                                function ensureVisible(r) {
                                    if (contentY >= r.y) contentY = r.y
                                    else if (contentY + height <= r.y + r.height + 8)
                                        contentY = r.y + r.height + 8 - height
                                }

                                TextEdit {
                                    id: editor
                                    width: flick.width - 10
                                    height: Math.max(implicitHeight, flick.height)
                                    padding: 6
                                    wrapMode: TextEdit.Wrap
                                    color: Theme.fg
                                    selectionColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
                                    selectedTextColor: Theme.fg
                                    selectByMouse: true
                                    persistentSelection: true
                                    tabStopDistance: 28
                                    font.family: root.mono
                                    font.pixelSize: 14
                                    onCursorRectangleChanged: flick.ensureVisible(cursorRectangle)
                                    onTextChanged: {
                                        if (win.loading || root.curPath === "") return
                                        root.dirty = true
                                        saveTimer.restart()
                                    }
                                }
                            }

                            Rectangle {
                                anchors.right: parent.right
                                anchors.rightMargin: 6
                                width: 3
                                radius: 2
                                color: Theme.fgDim
                                opacity: 0.5
                                visible: flick.contentHeight > flick.height + 1
                                height: Math.max(24, (flick.height + 28) * flick.height / Math.max(1, flick.contentHeight))
                                y: 14 + flick.contentY / Math.max(1, flick.contentHeight - flick.height) * (flick.height - height)
                            }
                        }

                        // Stats: big numbers, small units
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 24

                            Text {
                                textFormat: Text.RichText
                                font.family: root.mono
                                text: root.statHtml(win.words, win.words === 1 ? "word" : "words", 30, 12, Theme.accentHi)
                            }
                            Text {
                                textFormat: Text.RichText
                                font.family: root.mono
                                text: root.statHtml(editor.text.length, "chars", 20, 10, Theme.fg)
                            }
                            Text {
                                textFormat: Text.RichText
                                font.family: root.mono
                                text: root.statHtml(editor.lineCount, "lines", 20, 10, Theme.fg)
                            }
                            Text {
                                textFormat: Text.RichText
                                font.family: root.mono
                                text: root.statHtml(Math.max(1, Math.ceil(win.words / 200)), "min read", 20, 10, Theme.fg)
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: "^N new   ^F search   ^D delete"
                                color: Theme.fgDim
                                font.family: root.mono
                                font.pixelSize: 9
                            }
                        }
                    }

                    // Empty state
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.curPath === ""
                        spacing: 10
                        Item { Layout.fillHeight: true }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "\uf249"
                            color: Theme.fgDim
                            opacity: 0.5
                            font.family: root.mono
                            font.pixelSize: 56
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Nothing open"
                            color: Theme.fgDim
                            font.family: root.mono
                            font.pixelSize: 13
                        }
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: emptyText.implicitWidth + 32
                            Layout.preferredHeight: 36
                            radius: 18
                            color: emptyHit.containsMouse ? Theme.accentHi : Theme.accent
                            Text {
                                id: emptyText
                                anchors.centerIn: parent
                                text: "New note"
                                color: Theme.accentText
                                font.family: root.mono
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                            MouseArea {
                                id: emptyHit
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.createNote(root.dir + "/note-" + root.stamp() + ".md", "")
                            }
                        }
                        Item { Layout.fillHeight: true }
                    }
                }
            }
        }
    }
}
