// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15

Item {
    id: root
    property string status: "ready"
    property bool legacyWindowsXp: typeof appLegacyWindowsXp !== "undefined" ? appLegacyWindowsXp : false
    property bool unreliableNativePopups: typeof appUnreliableNativeQmlPopups !== "undefined" ? appUnreliableNativeQmlPopups : false
    property string disabledReason: root.legacyWindowsXp
        ? "Disabled on Windows XP"
        : "Disabled on macOS: native QML windows render as gray surfaces in this static build"

    function showWindow(win) {
        if (root.unreliableNativePopups) {
            root.status = root.disabledReason
            return
        }
        win.x = Screen.width / 2 - win.width / 2
        win.y = Screen.height / 2 - win.height / 2
        win.show()
        win.raise()
        win.requestActivate()
    }

    Window {
        id: plainWindow
        width: 320
        height: 180
        title: "QML Window"
        color: "#f8fafc"
        onActiveChanged: root.status = "plain active: " + active
        Column {
            anchors.centerIn: parent
            spacing: 10
            Text { text: "Plain QML Window"; font.pixelSize: 20 }
            Button { text: "Close"; onClicked: plainWindow.hide() }
        }
    }

    Window {
        id: toolWindow
        width: 300
        height: 150
        title: "QML Tool"
        flags: Qt.Tool
        color: "#ecfeff"
        Column {
            anchors.centerIn: parent
            spacing: 8
            Text { text: "Qt.Tool window" }
            TextField { text: "focus test"; width: 190 }
            Button { text: "OK"; onClicked: toolWindow.hide() }
        }
    }

    Window {
        id: framelessWindow
        width: 300
        height: 160
        title: "Frameless QML"
        flags: Qt.Window | Qt.FramelessWindowHint
        color: "#111827"
        Rectangle {
            anchors.fill: parent
            color: "#111827"
            border.color: "#60a5fa"
            border.width: 2
            Text {
                anchors.centerIn: parent
                text: "Frameless QML Window"
                color: "white"
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onClicked: framelessMenu.popup()
            }
            Menu {
                id: framelessMenu
                MenuItem { text: "Hide"; onTriggered: framelessWindow.hide() }
            }
        }
    }

    Window {
        id: splashWindow
        width: 260
        height: 120
        title: "Splash"
        flags: Qt.SplashScreen
        modality: Qt.ApplicationModal
        color: "#fef3c7"
        Column {
            anchors.centerIn: parent
            spacing: 10
            Text { text: "Splash / modal flags" }
            Button { text: "OK"; onClicked: splashWindow.hide() }
        }
    }

    Window {
        id: translucentWindow
        width: 280
        height: 180
        title: "Translucent"
        flags: Qt.Window | Qt.FramelessWindowHint
        color: "transparent"
        Rectangle {
            anchors.fill: parent
            anchors.margins: 10
            radius: 24
            color: "#cc1d4ed8"
            border.color: "#93c5fd"
            Column {
                anchors.centerIn: parent
                spacing: 10
                Text {
                    text: "transparent window"
                    color: "white"
                }
                Button { text: "OK"; onClicked: translucentWindow.hide() }
            }
        }
    }

    ScrollView {
        anchors.fill: parent
        clip: true

        ColumnLayout {
            width: Math.max(parent.width - 24, 720)
            spacing: 12
            anchors.margins: 12

            GroupBox {
                title: "QtQuick.Window"
                Layout.fillWidth: true

                GridLayout {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    columns: 3
                    columnSpacing: 12
                    rowSpacing: 10

                    Button {
                        text: "Plain Window"
                        enabled: !root.unreliableNativePopups
                        Layout.preferredWidth: 140
                        ToolTip.visible: hovered && !enabled
                        ToolTip.text: root.disabledReason
                        onClicked: root.showWindow(plainWindow)
                    }
                    Button {
                        text: "Tool Window"
                        enabled: !root.unreliableNativePopups
                        Layout.preferredWidth: 140
                        ToolTip.visible: hovered && !enabled
                        ToolTip.text: root.disabledReason
                        onClicked: root.showWindow(toolWindow)
                    }
                    Button {
                        text: "Frameless"
                        enabled: !root.unreliableNativePopups
                        Layout.preferredWidth: 140
                        ToolTip.visible: hovered && !enabled
                        ToolTip.text: root.disabledReason
                        onClicked: root.showWindow(framelessWindow)
                    }
                    Button {
                        text: "Splash/modal"
                        enabled: !root.unreliableNativePopups
                        Layout.preferredWidth: 140
                        ToolTip.visible: hovered && !enabled
                        ToolTip.text: root.disabledReason
                        onClicked: root.showWindow(splashWindow)
                    }
                    Button {
                        text: "Translucent"
                        enabled: !root.unreliableNativePopups
                        Layout.preferredWidth: 140
                        ToolTip.visible: hovered && !enabled
                        ToolTip.text: root.disabledReason
                        onClicked: root.showWindow(translucentWindow)
                    }
                    Button {
                        text: "Hide all"
                        Layout.preferredWidth: 140
                        onClicked: {
                            plainWindow.hide()
                            toolWindow.hide()
                            framelessWindow.hide()
                            splashWindow.hide()
                            translucentWindow.hide()
                            root.status = "hidden"
                        }
                    }
                }
            }

            GroupBox {
                title: "Window state"
                Layout.fillWidth: true

                ColumnLayout {
                    anchors.fill: parent
                    Label { text: "status: " + root.status; Layout.fillWidth: true }
                    Label { text: "screen: " + Screen.width + "x" + Screen.height; Layout.fillWidth: true }
                    Label {
                        text: root.unreliableNativePopups
                            ? (root.legacyWindowsXp
                               ? "Separate Qt Quick windows are disabled on Windows XP because this OpenGL/WGL stack corrupts the main Quick scene after native child windows."
                               : "Separate Qt Quick windows are disabled on macOS in this static build because they render as unreadable gray native surfaces.")
                            : "Right-click the frameless window to test a QML menu inside an unframed native window."
                        wrapMode: Label.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }
}
