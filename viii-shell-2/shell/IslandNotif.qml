// File: ~/viii-shell-2/shell/IslandNotif.qml
// One notification card, used inside the Island (popup and list).

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications

Item {
    id: card
    property var notif: null
    readonly property string mono: "JetBrainsMono Nerd Font"
    readonly property bool critical: notif !== null && notif.urgency === NotificationUrgency.Critical
    readonly property string iconSrc: {
        if (!notif) return ""
        if (notif.image && notif.image !== "") return notif.image
        if (notif.appIcon && notif.appIcon !== "") {
            return notif.appIcon.startsWith("/") ? "file://" + notif.appIcon
                                                 : Quickshell.iconPath(notif.appIcon, "dialog-information")
        }
        return ""
    }

    implicitHeight: content.implicitHeight + 22

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: Qt.rgba(1, 1, 1, 0.07)
        border.width: 1
        border.color: card.critical ? Theme.bad : Qt.rgba(1, 1, 1, 0.12)
    }

    RowLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 11
        spacing: 10

        Image {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            visible: card.iconSrc !== ""
            source: card.iconSrc
            sourceSize: Qt.size(64, 64)
            fillMode: Image.PreserveAspectFit
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                text: card.notif ? card.notif.appName.toUpperCase() : ""
                color: card.critical ? Theme.bad : Theme.accentHi
                font.family: card.mono
                font.pixelSize: 9
                font.letterSpacing: 2
            }
            Text {
                Layout.fillWidth: true
                text: card.notif ? card.notif.summary : ""
                color: Theme.fg
                font.family: card.mono
                font.pixelSize: 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: card.notif ? card.notif.body : ""
                color: Theme.fgDim
                font.family: card.mono
                font.pixelSize: 11
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }

            // Action buttons (Reply, Open, ...) if the app sent any
            Row {
                spacing: 14
                visible: card.notif !== null && card.notif.actions.length > 0
                Repeater {
                    model: card.notif ? card.notif.actions : []
                    delegate: Text {
                        required property var modelData
                        text: modelData.text.toUpperCase()
                        color: actArea.containsMouse ? Theme.accentHi : Theme.fg
                        font.family: card.mono
                        font.pixelSize: 9
                        font.letterSpacing: 2
                        MouseArea {
                            id: actArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: modelData.invoke()
                        }
                    }
                }
            }
        }

        // Dismiss
        Text {
            Layout.alignment: Qt.AlignTop
            text: "\uf00d"
            color: xArea.containsMouse ? Theme.accentHi : Theme.fgDim
            font.family: card.mono
            font.pixelSize: 12
            MouseArea {
                id: xArea
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (card.notif) card.notif.dismiss()
            }
        }
    }
}
