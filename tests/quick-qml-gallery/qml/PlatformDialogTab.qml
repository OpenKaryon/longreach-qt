// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Qt.labs.platform 1.1 as Platform

Item {
    id: root
    property string status: "ready"
    property bool trayEnabled: false
    property bool legacyWindowsXp: typeof appLegacyWindowsXp !== "undefined" ? appLegacyWindowsXp : false
    property bool unreliableNativePopups: typeof appUnreliableNativeQmlPopups !== "undefined" ? appUnreliableNativeQmlPopups : false
    property string disabledReason: root.legacyWindowsXp
        ? "Disabled on Windows XP"
        : "Disabled on macOS: native dialogs render as gray surfaces in this static build"

    function openPlatformDialog(dialog, name) {
        if (root.unreliableNativePopups) {
            root.status = name + " " + root.disabledReason
            return
        }
        dialog.open()
    }

    Platform.FileDialog {
        id: openDialog
        title: "QML platform open file"
        fileMode: Platform.FileDialog.OpenFile
        nameFilters: ["All files (*)"]
        onAccepted: root.status = "open: " + file
        onRejected: root.status = "open rejected"
    }

    Platform.FileDialog {
        id: saveDialog
        title: "QML platform save file"
        fileMode: Platform.FileDialog.SaveFile
        nameFilters: ["Text files (*.txt)", "All files (*)"]
        onAccepted: root.status = "save: " + file
        onRejected: root.status = "save rejected"
    }

    Platform.FolderDialog {
        id: folderDialog
        title: "QML platform folder"
        onAccepted: root.status = "folder: " + folder
        onRejected: root.status = "folder rejected"
    }

    Platform.ColorDialog {
        id: colorDialog
        title: "QML platform color"
        color: "steelblue"
        onAccepted: root.status = "color: " + color
        onRejected: root.status = "color rejected"
    }

    Platform.FontDialog {
        id: fontDialog
        title: "QML platform font"
        onAccepted: root.status = "font accepted"
        onRejected: root.status = "font rejected"
    }

    Platform.MessageDialog {
        id: messageDialog
        title: "QML platform message"
        text: "Qt.labs.platform MessageDialog smoke"
        buttons: Platform.MessageDialog.Ok | Platform.MessageDialog.Cancel
        onAccepted: root.status = "message accepted"
        onRejected: root.status = "message rejected"
    }

    Platform.Menu {
        id: platformMenu
        Platform.MenuItem { text: "Platform menu item"; onTriggered: root.status = "platform menu item" }
        Platform.MenuSeparator {}
        Platform.MenuItem { text: "Disabled item"; enabled: false }
    }

    Platform.SystemTrayIcon {
        id: tray
        visible: root.trayEnabled && available
        tooltip: "Qt Quick platform tray"
        icon.name: "applications-system"
        menu: Platform.Menu {
            Platform.MenuItem { text: "Restore"; onTriggered: root.status = "tray restore" }
            Platform.MenuSeparator {}
            Platform.MenuItem { text: "Disable tray"; onTriggered: root.trayEnabled = false }
        }
        onActivated: root.status = "tray activated: " + reason
        onMessageClicked: root.status = "tray message clicked"
    }

    ScrollView {
        anchors.fill: parent
        clip: true

        ColumnLayout {
            width: Math.max(parent.width - 24, 720)
            spacing: 12
            anchors.margins: 12

            GroupBox {
                title: "Qt.labs.platform dialogs"
                Layout.fillWidth: true

                GridLayout {
                    anchors.fill: parent
                    columns: 3
                    columnSpacing: 12
                    rowSpacing: 10

                    Button {
                        text: "Open file"
                        enabled: !root.unreliableNativePopups
                        ToolTip.visible: hovered && !enabled
                        ToolTip.text: root.disabledReason
                        onClicked: root.openPlatformDialog(openDialog, "open file")
                    }
                    Button {
                        text: "Save file"
                        enabled: !root.unreliableNativePopups
                        ToolTip.visible: hovered && !enabled
                        ToolTip.text: root.disabledReason
                        onClicked: root.openPlatformDialog(saveDialog, "save file")
                    }
                    Button {
                        text: "Folder"
                        enabled: !root.unreliableNativePopups
                        ToolTip.visible: hovered && !enabled
                        ToolTip.text: root.disabledReason
                        onClicked: root.openPlatformDialog(folderDialog, "folder")
                    }
                    Button {
                        text: "Color"
                        enabled: !root.unreliableNativePopups
                        ToolTip.visible: hovered && !enabled
                        ToolTip.text: root.disabledReason
                        onClicked: root.openPlatformDialog(colorDialog, "color")
                    }
                    Button {
                        text: "Font"
                        enabled: !root.unreliableNativePopups
                        ToolTip.visible: hovered && !enabled
                        ToolTip.text: root.disabledReason
                        onClicked: root.openPlatformDialog(fontDialog, "font")
                    }
                    Button {
                        text: "Message"
                        enabled: !root.unreliableNativePopups
                        ToolTip.visible: hovered && !enabled
                        ToolTip.text: root.disabledReason
                        onClicked: root.openPlatformDialog(messageDialog, "message")
                    }
                }
            }

            GroupBox {
                title: "Platform menu and tray"
                Layout.fillWidth: true

                ColumnLayout {
                    anchors.fill: parent
                    RowLayout {
                        Button {
                            text: "Open platform menu"
                            onClicked: platformMenu.open()
                        }
                        Switch {
                            text: "Tray icon"
                            enabled: tray.available
                            checked: root.trayEnabled
                            onToggled: root.trayEnabled = checked
                        }
                        Button {
                            text: "Show tray message"
                            enabled: tray.visible
                            onClicked: tray.showMessage("Qt Quick tray", "Qt.labs.platform SystemTrayIcon smoke")
                        }
                    }

                    Label {
                        text: "system tray available: " + tray.available
                        Layout.fillWidth: true
                    }
                    Label {
                        text: "status: " + root.status
                        elide: Label.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }

            GroupBox {
                title: "Notes"
                Layout.fillWidth: true

                Label {
                    anchors.fill: parent
                    wrapMode: Label.WordWrap
                    text: root.legacyWindowsXp
                        ? "Native Qt.labs.platform dialogs are disabled on Windows XP because modal native windows can corrupt the Qt Quick OpenGL scene."
                        : (root.unreliableNativePopups
                           ? "Native Qt.labs.platform dialogs are disabled on macOS in this static build because they render as unreadable gray native surfaces. The dialog APIs are still covered by --selftest."
                           : "This tab creates Qt.labs.platform dialog and tray objects during selftest, but native UI is opened only by manual button clicks.")
                }
            }
        }
    }
}
