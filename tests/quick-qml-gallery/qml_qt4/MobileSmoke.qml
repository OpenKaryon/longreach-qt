// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

import QtQuick 1.1

Rectangle {
    width: 220
    height: 260
    color: "#20242c"
    property alias checked: control.checked

    SwitchTile {
        id: control
        objectName: "tapSwitch"
        anchors.centerIn: parent
        width: 96
        height: 96
    }
}
