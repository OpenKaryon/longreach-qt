// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

import QtQuick 1.1

Rectangle {
    id: tile
    width: 22
    height: 22
    property bool checked: false
    color: checked ? "#50b848" : "#3a404b"
    border.color: "#87909e"

    Text {
        anchors.centerIn: parent
        text: tile.checked ? "✓" : ""
        color: "white"
    }
    MouseArea {
        anchors.fill: parent
        onClicked: tile.checked = !tile.checked
    }
}
