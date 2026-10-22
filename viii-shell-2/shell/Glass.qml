// File: ~/viii-shell-2/shell/Glass.qml
// A glass card: translucent surface + a thin light edge.
// Size it and add a `radius` where you use it:  Glass { radius: 20 }
import QtQuick

Rectangle {
    radius: 16
    color: Qt.alpha(Theme.surface, 0.55)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.10)
}