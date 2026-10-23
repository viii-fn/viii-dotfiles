// File: ~/viii-shell-2/shell/LauncherPage.qml
// The dial launcher, grown inside the notch. Loaded by Notch.qml, which sets `n`.
//   qsctl omni toggle   (or: qs ipc call omni toggle)
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    property var n: null
    property string query: ""

    property var apps: {
        const q = query.trim().toLowerCase()
        const list = DesktopEntries.applications.values.filter(e => {
            if (e.noDisplay) return false
            if (q === "") return true
            return e.name.toLowerCase().includes(q)
                || (e.genericName || "").toLowerCase().includes(q)
        })
        list.sort((a, b) => {
            if (q !== "") {
                const sa = a.name.toLowerCase().startsWith(q) ? 0 : 1
                const sb = b.name.toLowerCase().startsWith(q) ? 0 : 1
                if (sa !== sb) return sa - sb
            }
            return a.name.localeCompare(b.name)
        })
        return list
    }

    Component.onCompleted: input.forceActiveFocus()

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.bottomMargin: 16
        anchors.topMargin: 0
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Text {
                text: "Launcher"
                color: Theme.fg
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 16
                font.weight: Font.DemiBold
                Layout.fillWidth: true
            }
            Text {
                text: root.apps.length + " apps"
                color: Theme.fgDim
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 10
            }
        }

        // ── The dial ──
        Item {
            id: dial
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 480
            Layout.preferredHeight: 480

            readonly property real rad: 176
            property real pos: -4
            property int idx: 0
            property bool dragging: false
            property real press: 0
            readonly property int n: root.apps.length
            readonly property int sel: n > 0 ? ((idx % n) + n) % n : -1
            readonly property var cur: n > 0 ? root.apps[sel] : null

            Behavior on pos {
                enabled: !dial.dragging
                SpringAnimation { spring: 6; damping: 0.24; epsilon: 0.002 }
            }
            Component.onCompleted: pos = idx

            function go(i) { idx = i; pos = i }
            function activate() { if (cur && !slam.running) slam.start() }
            function doLaunch() {
                if (cur) cur.execute()
                press = 0
                if (root.n) root.n.closeAll()
            }

            SequentialAnimation {
                id: slam
                NumberAnimation { target: dial; property: "press"; to: 1; duration: 110; easing.type: Easing.InQuad }
                ScriptAction { script: dial.doLaunch() }
            }

            Connections {
                target: root
                function onQueryChanged() { dial.go(0) }
            }

            // Rotating tick ring
            Repeater {
                model: 48
                Item {
                    required property int index
                    anchors.centerIn: parent
                    width: 1
                    height: 1
                    rotation: index * 7.5 - dial.pos * 30
                    Rectangle {
                        readonly property real h: index % 4 === 0 ? 10 : 5
                        x: -1
                        y: -(dial.rad + 36 + h)
                        width: 2
                        height: h
                        radius: 1
                        color: index % 4 === 0 ? Theme.fgDim : Theme.line
                    }
                }
            }

            Rectangle {
                x: dial.width / 2 - 8
                y: 8
                width: 16
                height: 5
                radius: 2.5
                color: Theme.accent
            }

            Rectangle {
                anchors.centerIn: parent
                width: dial.rad * 2
                height: dial.rad * 2
                radius: dial.rad
                color: "transparent"
                border.width: 1
                border.color: Theme.line
            }

            MouseArea {
                id: drag
                anchors.fill: parent
                property real lastA: 0
                property real vel: 0
                property real wheelAcc: 0
                function ang(m) {
                    return Math.atan2(m.y - height / 2, m.x - width / 2) * 180 / Math.PI
                }
                onPressed: (m) => { dial.dragging = true; lastA = ang(m); vel = 0 }
                onPositionChanged: (m) => {
                    if (!pressed) return
                    const a = ang(m)
                    let d = a - lastA
                    if (d > 180) d -= 360
                    if (d < -180) d += 360
                    lastA = a
                    vel = d
                    dial.pos -= d / 30
                }
                onReleased: {
                    dial.dragging = false
                    dial.go(Math.round(dial.pos - vel / 30 * 4))
                }
                onWheel: (w) => {
                    wheelAcc += w.angleDelta.y
                    while (wheelAcc >= 120) { wheelAcc -= 120; dial.go(dial.idx - 1) }
                    while (wheelAcc <= -120) { wheelAcc += 120; dial.go(dial.idx + 1) }
                }
            }

            // App slots on the ring
            Repeater {
                model: 13

                Item {
                    id: slot
                    required property int index
                    readonly property int s: index - 6
                    readonly property int base: Math.round(dial.pos)
                    readonly property real off: base + s - dial.pos
                    readonly property int cnt: dial.n
                    readonly property int ai: cnt > 0 ? (((base + s) % cnt) + cnt) % cnt : -1
                    readonly property var entry: ai >= 0 ? root.apps[ai] : null
                    readonly property bool uniq: cnt > 0 && Math.abs(s) <= (cnt - 1) / 2
                    readonly property bool isSel: Math.abs(off) < 0.5
                    readonly property real a: (-90 + off * 30) * Math.PI / 180

                    width: 56
                    height: 56
                    x: dial.width / 2 + dial.rad * Math.cos(a) - width / 2
                    y: dial.height / 2 + dial.rad * Math.sin(a) - height / 2
                    scale: 1 + 0.45 * Math.max(0, 1 - Math.abs(off))
                    opacity: uniq ? Math.max(0, Math.min(1, (5.0 - Math.abs(off)) / 1.5)) : 0
                    visible: opacity > 0.01
                    z: isSel ? 2 : 1

                    Rectangle {
                        anchors.fill: parent
                        radius: 18
                        color: slot.isSel ? Qt.alpha(Theme.accent, 0.30) : Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1
                        border.color: slot.isSel ? Qt.alpha(Theme.accent, 0.55) : Qt.rgba(1, 1, 1, 0.10)
                    }
                    Image {
                        id: ico
                        anchors.centerIn: parent
                        width: 30
                        height: 30
                        sourceSize.width: 64
                        sourceSize.height: 64
                        fillMode: Image.PreserveAspectFit
                        source: slot.entry ? Quickshell.iconPath(slot.entry.icon, true) : ""
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: ico.status !== Image.Ready
                        text: slot.entry ? slot.entry.name.charAt(0).toUpperCase() : ""
                        color: slot.isSel ? Theme.accentHi : Theme.fgDim
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (slot.isSel) dial.activate()
                            else dial.go(dial.idx + Math.round(slot.off))
                        }
                    }
                }
            }

            // Center core
            Item {
                id: core
                anchors.centerIn: parent
                width: 210
                height: 210

                transform: Scale {
                    origin.x: core.width / 2
                    origin.y: core.height / 2
                    xScale: 1 + 0.05 * dial.press
                    yScale: 1 - 0.12 * dial.press
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 105
                    color: "transparent"
                    border.width: 3
                    border.color: Theme.accent
                    opacity: dial.press * 0.9
                    scale: 1 + dial.press * 0.5
                }
                Rectangle {
                    anchors.fill: parent
                    radius: 105
                    color: Qt.alpha(Theme.surface, 0.60)
                    border.width: 1.5
                    border.color: dial.press > 0.05 ? Theme.accentHi : Qt.alpha(Theme.accent, 0.50)
                }
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: 104
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.12) }
                        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.0) }
                    }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 4

                    Item {
                        id: coreIcon
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 84
                        Layout.preferredHeight: 84

                        Image {
                            id: bigIco
                            anchors.fill: parent
                            sourceSize.width: 128
                            sourceSize.height: 128
                            fillMode: Image.PreserveAspectFit
                            source: dial.cur ? Quickshell.iconPath(dial.cur.icon, true) : ""
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: bigIco.status !== Image.Ready
                            text: dial.cur ? dial.cur.name.charAt(0).toUpperCase() : "·"
                            color: Theme.accentHi
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 54
                            font.weight: Font.DemiBold
                        }
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 170
                        horizontalAlignment: Text.AlignHCenter
                        text: dial.cur ? dial.cur.name : "No matches"
                        color: Theme.fg
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 170
                        horizontalAlignment: Text.AlignHCenter
                        text: dial.cur ? (dial.cur.genericName || dial.cur.comment || "") : ""
                        color: Theme.fgDim
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: dial.n > 0 ? (dial.sel + 1) + " / " + dial.n : ""
                        color: Theme.accent
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: dial.activate()
                }
            }

            Connections {
                target: dial
                function onSelChanged() { bump.restart() }
            }
            NumberAnimation {
                id: bump
                target: coreIcon
                property: "scale"
                from: 0.7
                to: 1
                duration: 240
                easing.type: Easing.OutBack
            }
        }

        // ── Search ──
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 42
            radius: 21
            color: Qt.rgba(1, 1, 1, 0.07)
            border.width: 1
            border.color: input.activeFocus ? Qt.alpha(Theme.accent, 0.70) : Qt.rgba(1, 1, 1, 0.12)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 10

                Text {
                    text: "\uf002"
                    color: Theme.fgDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                }
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: input.text === ""
                        text: "Type to search · scroll or drag to spin · Enter to launch"
                        color: Theme.fgDim
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                    }
                    TextInput {
                        id: input
                        anchors.fill: parent
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.fg
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 13
                        clip: true
                        onTextChanged: root.query = text
                        onAccepted: dial.activate()
                        Keys.onEscapePressed: {
                            if (text !== "") text = ""
                            else if (root.n) root.n.closeAll()
                        }
                        Keys.onPressed: (e) => {
                            if (e.key === Qt.Key_Left || e.key === Qt.Key_Up) {
                                dial.go(dial.idx - 1); e.accepted = true
                            } else if (e.key === Qt.Key_Right || e.key === Qt.Key_Down
                                       || e.key === Qt.Key_Tab) {
                                dial.go(dial.idx + 1); e.accepted = true
                            }
                        }
                    }
                }
            }
        }
    }
}
