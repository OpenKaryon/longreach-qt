// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    property string status: "ready"

    Drawer {
        id: drawer
        width: Math.min(root.width * 0.45, 280)
        height: root.height
        edge: Qt.LeftEdge
        modal: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            Label { text: "Drawer"; font.bold: true }
            ItemDelegate { text: "Drawer action"; Layout.fillWidth: true; onClicked: root.status = "drawer action" }
            ItemDelegate { text: "Close"; Layout.fillWidth: true; onClicked: drawer.close() }
            Item { Layout.fillHeight: true }
        }
    }

    Menu {
        id: menu
        MenuItem { text: "First action"; onTriggered: root.status = "first menu action" }
        Menu {
            title: "Nested menu"
            MenuItem { text: "Nested A"; onTriggered: root.status = "nested A" }
            MenuItem { text: "Nested B"; onTriggered: root.status = "nested B" }
        }
        MenuSeparator {}
        MenuItem { text: "Disabled action"; enabled: false }
    }

    Popup {
        id: popup
        x: 28
        y: 82
        width: 280
        height: 150
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle {
            color: "#ffffff"
            border.color: "#6b7280"
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            Label { text: "Popup content"; font.bold: true }
            Label {
                text: "Checks popup geometry, focus and font metrics."
                wrapMode: Label.WordWrap
                Layout.fillWidth: true
            }
            Button { text: "Close"; onClicked: popup.close() }
        }
    }

    Dialog {
        id: dialog
        title: "Controls 2 Dialog"
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        onAccepted: root.status = "dialog accepted"
        onRejected: root.status = "dialog rejected"

        Label {
            text: "Dialog body with standard buttons."
            wrapMode: Label.WordWrap
            width: 260
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        MenuBar {
            Layout.fillWidth: true
            Menu {
                title: "File"
                Action { text: "New"; onTriggered: root.status = "new" }
                Action { text: "Open"; onTriggered: root.status = "open" }
                MenuSeparator {}
                Action { text: "Close"; onTriggered: root.status = "close" }
            }
            Menu {
                title: "View"
                Action { text: "Navigation"; onTriggered: stack.push(pageB) }
                Action { text: "Details"; onTriggered: stack.push(pageC) }
            }
        }

        RowLayout {
            spacing: 10
            Button { text: "Open Drawer"; onClicked: drawer.open() }
            Button { text: "Open Popup"; onClicked: popup.open() }
            Button { text: "Open Dialog"; onClicked: dialog.open() }
            Button {
                id: menuButton
                text: "Open Menu"
                onClicked: {
                    menu.x = menuButton.x
                    menu.y = menuButton.y + menuButton.height
                    menu.open()
                }
            }
            Label { text: "status: " + root.status; Layout.fillWidth: true; elide: Label.ElideRight }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            Frame {
                Layout.minimumWidth: 300
                Layout.preferredWidth: 360
                Layout.maximumWidth: 420
                Layout.fillHeight: true
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 8
                    RowLayout {
                        Button { text: "Push A"; onClicked: stack.push(pageA) }
                        Button { text: "Push B"; onClicked: stack.push(pageB) }
                        Button { text: "Pop"; enabled: stack.depth > 1; onClicked: stack.pop() }
                    }
                    StackView {
                        id: stack
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        initialItem: pageA
                    }
                }
            }

            Frame {
                Layout.minimumWidth: 300
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    SwipeView {
                        id: swipe
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        currentIndex: 1
                        Repeater {
                            model: ["Swipe page 1", "Swipe page 2", "Swipe page 3"]
                            Pane {
                                Label {
                                    anchors.centerIn: parent
                                    text: modelData
                                    font.pixelSize: 22
                                }
                            }
                        }
                    }
                    PageIndicator {
                        count: swipe.count
                        currentIndex: swipe.currentIndex
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }
        }
    }

    Component {
        id: pageA
        Page {
            title: "Page A"
            Label { anchors.centerIn: parent; text: "StackView page A" }
        }
    }

    Component {
        id: pageB
        Page {
            title: "Page B"
            Label { anchors.centerIn: parent; text: "StackView page B" }
        }
    }

    Component {
        id: pageC
        Page {
            title: "Page C"
            Label { anchors.centerIn: parent; text: "StackView page C" }
        }
    }
}
