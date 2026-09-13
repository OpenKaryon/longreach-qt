// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Visual QML gallery: an ApplicationWindow exercising Qt Quick, Controls 2,
// Shapes, animations, popups, navigation and model/view patterns - the QML-side
// counterpart to the C++ widgets/graphics galleries.
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

ApplicationWindow {
    id: root
    visible: true
    width: 940
    height: 640
    title: "Qt Quick Gallery - " + Qt.application.version

    header: ToolBar {
        RowLayout {
            anchors.fill: parent
            anchors.margins: 6
            Label {
                text: "Qt Quick / Controls 2 / Shapes smoke test"
                elide: Label.ElideRight
                Layout.fillWidth: true
            }
        }
    }

    SplitView {
        anchors.fill: parent
        orientation: Qt.Horizontal

        Frame {
            SplitView.preferredWidth: 190
            SplitView.minimumWidth: 160
            SplitView.maximumWidth: 260
            padding: 0

            ListView {
                id: sectionList
                anchors.fill: parent
                clip: true
                currentIndex: 0
                model: [
                    "Controls",
                    "Controls 2",
                    "Popups",
                    "Platform",
                    "Windows",
                    "Accordion",
                    "TableView",
                    "Input/Text",
                    "Canvas",
                    "Particles",
                    "Effects",
                    "Shapes",
                    "Animation",
                    "ListView"
                ]
                delegate: ItemDelegate {
                    width: ListView.view.width
                    text: modelData
                    highlighted: ListView.isCurrentItem
                    onClicked: sectionList.currentIndex = index
                }
            }
        }

        StackLayout {
            currentIndex: sectionList.currentIndex
            SplitView.fillWidth: true
            SplitView.fillHeight: true

            ControlsTab {}
            Controls2CatalogTab {}
            NavigationPopupTab {}
            PlatformDialogTab {}
            WindowLabTab {}
            AccordionViewsTab {}
            TableViewTab {}
            InputTextTab {}
            CanvasShaderTab {}
            ParticlesTab {}
            GraphicalEffectsTab {}
            ShapesTab {}
            AnimationTab {}
            ListTab {}
        }
    }
}
