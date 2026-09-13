// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root

    ScrollView {
        anchors.fill: parent
        clip: true

        ColumnLayout {
            width: Math.max(parent.width - 24, 720)
            spacing: 12
            anchors.margins: 12

            GroupBox {
                title: "Accordion / expanding sections"
                Layout.fillWidth: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 6

                    Repeater {
                        model: [
                            { title: "Activity feed", body: "Expands with animated height and opacity. Useful for delegate and clipping regressions." },
                            { title: "Details panel", body: "Nested controls stay correctly sized while the container changes height." },
                            { title: "Actions", body: "This imitates the accordion-style official expanding delegate examples." }
                        ]

                        ColumnLayout {
                            id: section
                            property bool expanded: index === 0
                            Layout.fillWidth: true
                            spacing: 0

                            ToolButton {
                                text: (section.expanded ? "v " : "> ") + modelData.title
                                Layout.fillWidth: true
                                onClicked: section.expanded = !section.expanded
                            }

                            Pane {
                                Layout.fillWidth: true
                                implicitHeight: section.expanded ? content.implicitHeight + topPadding + bottomPadding : 0
                                opacity: section.expanded ? 1 : 0
                                clip: true
                                Behavior on implicitHeight { NumberAnimation { duration: 160; easing.type: Easing.InOutQuad } }
                                Behavior on opacity { NumberAnimation { duration: 120 } }

                                ColumnLayout {
                                    id: content
                                    width: parent.width
                                    Label {
                                        text: modelData.body
                                        wrapMode: Label.WordWrap
                                        Layout.fillWidth: true
                                    }
                                    RowLayout {
                                        Button { text: "Action" }
                                        CheckBox { text: "Enabled"; checked: true }
                                        Slider { from: 0; to: 10; value: index + 3; Layout.fillWidth: true }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 220
                spacing: 12

                GroupBox {
                    title: "SwipeDelegate list"
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ListView {
                        anchors.fill: parent
                        clip: true
                        model: ["Swipe left/right", "Delegate with actions", "Selection colors", "Pressed state"]
                        delegate: SwipeDelegate {
                            width: ListView.view.width
                            text: modelData
                            swipe.right: Label {
                                text: "Archive"
                                color: "white"
                                verticalAlignment: Label.AlignVCenter
                                padding: 12
                                background: Rectangle { color: "#2563eb" }
                            }
                        }
                    }
                }

                GroupBox {
                    title: "GridView"
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    GridView {
                        anchors.fill: parent
                        clip: true
                        cellWidth: 92
                        cellHeight: 72
                        model: 24
                        delegate: Rectangle {
                            width: 82
                            height: 60
                            radius: 4
                            color: index % 2 ? "#e0f2fe" : "#fef3c7"
                            border.color: GridView.isCurrentItem ? "#111827" : "#9ca3af"
                            Text {
                                anchors.centerIn: parent
                                text: "Cell " + (index + 1)
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: GridView.view.currentIndex = index
                            }
                        }
                    }
                }
            }

            GroupBox {
                title: "PathView"
                Layout.fillWidth: true
                Layout.preferredHeight: 180

                PathView {
                    id: pathView
                    anchors.fill: parent
                    model: ["One", "Two", "Three", "Four", "Five", "Six", "Seven"]
                    pathItemCount: 5
                    preferredHighlightBegin: 0.5
                    preferredHighlightEnd: 0.5
                    delegate: Rectangle {
                        width: 92
                        height: 70
                        radius: 6
                        color: PathView.isCurrentItem ? "#bbf7d0" : "#e5e7eb"
                        border.color: "#374151"
                        scale: PathView.isCurrentItem ? 1.15 : 0.9
                        Text { anchors.centerIn: parent; text: modelData }
                    }
                    path: Path {
                        startX: 70
                        startY: 90
                        PathAttribute { name: "scale"; value: 0.8 }
                        PathQuad { x: root.width / 2; y: 30; controlX: root.width / 4; controlY: 20 }
                        PathAttribute { name: "scale"; value: 1.15 }
                        PathQuad { x: root.width - 90; y: 90; controlX: root.width * 0.75; controlY: 20 }
                        PathAttribute { name: "scale"; value: 0.8 }
                    }
                }
            }
        }
    }
}
