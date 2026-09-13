// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    focus: true
    property string lastKey: "none"

    Keys.onPressed: {
        lastKey = event.text.length ? event.text : event.key
        event.accepted = false
    }

    ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true

        ColumnLayout {
            width: Math.max(parent.width - 24, 720)
            spacing: 12
            anchors.margins: 12

            GroupBox {
                title: "Text input"
                Layout.fillWidth: true

                GridLayout {
                    anchors.fill: parent
                    columns: 2
                    columnSpacing: 12
                    rowSpacing: 10

                    TextField {
                        id: field
                        placeholderText: "Editable TextField"
                        selectByMouse: true
                        Layout.fillWidth: true
                    }
                    SpinBox {
                        from: -100
                        to: 100
                        value: 15
                    }
                    TextArea {
                        text: "TextArea with wrapping, selection and scrollbars.\nLine 2\nLine 3"
                        wrapMode: TextArea.Wrap
                        selectByMouse: true
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        Layout.preferredHeight: 110
                    }
                    ComboBox {
                        editable: true
                        model: ["editable combo", "popup list", "keyboard focus"]
                        Layout.fillWidth: true
                    }
                    Label {
                        text: "last key: " + root.lastKey
                        Layout.fillWidth: true
                    }
                }
            }

            GroupBox {
                title: "Rich text and metrics"
                Layout.fillWidth: true

                ColumnLayout {
                    anchors.fill: parent
                    Text {
                        id: sample
                        text: "Qt Quick Text: plain, <b>bold</b>, <i>italic</i>, colored spans"
                        textFormat: Text.RichText
                        font.pixelSize: 20
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    TextMetrics {
                        id: metrics
                        text: sample.text
                        font: sample.font
                    }
                    Label {
                        text: "advance width: " + Math.round(metrics.advanceWidth) + ", height: " + Math.round(metrics.height)
                    }
                    TextEdit {
                        text: "TextEdit checks cursor, selection, mouse editing and native text rendering."
                        selectByMouse: true
                        wrapMode: TextEdit.Wrap
                        Layout.fillWidth: true
                        Layout.preferredHeight: 82
                    }
                }
            }

            GroupBox {
                title: "Mouse, drag and drop visuals"
                Layout.fillWidth: true
                Layout.preferredHeight: 190

                Item {
                    anchors.fill: parent
                    id: dragDropHost
                    property bool dragging: false
                    property bool dropHot: false
                    property string dragText: ""

                    function setScrollInteractive(enabled) {
                        if (scroll.contentItem)
                            scroll.contentItem.interactive = enabled
                    }

                    function moveDragProxy(item, mouseX, mouseY) {
                        var p = dragDropHost.mapFromItem(item, mouseX, mouseY)
                        dragProxy.x = p.x - dragProxy.width / 2
                        dragProxy.y = p.y - dragProxy.height / 2
                        var targetPoint = dropTarget.mapFromItem(dragDropHost, p.x, p.y)
                        dropHot = targetPoint.x >= 0 && targetPoint.y >= 0
                                && targetPoint.x <= dropTarget.width
                                && targetPoint.y <= dropTarget.height
                    }

                    function finishDrag() {
                        if (dropHot)
                            dropTarget.receivedText = dragText
                        dragging = false
                        dropHot = false
                        setScrollInteractive(true)
                    }

                    RowLayout {
                        anchors.fill: parent
                        spacing: 12

                        ColumnLayout {
                            id: sourceColumn

                            Layout.minimumWidth: 180
                            Layout.preferredWidth: 190
                            Layout.maximumWidth: 220
                            Layout.fillHeight: true

                            Repeater {
                                model: [ "First draggable text", "Second draggable text", "Third draggable text" ]

                                Rectangle {
                                    id: dragSource
                                    property string payload: modelData

                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 42
                                    color: dragMouse.pressed ? "#bfdbfe" : "#dbeafe"
                                    border.color: "#2563eb"

                                    Text {
                                        anchors.centerIn: parent
                                        text: dragSource.payload
                                    }

                                    MouseArea {
                                        id: dragMouse
                                        anchors.fill: parent
                                        cursorShape: Qt.OpenHandCursor
                                        preventStealing: true
                                        onPressed: {
                                            dragDropHost.dragText = dragSource.payload
                                            dragDropHost.dragging = true
                                            dragDropHost.setScrollInteractive(false)
                                            dragDropHost.moveDragProxy(dragSource, mouse.x, mouse.y)
                                        }
                                        onPositionChanged: {
                                            if (!dragDropHost.dragging)
                                                return
                                            dragDropHost.moveDragProxy(dragSource, mouse.x, mouse.y)
                                        }
                                        onReleased: dragDropHost.finishDrag()
                                        onCanceled: {
                                            dragDropHost.dragging = false
                                            dragDropHost.dropHot = false
                                            dragDropHost.setScrollInteractive(true)
                                        }
                                    }
                                }
                            }

                            Item { Layout.fillHeight: true }
                        }

                        DropArea {
                            id: dropTarget
                            Layout.minimumWidth: 320
                            Layout.preferredWidth: 520
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            property string receivedText: ""

                            Rectangle {
                                anchors.fill: parent
                                color: dragDropHost.dropHot ? "#dcfce7" : "#f3f4f6"
                                border.color: "#16a34a"
                                Text {
                                    anchors.centerIn: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    text: dropTarget.receivedText.length
                                          ? "Received text:\n" + dropTarget.receivedText
                                          : (dragDropHost.dropHot ? "Release to drop" : "Drop text here")
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: dragProxy
                        width: sourceColumn.width
                        height: 42
                        visible: dragDropHost.dragging
                        z: 100
                        color: "#bfdbfe"
                        border.color: "#2563eb"
                        opacity: 0.9

                        Text {
                            anchors.centerIn: parent
                            text: dragDropHost.dragText
                        }
                    }
                }
            }
        }
    }
}
