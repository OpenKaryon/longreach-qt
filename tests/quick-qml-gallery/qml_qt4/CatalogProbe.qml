// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

import QtQuick 1.1
import Qt.labs.particles 1.0

Item {
    id: root
    width: 32; height: 32
    property int sourceValue: 21
    property int boundValue: 0
    property int connectedValue: 0
    property int workerValue: 0
    property bool timerFired: false
    property int xmlCount: xml.count
    property int xmlStatus: xml.status
    property string xmlError: xml.status === XmlListModel.Error ? xml.errorString() : ""
    property bool loaded: loader.item !== null
    signal ping(int value)

    function run() {
        ping(17)
        worker.sendMessage({ value: sourceValue })
    }

    Binding { target: root; property: "boundValue"; value: root.sourceValue * 2 }
    Connections { target: root; onPing: root.connectedValue = value }
    Timer { interval: 1; running: true; repeat: false; onTriggered: root.timerFired = true }
    WorkerScript { id: worker; source: "worker.js"; onMessage: root.workerValue = messageObject.value }
    XmlListModel {
        id: xml
        source: "catalog.xml"
        query: "/catalog/item"
        XmlRole { name: "label"; query: "@name/string()" }
    }
    Loader { id: loader; sourceComponent: Component { Rectangle { width: 1; height: 1; visible: false; property int answer: 42 } } }

    // These have structural rather than visual jobs. Keeping them in a real
    // component makes the QML compiler validate their Qt Quick 1 spelling.
    StateGroup { states: State { name: "ready" } }
    SystemPalette { id: palette }
    FontLoader { }
    FocusPanel { visible: false }
    FocusScope {
        visible: false
        LayoutMirroring.enabled: true
        Keys.onSpacePressed: root.connectedValue = 23
        TextInput {
            validator: DoubleValidator { bottom: 0; top: 100 }
            KeyNavigation.tab: regexpInput
        }
        TextInput { id: regexpInput; validator: RegExpValidator { regExp: /[A-Z]+/ } }
    }

    // The remaining animation/state operations are only meaningful as pieces
    // of a larger transition. This shelf is compiled and instantiated so their
    // parsers and constructors are exercised without disturbing the probe's
    // deterministic geometry.
    Item { visible: false
        Rectangle { id: stateTarget; width: 10; height: 10 }
        Rectangle { id: alternateParent; width: 20; height: 20 }
        states: State { name: "changed"
            AnchorChanges { target: stateTarget; anchors.left: alternateParent.left }
            ParentChange { target: stateTarget; parent: alternateParent; x: 1; y: 2 }
            StateChangeScript { script: root.connectedValue = root.connectedValue }
        }
        transitions: Transition {
            AnchorAnimation { duration: 1 }
            ParentAnimation { NumberAnimation { properties: "x,y"; duration: 1 } }
            PropertyAction { target: stateTarget; property: "opacity"; value: 1 }
            ScriptAction { script: root.connectedValue = root.connectedValue }
        }
        PropertyAnimation { target: stateTarget; property: "opacity"; duration: 1 }
        PauseAnimation { duration: 1 }
        SmoothedAnimation { target: stateTarget; property: "x"; velocity: 200 }
        Vector3dAnimation { duration: 1 }
        Translate { id: translation }
    }

    Package { }
    ParticleMotion { }
    QGraphicsWidget { visible: false; LayoutItem { visible: false } }
    VisualDataModel {
        model: ListModel { ListElement { label: "probe" } }
        delegate: Component { Rectangle { width: 1; height: 1 } }
    }
}
