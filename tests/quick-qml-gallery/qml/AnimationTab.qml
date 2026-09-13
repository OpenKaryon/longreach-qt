// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Exercises the QML animation framework: NumberAnimation, SequentialAnimation,
// Behavior, and states/transitions - the declarative counterpart to
// QPropertyAnimation in the graphics gallery.
import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    Rectangle {
        id: bouncer
        width: 50; height: 50
        radius: 8
        color: "#e0a020"
        y: 20

        SequentialAnimation on x {
            loops: Animation.Infinite
            NumberAnimation { from: 20; to: 400; duration: 1200; easing.type: Easing.InOutCubic }
            NumberAnimation { from: 400; to: 20; duration: 1200; easing.type: Easing.InOutCubic }
        }
    }

    Rectangle {
        id: pulser
        width: 40; height: 40
        radius: 20
        color: "#2080c0"
        x: 30; y: 120

        states: State {
            name: "big"
            PropertyChanges { target: pulser; scale: 1.6; opacity: 0.5 }
        }
        transitions: Transition {
            NumberAnimation { properties: "scale,opacity"; duration: 500; easing.type: Easing.InOutQuad }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: pulser.state = pulser.state === "big" ? "" : "big"
        }
    }

    Rectangle {
        id: follower
        width: 24; height: 24
        radius: 12
        color: "#c02040"
        y: 200
        Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
    }

    Slider {
        y: 240
        width: 300
        from: 20; to: 320
        onValueChanged: follower.x = value
    }

    Label {
        y: 280
        text: "Click the blue circle to pulse it; drag the slider to chase it with the red dot."
        width: 400
        wrapMode: Text.WordWrap
    }
}
