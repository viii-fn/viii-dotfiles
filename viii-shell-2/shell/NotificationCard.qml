import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications

Item {
    id: card

    required property var modelData
    readonly property var n: modelData
    readonly property bool critical: n.urgency === NotificationUrgency.Critical

    // How long it stays, in ms. 0 = until clicked (critical).
    // Apps can request their own time via expireTimeout (in seconds).
    readonly property int lifetime: {
        if (critical) return 0
        if (n.expireTimeout > 0) return n.expireTimeout * 1000
        return n.urgency === NotificationUrgency.Low ? 4000 : 6000
    }

    readonly property bool hasActions: {
        for (let i = 0; i < n.actions.length; i++)
            if (n.actions[i].identifier !== "default") return true
        return false
    }

    property bool closing: false
    property real remaining: 1      // 1 -> 0, drives the timer bar

    width: parent.width
    height: panel.height

    function iconSource() {
        if (n.image !== "") return n.image
        if (n.appIcon === "") return ""
        if (n.appIcon.startsWith("/")) return "file://" + n.appIcon
        return Quickshell.iconPath(n.appIcon, true)
    }

    // Play the exit animation first, then tell the app how it closed.
    function close(expired) {
        if (closing) return
        closing = true
        countdown.stop()
        exit.expired = expired
        exit.start()
    }

    // An app updated this notification (volume/brightness popups do this):
    // show the new text and restart the timer.
    function refresh() {
        if (closing || lifetime === 0) return
        remaining = 1
        countdown.restart()
    }

    Connections {
        target: card.n
        function onSummaryChanged() { card.refresh() }
        function onBodyChanged() { card.refresh() }
    }

    Component.onCompleted: enter.start()

    Rectangle {
        id: panel
        width: parent.width
        height: content.implicitHeight + 28
        x: card.width               // starts off to the right, clipped by the window
        opacity: 0
        radius: 20
        color: Qt.alpha(Theme.bg, Theme.bgAlpha)
        border.width: 1
        border.color: card.critical ? Theme.bad : Theme.line

        HoverHandler { id: hover }  // hovering pauses the timer

        // left click: run the "default" action if there is one, then close
        // right click: just dismiss
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (mouse.button === Qt.LeftButton) {
                    for (let i = 0; i < card.n.actions.length; i++)
                        if (card.n.actions[i].identifier === "default")
                            card.n.actions[i].invoke()
                }
                card.close(false)
            }
        }

        ColumnLayout {
            id: content
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                // icon / avatar tile
                Rectangle {
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    Layout.alignment: Qt.AlignTop
                    radius: 12
                    color: Theme.surface

                    Image {
                        id: img
                        anchors { fill: parent; margins: 6 }
                        source: card.iconSource()
                        sourceSize: Qt.size(80, 80)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }
                    // no icon available: first letter of the app name
                    Text {
                        anchors.centerIn: parent
                        visible: img.status !== Image.Ready
                        text: (card.n.appName || "?").charAt(0).toUpperCase()
                        color: Theme.accentHi
                        font { pixelSize: 18; bold: true }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        text: card.n.appName
                        color: Theme.fgDim
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: card.n.summary
                        color: Theme.fg
                        font { pixelSize: 14; bold: true }
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: card.n.body
                        textFormat: Text.StyledText   // safe subset of markup
                        color: Theme.fgDim
                        font.pixelSize: 13
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }
                }
            }

            // action buttons (the "default" action is the card click, not a button)
            RowLayout {
                Layout.fillWidth: true
                visible: card.hasActions
                spacing: 8

                Repeater {
                    model: card.n.actions

                    Rectangle {
                        required property var modelData
                        visible: modelData.identifier !== "default"
                        Layout.preferredHeight: 30
                        Layout.preferredWidth: label.implicitWidth + 28
                        radius: 15
                        color: btn.containsMouse ? Theme.accent : Theme.surface

                        Text {
                            id: label
                            anchors.centerIn: parent
                            text: parent.modelData.text
                            color: btn.containsMouse ? Theme.accentText : Theme.accentHi
                            font { pixelSize: 12; bold: true }
                        }
                        MouseArea {
                            id: btn
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                parent.modelData.invoke()
                                card.close(false)
                            }
                        }
                    }
                }
            }

            // time-left bar (hidden for critical, which waits for you)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 3
                radius: 1.5
                visible: card.lifetime > 0
                color: Theme.surface

                Rectangle {
                    width: parent.width * card.remaining
                    height: parent.height
                    radius: parent.radius
                    color: Theme.accent
                }
            }
        }
    }

    // slide in from the right with a small overshoot
    ParallelAnimation {
        id: enter
        NumberAnimation {
            target: panel; property: "x"
            from: card.width; to: 0
            duration: 380
            easing.type: Easing.OutBack; easing.overshoot: 0.8
        }
        NumberAnimation { target: panel; property: "opacity"; from: 0; to: 1; duration: 200 }
        onFinished: if (card.lifetime > 0) countdown.start()
    }

    NumberAnimation {
        id: countdown
        target: card; property: "remaining"
        from: 1; to: 0
        duration: card.lifetime
        paused: hover.hovered
        onFinished: card.close(true)
    }

    ParallelAnimation {
        id: exit
        property bool expired: false
        NumberAnimation { target: panel; property: "x"; to: 60; duration: 200; easing.type: Easing.InCubic }
        NumberAnimation { target: panel; property: "opacity"; to: 0; duration: 200 }
        onFinished: {
            if (!card.n) return     // the app already closed it itself
            if (expired) card.n.expire()
            else card.n.dismiss()
        }
    }
}
