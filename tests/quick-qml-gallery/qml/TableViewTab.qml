// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Qt.labs.qmlmodels 1.0

Item {
    id: root
    property int selectedRow: -1
    property int selectedColumn: -1

    TableModel {
        id: tableModel
        TableModelColumn { display: "enabled" }
        TableModelColumn { display: "name" }
        TableModelColumn { display: "state" }
        TableModelColumn { display: "value" }
        rows: [
            { enabled: true,  name: "Alpha",   state: "Ready",    value: "15" },
            { enabled: false, name: "Beta",    state: "Waiting",  value: "28" },
            { enabled: true,  name: "Gamma",   state: "Running",  value: "31" },
            { enabled: true,  name: "Delta",   state: "Ready",    value: "44" },
            { enabled: false, name: "Epsilon", state: "Disabled", value: "57" },
            { enabled: true,  name: "Zeta",    state: "Running",  value: "63" },
            { enabled: true,  name: "Eta",     state: "Waiting",  value: "79" },
            { enabled: false, name: "Theta",   state: "Ready",    value: "82" },
            { enabled: true,  name: "Iota",    state: "Running",  value: "96" },
            { enabled: true,  name: "Kappa",   state: "Ready",    value: "108" },
            { enabled: false, name: "Lambda",  state: "Disabled", value: "121" },
            { enabled: true,  name: "Mu",      state: "Waiting",  value: "134" }
        ]
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Button {
                text: "Append row"
                onClicked: tableModel.appendRow({
                    enabled: tableModel.rowCount % 2 === 0,
                    name: "Row " + (tableModel.rowCount + 1),
                    state: tableModel.rowCount % 3 === 0 ? "Running" : "Ready",
                    value: String(tableModel.rowCount * 17)
                })
            }
            Button {
                text: "Remove last"
                enabled: tableModel.rowCount > 0
                onClicked: tableModel.removeRow(tableModel.rowCount - 1)
            }
            Label {
                text: root.selectedRow >= 0 ? "selected: " + root.selectedRow + "," + root.selectedColumn : "selected: none"
                Layout.fillWidth: true
                elide: Label.ElideRight
            }
        }

        SplitView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            orientation: Qt.Horizontal

            Frame {
                SplitView.fillWidth: true
                SplitView.fillHeight: true
                padding: 0

                Item {
                    anchors.fill: parent

                    HorizontalHeaderView {
                        id: horizontalHeader
                        anchors.left: verticalHeader.right
                        anchors.top: parent.top
                        anchors.right: parent.right
                        height: 32
                        syncView: tableView
                        clip: true
                    }

                    VerticalHeaderView {
                        id: verticalHeader
                        anchors.left: parent.left
                        anchors.top: horizontalHeader.bottom
                        anchors.bottom: parent.bottom
                        width: 48
                        syncView: tableView
                        clip: true
                    }

                    TableView {
                        id: tableView
                        anchors.left: verticalHeader.right
                        anchors.top: horizontalHeader.bottom
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        clip: true
                        model: tableModel
                        columnSpacing: 1
                        rowSpacing: 1
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Rectangle {
                            implicitWidth: column === 0 ? 82 : 132
                            implicitHeight: 34
                            color: row === root.selectedRow && column === root.selectedColumn ? "#bbf7d0"
                                   : row % 2 ? "#f8fafc" : "#ffffff"
                            border.color: "#d1d5db"

                            DelegateChooser {
                                role: "column"
                                DelegateChoice {
                                    roleValue: 0
                                    CheckBox {
                                        anchors.centerIn: parent
                                        checked: display
                                    }
                                }
                                DelegateChoice {
                                    roleValue: 3
                                    ProgressBar {
                                        anchors.centerIn: parent
                                        width: parent.width - 16
                                        from: 0
                                        to: 150
                                        value: Number(display)
                                    }
                                }
                                DelegateChoice {
                                    Label {
                                        anchors.fill: parent
                                        anchors.margins: 7
                                        text: display
                                        elide: Label.ElideRight
                                        verticalAlignment: Label.AlignVCenter
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.selectedRow = row
                                    root.selectedColumn = column
                                }
                            }
                        }
                    }
                }
            }

            Frame {
                SplitView.preferredWidth: 250
                SplitView.minimumWidth: 210
                SplitView.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    Label { text: "DelegateChooser"; font.bold: true }
                    Label {
                        text: "Column 0 uses CheckBox, column 3 uses ProgressBar, other columns use text delegates."
                        wrapMode: Label.WordWrap
                        Layout.fillWidth: true
                    }
                    Label { text: "Rows: " + tableModel.rowCount }
                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        ListView {
                            model: tableModel.rows
                            delegate: ItemDelegate {
                                width: ListView.view.width
                                text: modelData.name + " - " + modelData.state
                            }
                        }
                    }
                }
            }
        }
    }
}
