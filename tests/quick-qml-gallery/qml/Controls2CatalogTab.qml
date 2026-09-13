// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    ScrollView {
        anchors.fill: parent
        clip: true

        ColumnLayout {
            width: Math.max(parent.width - 24, 720)
            spacing: 12
            anchors.margins: 12

            GroupBox {
                title: "Buttons and delegates"
                Layout.fillWidth: true

                GridLayout {
                    anchors.fill: parent
                    columns: 4
                    columnSpacing: 12
                    rowSpacing: 10

                    Button { text: "Button" }
                    ToolButton { text: "Tool" }
                    RoundButton { text: "+" }
                    DelayButton { text: "Delay"; delay: 900 }
                    CheckDelegate { text: "CheckDelegate"; checked: true }
                    RadioDelegate { text: "RadioDelegate"; checked: true }
                    SwitchDelegate { text: "SwitchDelegate"; checked: true }
                    BusyIndicator { running: true }
                }
            }

            GroupBox {
                title: "Value controls"
                Layout.fillWidth: true

                GridLayout {
                    anchors.fill: parent
                    columns: 3
                    columnSpacing: 16
                    rowSpacing: 12

                    Dial {
                        id: dial
                        from: 0
                        to: 100
                        value: 35
                        Layout.preferredWidth: 84
                        Layout.preferredHeight: 84
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Label { text: "RangeSlider: " + Math.round(range.first.value) + "..." + Math.round(range.second.value) }
                        RangeSlider {
                            id: range
                            from: 0
                            to: 100
                            first.value: 20
                            second.value: 75
                            Layout.fillWidth: true
                        }
                        ProgressBar {
                            from: 0
                            to: 100
                            value: dial.value
                            Layout.fillWidth: true
                        }
                    }
                    Tumbler {
                        model: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                        currentIndex: 2
                        visibleItemCount: 3
                        Layout.preferredWidth: 110
                        Layout.preferredHeight: 110
                    }
                }
            }

            GroupBox {
                title: "Containers and scrolling"
                Layout.fillWidth: true
                Layout.preferredHeight: 210

                RowLayout {
                    anchors.fill: parent
                    spacing: 12

                    Pane {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        ColumnLayout {
                            anchors.fill: parent
                            Label { text: "Pane + Frame + GroupBox"; font.bold: true }
                            Frame {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Label {
                                    anchors.fill: parent
                                    wrapMode: Label.WordWrap
                                    text: "This frame checks padding, background, clipping and text wrapping inside nested Controls 2 containers."
                                }
                            }
                        }
                    }

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        ListView {
                            model: 24
                            delegate: ItemDelegate {
                                width: ListView.view.width
                                text: "Scrollable delegate " + (index + 1)
                            }
                        }
                    }
                }
            }

            GroupBox {
                title: "Text controls and tooltips"
                Layout.fillWidth: true

                GridLayout {
                    anchors.fill: parent
                    columns: 2
                    columnSpacing: 12
                    rowSpacing: 10

                    TextField {
                        placeholderText: "TextField placeholder"
                        Layout.fillWidth: true
                        ToolTip.visible: hovered
                        ToolTip.text: "Attached ToolTip"
                    }
                    ComboBox {
                        model: ["Combo popup A", "Combo popup B", "Combo popup C"]
                        Layout.fillWidth: true
                    }
                    TextArea {
                        text: "TextArea\nmultiple lines\nselection and cursor"
                        selectByMouse: true
                        wrapMode: TextArea.Wrap
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        Layout.preferredHeight: 82
                    }
                }
            }
        }
    }
}
