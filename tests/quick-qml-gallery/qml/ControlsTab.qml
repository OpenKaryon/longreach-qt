// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    property int clicks: 0

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        RowLayout {
            spacing: 12
            Button { text: "Push me"; onClicked: clickLabel.text = "clicked " + (++clicks) + "x" }
            CheckBox { text: "Check"; checked: true }
            RadioButton { text: "A"; checked: true }
            RadioButton { text: "B" }
        }

        Label { id: clickLabel; text: "clicked 0x" }

        RowLayout {
            spacing: 12
            Label { text: "Slider:" }
            Slider { id: slider; from: 0; to: 100; value: 40; Layout.fillWidth: true }
            Label { text: Math.round(slider.value) }
        }

        RowLayout {
            spacing: 12
            Label { text: "Progress:" }
            ProgressBar { from: 0; to: 100; value: slider.value; Layout.fillWidth: true }
        }

        RowLayout {
            spacing: 12
            ComboBox { model: ["One", "Two", "Three"] }
            TextField { placeholderText: "type here"; Layout.fillWidth: true }
            SpinBox { from: 0; to: 10; value: 3 }
        }

        Switch { text: "Enable extra stuff" }

        Item { Layout.fillHeight: true }
    }
}
