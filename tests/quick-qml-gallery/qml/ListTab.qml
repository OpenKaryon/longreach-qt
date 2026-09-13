// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Exercises ListModel/ListView with a delegate and highlight - the QML-side
// equivalent of the item-view widgets in the widgets gallery.
import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    ListModel {
        id: fruitModel
        ListElement { name: "Apple"; color: "#c02020" }
        ListElement { name: "Lime"; color: "#40a020" }
        ListElement { name: "Blueberry"; color: "#2040c0" }
        ListElement { name: "Banana"; color: "#d0b020" }
        ListElement { name: "Grape"; color: "#7020a0" }
    }

    ListView {
        anchors.fill: parent
        anchors.margins: 12
        model: fruitModel
        clip: true
        spacing: 4
        highlight: Rectangle { color: "#30000000"; radius: 4 }
        highlightFollowsCurrentItem: true

        delegate: ItemDelegate {
            width: ListView.view.width
            text: name
            icon.color: color
            onClicked: ListView.view.currentIndex = index

            contentItem: Row {
                spacing: 10
                Rectangle { width: 20; height: 20; radius: 10; color: model.color; anchors.verticalCenter: parent.verticalCenter }
                Text { text: model.name; anchors.verticalCenter: parent.verticalCenter }
            }
        }
    }
}
