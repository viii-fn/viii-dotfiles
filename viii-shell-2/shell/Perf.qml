// File: ~/viii-shell-2/shell/Perf.qml
// Perforation: a column of four dots that separates two sections of the Island.
import QtQuick

Column {
    property real alpha: 0.45
    spacing: 3
    Repeater {
        model: 4
        delegate: Rectangle {
            width: 2; height: 2; radius: 1
            color: Theme.fgDim
            opacity: alpha
        }
    }
}
