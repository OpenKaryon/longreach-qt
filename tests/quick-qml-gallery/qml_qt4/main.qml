// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Qt 4.8's Qt Quick 1.1 counterpart to qml/main.qml. It deliberately keeps
// the same fourteen-section navigation. Where a later module has no Qt 4
// equivalent, the page demonstrates the nearest composable Qt Quick 1
// primitive and labels the missing module instead of silently disappearing.
import QtQuick 1.1
import Qt.labs.folderlistmodel 1.0
import Qt.labs.gestures 1.0
import Qt.labs.particles 1.0
import Qt.labs.shaders 1.0

Rectangle {
    id: root
    width: 940; height: 640
    color: "#20242c"
    property int section: 0
    property bool shaderEffectsAvailable: appShaderEffectsAvailable
    property variant names: ["Controls", "Controls 2", "Popups", "Platform", "Windows",
                             "Accordion", "TableView", "Input/Text", "Canvas", "Particles",
                             "Effects", "Shapes", "Animation", "ListView"]
    property variant details: [
        "Buttons, checkbox, slider and progress composed from Qt Quick 1 primitives",
        "Controls 2 arrived later; these switches show the same interaction model",
        "Popup and modal-overlay behaviour built from Item, Rectangle and MouseArea",
        "Qt Quick 1 has no platform-dialog QML module; URL and path editing remain available",
        "A draggable child-window simulation; Window QML types arrived with Qt Quick 2",
        "Expandable sections driven by states and animated height",
        "A model-backed grid standing in for the later Controls TableView",
        "TextInput, TextEdit, selection and focus",
        "Canvas arrived in Qt Quick 2; this page composes the same drawing from primitives",
        "A lightweight particle field animated by Qt Quick 1 animations",
        "Opacity, scale, rotation and colour effects without the later effects module",
        "Shape primitives assembled from rectangles; QtQuick.Shapes arrived later",
        "Sequential, parallel, easing and behavioural animation",
        "ListView, sections, current item and flicking"
    ]

    Rectangle {
        id: header; height: 46; anchors.left: parent.left; anchors.right: parent.right
        color: "#343a46"
        Text { anchors.centerIn: parent; text: "Qt Quick / Controls / Shapes smoke test - Qt 4.8"; color: "white"; font.pixelSize: 17 }
    }

    Rectangle {
        id: sidebar; width: 190; anchors.top: header.bottom; anchors.bottom: parent.bottom
        color: "#292e38"
        ListView {
            anchors.fill: parent; clip: true; model: root.names; currentIndex: root.section
            delegate: Rectangle {
                objectName: "navigationRow" + index
                width: parent.width; height: 39
                color: index === root.section ? "#4b78a8" : mouse.containsMouse ? "#363d49" : "transparent"
                Text { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 14; text: modelData; color: "white" }
                MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.section = index }
            }
        }
    }

    Item {
        anchors.left: sidebar.right; anchors.right: parent.right; anchors.top: header.bottom; anchors.bottom: parent.bottom
        anchors.margins: 18
        Text { id: title; text: root.names[root.section]; color: "white"; font.pixelSize: 24 }
        Text { id: description; anchors.top: title.bottom; anchors.topMargin: 6; width: parent.width; text: root.details[root.section]; color: "#b8c0cc"; wrapMode: Text.WordWrap }
        Rectangle { anchors.top: description.bottom; anchors.topMargin: 12; width: parent.width; height: 1; color: "#4b5260" }

        // Controls / Controls 2
        Item {
            visible: root.section === 0 || root.section === 1
            anchors.top: description.bottom; anchors.topMargin: 30; width: parent.width; height: 380
            property bool checked: false
            Rectangle { id: button; width: 180; height: 42; radius: 5; color: buttonMouse.pressed ? "#315b82" : "#4b78a8"
                Text { anchors.centerIn: parent; text: "Push Button"; color: "white" }
                MouseArea { id: buttonMouse; anchors.fill: parent }
            }
            Rectangle { id: check; y: 62; width: 22; height: 22; color: parent.checked ? "#50b848" : "#3a404b"; border.color: "#87909e"
                Text { anchors.centerIn: parent; text: parent.parent.checked ? "✓" : ""; color: "white" }
                MouseArea { anchors.fill: parent; onClicked: parent.parent.checked = !parent.parent.checked }
            }
            Text { x: 32; y: 64; text: "Check box / switch"; color: "white" }
            Rectangle { y: 112; width: 360; height: 8; radius: 4; color: "#3a404b" }
            Rectangle { y: 112; width: sliderMouse.mouseX < 0 ? 0 : sliderMouse.mouseX > 360 ? 360 : sliderMouse.mouseX; height: 8; radius: 4; color: "#50b848" }
            MouseArea { id: sliderMouse; y: 96; width: 360; height: 40; drag.target: knob; drag.axis: Drag.XAxis; drag.minimumX: 0; drag.maximumX: 344 }
            Rectangle { id: knob; y: 104; x: 170; width: 16; height: 24; radius: 8; color: "white" }
            TextInput { y: 160; width: 360; height: 34; text: "Editable control"; color: "white"; selectionColor: "#50b848" }
            Row { y: 220; spacing: 10
                Repeater { model: ["Primary", "Secondary", "Disabled"]
                    Rectangle { width: 120; height: 36; radius: 4; color: index === 0 ? "#4b78a8" : index === 1 ? "#4b5260" : "#303641"; opacity: index === 2 ? 0.45 : 1
                        Text { anchors.centerIn: parent; text: modelData; color: "white" }
                    }
                }
            }
        }

        // Popups
        Item { visible: root.section === 2; anchors.top: description.bottom; anchors.topMargin: 30; width: parent.width; height: 400; property bool open: false
            Rectangle { width: 180; height: 42; color: "#4b78a8"; radius: 5; Text { anchors.centerIn: parent; text: "Open popup"; color: "white" }
                MouseArea { anchors.fill: parent; onClicked: parent.parent.open = true } }
            Rectangle { visible: parent.open; anchors.fill: parent; color: "#99000000"; z: 2; MouseArea { anchors.fill: parent; onClicked: parent.parent.open = false }
                Rectangle { anchors.centerIn: parent; width: 330; height: 170; radius: 8; color: "#f0f0f0"; border.color: "#606060"
                    Text { anchors.centerIn: parent; text: "Modal Qt Quick 1 popup\nClick outside to close"; horizontalAlignment: Text.AlignHCenter; color: "#202020" } }
            }
        }

        // Platform: the real Qt.labs FolderListModel shipped with Qt 4.
        Item { visible: root.section === 3; anchors.top: description.bottom; anchors.topMargin: 30; width: parent.width; height: 400
            FolderListModel { id: files; folder: "file:///"; showDirs: true; showOnlyReadable: true }
            Text { text: "Qt.labs.folderlistmodel 1.0 - file:///"; color: "#b8c0cc" }
            ListView { y: 28; width: 600; height: 300; clip: true; model: files
                delegate: Rectangle { width: 600; height: 34; color: index % 2 ? "#303641" : "#383f4b"
                    Text { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 10
                        text: "file:///  " + fileName; color: "white" }
                }
            }
        }

        // Input: text editing, validators, keyboard focus and the real labs gesture area.
        Item { visible: root.section === 7; anchors.top: description.bottom; anchors.topMargin: 30; width: parent.width; height: 400
            property bool narrow: width < 650
            Item { id: textInputColumn; width: parent.narrow ? parent.width : Math.min(350, parent.width * 0.56); height: 255
                Text { text: "Single-line input (integer validator):"; color: "#b8c0cc" }
                Rectangle { y: 28; width: Math.min(250, parent.width); height: 38; color: "#303641"; border.color: input.activeFocus ? "#50b848" : "#666e7a"
                    TextInput { id: input; anchors.fill: parent; anchors.margins: 8; text: "42"; color: "white"; selectionColor: "#50b848"
                        validator: IntValidator { bottom: 0; top: 9999 }
                        KeyNavigation.tab: editor
                    }
                }
                Rectangle { y: 84; width: parent.width; height: 170; color: "#303641"; border.color: editor.activeFocus ? "#50b848" : "#666e7a"
                    TextEdit { id: editor; anchors.fill: parent; anchors.margins: 8; text: "Multi-line TextEdit\nSelection, wrapping and clipboard interaction."; color: "white"; wrapMode: TextEdit.WordWrap } }
            }
            Rectangle { id: gesturePad; x: parent.narrow ? 0 : textInputColumn.width + 20; y: parent.narrow ? 275 : 0
                width: parent.narrow ? parent.width : parent.width - x; height: parent.narrow ? 105 : 254
                radius: 6; color: "#3a404b"; border.color: "#4b78a8"
                property string lastGesture: "Mouse: click here\nTouch: tap, hold, pan, pinch or swipe"
                Text { anchors.centerIn: parent; width: parent.width - 24; text: gesturePad.lastGesture; color: "white"; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter }
                GestureArea { anchors.fill: parent; focus: true
                    onTap: gesturePad.lastGesture = "Tap at " + Math.round(gesture.position.x) + ", " + Math.round(gesture.position.y)
                    onTapAndHold: gesturePad.lastGesture = "Tap and hold"
                    onPan: gesturePad.lastGesture = "Pan: " + Math.round(gesture.delta.x) + ", " + Math.round(gesture.delta.y)
                    onPinch: gesturePad.lastGesture = "Pinch scale: " + gesture.scaleFactor.toFixed(2)
                    onSwipe: gesturePad.lastGesture = "Swipe angle: " + Math.round(gesture.swipeAngle)
                }
                PinchArea { anchors.fill: parent
                    onPinchUpdated: gesturePad.scale = Math.max(0.8, Math.min(1.2, pinch.scale))
                    onPinchFinished: gesturePad.scale = 1
                }
                MouseArea { anchors.fill: parent; onClicked: gesturePad.lastGesture = "Mouse click at " + Math.round(mouse.x) + ", " + Math.round(mouse.y) }
            }
        }

        // Windows
        Item { visible: root.section === 4; anchors.top: description.bottom; anchors.topMargin: 30; width: parent.width; height: 400
            property bool narrow: width < 650
            Rectangle { id: childWindow; x: parent.narrow ? 0 : 30; y: 20; width: parent.narrow ? parent.width : Math.min(360, parent.width * 0.58); height: 220; color: "#303641"; border.color: "#7d8795"; border.width: 2
                Rectangle { width: parent.width; height: 32; color: "#4b78a8"; Text { anchors.centerIn: parent; text: "Draggable child surface"; color: "white" }
                    MouseArea { anchors.fill: parent; drag.target: childWindow } }
                Text { anchors.centerIn: parent; text: "QDeclarativeView is the real top-level window\nin Qt Quick 1"; color: "#d6dbe2"; horizontalAlignment: Text.AlignHCenter }
            }
            Flipable { id: flipCard; x: parent.narrow ? Math.max(0, (parent.width - width) / 2) : childWindow.x + childWindow.width + 35
                y: parent.narrow ? 260 : 45; width: 150; height: 170; property bool flipped: false
                front: Rectangle { anchors.fill: parent; radius: 8; color: "#4b78a8"; Text { anchors.centerIn: parent; text: "FRONT\n(click)"; color: "white"; horizontalAlignment: Text.AlignHCenter } }
                back: Rectangle { anchors.fill: parent; radius: 8; color: "#50a060"; Text { anchors.centerIn: parent; text: "BACK\nFlipable"; color: "white"; horizontalAlignment: Text.AlignHCenter } }
                transform: Rotation { origin.x: flipCard.width / 2; origin.y: flipCard.height / 2; axis.y: 1; angle: flipCard.flipped ? 180 : 0
                    Behavior on angle { NumberAnimation { duration: 450; easing.type: Easing.InOutQuad } } }
                MouseArea { anchors.fill: parent; onClicked: flipCard.flipped = !flipCard.flipped }
            }
        }

        // Accordion
        Column { visible: root.section === 5; anchors.top: description.bottom; anchors.topMargin: 30; width: parent.width; spacing: 8
            Repeater { model: 4; delegate: Item { width: 560; height: body.visible ? 112 : 38; property bool expanded: index === 0
                Rectangle { width: parent.width; height: 36; color: "#4b5260"; Text { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 12; text: (parent.expanded ? "▼ " : "▶ ") + "Section " + (index + 1); color: "white" }
                    MouseArea { anchors.fill: parent; onClicked: parent.parent.expanded = !parent.parent.expanded } }
                Rectangle { id: body; y: 38; width: parent.width; height: 72; visible: parent.expanded; color: "#303641"; Text { anchors.centerIn: parent; text: "Expandable model content " + (index + 1); color: "#c8ced8" } }
            } }
        }

        // TableView counterpart: an actual ListModel feeding a GridView.
        Item { visible: root.section === 6; anchors.top: description.bottom; anchors.topMargin: 30; width: parent.width; height: 380
            ListModel { id: tableModel
                ListElement { label: "R0 C0"; tone: "#2870b8" } ListElement { label: "R0 C1"; tone: "#408850" }
                ListElement { label: "R0 C2"; tone: "#a06030" } ListElement { label: "R0 C3"; tone: "#804890" }
                ListElement { label: "R1 C0"; tone: "#306890" } ListElement { label: "R1 C1"; tone: "#508048" }
                ListElement { label: "R1 C2"; tone: "#986038" } ListElement { label: "R1 C3"; tone: "#704880" }
            }
            GridView { anchors.fill: parent; cellWidth: 150; cellHeight: 74; model: tableModel; clip: true
                delegate: Rectangle { width: 142; height: 66; radius: 3; color: tone; border.color: "#20242c"
                    Text { anchors.centerIn: parent; text: label; color: "white" }
                }
            }
        }

        // Canvas counterpart: Qt Quick 1's image and dynamic-component toolkit.
        Item { visible: root.section === 8; anchors.top: description.bottom; anchors.topMargin: 30; width: parent.width; height: 380
            Flow { width: parent.width; spacing: 18
                Rectangle { width: 150; height: 150; color: "#303641"; border.color: "#606b78"
                    Image { anchors.fill: parent; anchors.margins: 8; source: "demo.svg"; fillMode: Image.PreserveAspectFit; smooth: true }
                    Text { anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; text: "Image"; color: "white" }
                }
                Rectangle { width: 150; height: 150; color: "#303641"; border.color: "#606b78"
                    BorderImage { objectName: "borderImageProbe"; anchors.fill: parent; anchors.margins: 18; source: "frame.svg"; border { left: 24; top: 24; right: 24; bottom: 24 } }
                    Text { anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; text: "BorderImage"; color: "white" }
                }
                Rectangle { width: 150; height: 150; color: "#303641"; border.color: "#606b78"
                    AnimatedImage {
                        objectName: "animatedImageProbe"
                        source: "data:image/gif;base64,R0lGODlhMAAwAHAAACH5BAEAAAIALAAAAAAwADAAgSAkLFC4SAAAAAAAAAJMhI+py+0Po5y02ouz3rz7D4biSJbmiabqyiJBewTy/K70rd46qvdnvzMBcaVhkGSc/ZK1IpNnzAFZPhigac1qt9yu9wsOi8fksnlcAAAh+QQBAAACACwAAAAAMAAwAIEgJCxQuEgAAAAAAAACTISPqcvtD6OctNqLs968+w+G4kiW5omm6soyQXsE8vyu9K3eOqr3Z78zAXGlYZBknP2StSKTZ8wBWT4YoGnNarfcrvcLDovH5LL5WwAAIfkEAQAAAgAsAAAAADAAMACBICQsULhIAAAAAAAAAkyEj6nL7Q+jnLTai7PevPsPhuJIluaJpurKQkF7BPL8rvSt3jqq92e/MwFxpWGQZJz9krUik2fMAVk+GKBpzWq33K73Cw6Lx+SyeVsAACH5BAEAAAIALAAAAAAwADAAgSAkLFC4SAAAAAAAAAJMhI+py+0Po5y02ouz3rz7D4biSJbmiabqylJBewTy/K70rd46qvdnvzMBcaVhkGSc/ZK1IpNnzAFZPhigac1qt9yu9wsOi8fkshlWAAAh+QQBAAACACwAAAAAMAAwAIEgJCxQuEgAAAAAAAACTISPqcvtD6OctNqLs968+w+G4kiW5omm6spiQXsE8vyu9K3eOqr3Z78zAXGlYZBknP2StSKTZ8wBWT4YoGnNarfcrvcLDovH5LJZVQAAIfkEAQAAAgAsAAAAADAAMACBICQsULhIAAAAAAAAAkyEj6nL7Q+jnLTai7PevPsPhuJIluaJpurKckF7BPL8rvSt3jqq92e/MwFxpWGQZJz9krUik2fMAVk+GKBpzWq33K73Cw6Lx+Sy2VQAACH5BAEAAAIALAAAAAAwADAAgSAkLFC4SAAAAAAAAAJMhI+py+0Po5y02ouz3rz7D4biSJbmiabqyoJBewTy/K70rd46qvdnvzMBcaVhkGSc/ZK1IpNnzAFZPhigac1qt9yu9wsOi8fksllUAAAh+QQBAAACACwAAAAAMAAwAIEgJCxQuEgAAAAAAAACTISPqcvtD6OctNqLs968+w+G4kiW5omm6sqSQXsE8vyu9K3eOqr3Z78zAXGlYdBllP2StSKTZ8wBWT4YoGnNarfcrvcLDovH5LLZUwAAOw=="
                        width: 48; height: 48; x: 10; y: 24
                        fillMode: Image.PreserveAspectFit; smooth: false; playing: true
                        SequentialAnimation on x {
                            loops: Animation.Infinite
                            NumberAnimation { to: 58; duration: 700; easing.type: Easing.InOutQuad }
                            NumberAnimation { to: 10; duration: 700; easing.type: Easing.InOutQuad }
                        }
                    }
                    Text { anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; text: "AnimatedImage"; color: "white" }
                }
                Rectangle { width: 150; height: 150; color: "#303641"; border.color: "#606b78"
                    Loader { id: sampleLoader; anchors.centerIn: parent; sourceComponent: loadedSample }
                    Component { id: loadedSample; Rectangle { width: 90; height: 90; radius: 45; color: "#e05048"; Text { anchors.centerIn: parent; text: "Loader"; color: "white" } } }
                }
            }
        }

        // Shapes counterpart. Qt Quick 1 has no drawing Shape item, so visible
        // shapes are composed from primitives; Path is separately demonstrated
        // in its real role as PathView trajectory data.
        Item { id: shapesPage; visible: root.section === 11; anchors.top: description.bottom; anchors.topMargin: 30; width: parent.width; height: 380
            Row { anchors.horizontalCenter: parent.horizontalCenter; y: 10; spacing: 42
                Item { id: composedStar; width: 120; height: 120
                    Repeater { model: 3; Rectangle { anchors.centerIn: parent; width: 100; height: 24; radius: 12; rotation: index * 60; color: index === 0 ? "#2870b8" : index === 1 ? "#50a060" : "#d07830" } }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.bottom; text: "composed star"; color: "white" }
                    RotationAnimation on rotation { from: 0; to: 360; duration: 3600; loops: Animation.Infinite; running: root.section === 11 }
                }
                Item { width: 120; height: 120
                    Rectangle { id: rotatedSquare; anchors.centerIn: parent; width: 76; height: 76; rotation: 45; color: "#8050a0"; border.color: "white"; border.width: 2
                        SequentialAnimation on scale { loops: Animation.Infinite; running: root.section === 11
                            NumberAnimation { to: 1.22; duration: 700; easing.type: Easing.InOutQuad }
                            NumberAnimation { to: 0.82; duration: 700; easing.type: Easing.InOutQuad }
                        }
                    }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.bottom; text: "rotation"; color: "white" }
                }
                Item { width: 120; height: 120
                    Rectangle { anchors.centerIn: parent; width: 100; height: 100; radius: 50; color: "#2870b8"
                        Rectangle { id: ringHole; anchors.centerIn: parent; width: 62; height: width; radius: width / 2; color: "#20242c"
                            SequentialAnimation on width { loops: Animation.Infinite; running: root.section === 11
                                NumberAnimation { to: 38; duration: 800; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 72; duration: 800; easing.type: Easing.InOutSine }
                            }
                        }
                    }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.bottom; text: "nested circles"; color: "white" }
                }
            }
            VisualItemModel { id: pathItems
                Rectangle { width: 24; height: 24; radius: 12; color: "#2870b8" }
                Rectangle { width: 24; height: 24; radius: 12; color: "#50a060" }
                Rectangle { width: 24; height: 24; radius: 12; color: "#d07830" }
                Rectangle { width: 24; height: 24; radius: 12; color: "#8050a0" }
            }
            Image { x: 0; y: 205; width: parent.width; height: 110; source: "path-guide.svg"; fillMode: Image.Stretch; smooth: true }
            PathView { y: 205; width: parent.width; height: 110; model: pathItems; pathItemCount: 4; interactive: false
                NumberAnimation on offset { from: 0; to: 4; duration: 5000; loops: Animation.Infinite; running: root.section === 11 }
                path: Path { startX: 40; startY: 65
                    PathLine { x: shapesPage.width * 0.28; y: 25 }
                    PathQuad { x: shapesPage.width * 0.55; y: 65; controlX: shapesPage.width * 0.42; controlY: 105 }
                    PathCubic { x: shapesPage.width - 40; y: 65; control1X: shapesPage.width * 0.67; control1Y: 5; control2X: shapesPage.width * 0.84; control2Y: 105 }
                    PathPercent { value: 1.0 }
                    PathAttribute { name: "itemScale"; value: 1.3 }
                }
            }
            Text { anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; text: "PathView trajectory: line + quadratic + cubic segments"; color: "#b8c0cc" }
        }

        // Particles: Qt 4's actual experimental particle engine, not a Repeater imitation.
        Item { visible: root.section === 9; anchors.top: description.bottom; anchors.topMargin: 30; width: parent.width; height: 380
            Row { anchors.fill: parent; spacing: 10
                property real panelWidth: (width - spacing * 2) / 3
                Rectangle { width: parent.panelWidth; height: 340; color: "#11151c"; border.color: "#4b5260"; clip: true
                    Particles { id: gravityParticles; anchors.fill: parent; source: "particle.xpm"; count: 42; emissionRate: 12; lifeSpan: 2200; angle: 270; angleDeviation: 45; velocity: 80
                        ParticleMotionGravity { yattractor: 700; xattractor: 105; acceleration: 24 } }
                    Text { anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; text: "Gravity"; color: "white" }
                    MouseArea { anchors.fill: parent; onClicked: gravityParticles.burst(25) }
                }
                Rectangle { width: parent.panelWidth; height: 340; color: "#11151c"; border.color: "#4b5260"; clip: true
                    Particles { id: linearParticles; anchors.fill: parent; source: "particle-linear.xpm"; count: 42; emissionRate: 12; lifeSpan: 2200; angle: 300; angleDeviation: 15; velocity: 75
                        ParticleMotionLinear { } }
                    Text { anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; text: "Linear"; color: "white" }
                    MouseArea { anchors.fill: parent; onClicked: linearParticles.burst(25) }
                }
                Rectangle { width: parent.panelWidth; height: 340; color: "#11151c"; border.color: "#4b5260"; clip: true
                    Particles { id: wanderParticles; anchors.fill: parent; source: "particle-wander.xpm"; count: 42; emissionRate: 12; lifeSpan: 2600; angle: 270; angleDeviation: 30; velocity: 70
                        ParticleMotionWander { xvariance: 45; yvariance: 25; pace: 80 } }
                    Text { anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; text: "Wander"; color: "white" }
                    MouseArea { anchors.fill: parent; onClicked: wanderParticles.burst(25) }
                }
            }
        }

        // Effects: the real OpenGL ShaderEffectItem and ShaderEffectSource module.
        Item { visible: root.section === 10; anchors.top: description.bottom; anchors.topMargin: 30; width: parent.width; height: 380
            Row { anchors.horizontalCenter: parent.horizontalCenter; y: 45; spacing: 30
                Rectangle { id: shaderSource; width: Math.min(220, (parent.parent.width - parent.spacing) / 2); height: 220; radius: 18
                    gradient: Gradient { GradientStop { position: 0; color: "#2870b8" } GradientStop { position: 1; color: "#e05048" } }
                    Text { anchors.centerIn: parent; text: "SOURCE"; color: "white"; font.pixelSize: 24 }
                    Text { anchors.top: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; text: "source item"; color: "#b8c0cc" }
                }
                Loader { width: shaderSource.width; height: 220
                    sourceComponent: root.shaderEffectsAvailable ? shaderComponent : undefined
                    Component { id: shaderComponent
                        ShaderEffectItem { objectName: "shaderEffectProbe"; width: shaderSource.width; height: 220
                            property variant source: ShaderEffectSource { sourceItem: shaderSource; hideSource: false }
                            property real pulse: 0.5 + 0.5 * Math.sin(effectClock.angle * Math.PI / 180)
                            fragmentShader: "varying highp vec2 qt_TexCoord0; uniform sampler2D source; uniform highp float pulse; void main() { lowp vec4 c = texture2D(source, qt_TexCoord0); lowp float g = dot(c.rgb, vec3(0.299, 0.587, 0.114)); gl_FragColor = vec4(mix(vec3(g), c.rgb, pulse), c.a); }"
                            Text { anchors.top: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; text: "shader output"; color: "#b8c0cc" }
                        }
                    }
                }
            }
            QtObject { id: effectClock; property real angle: 0 }
            NumberAnimation { target: effectClock; property: "angle"; from: 0; to: 360; duration: 2400; loops: Animation.Infinite; running: root.section === 10 }
            Text { anchors.horizontalCenter: parent.horizontalCenter; y: 305; text: root.shaderEffectsAvailable ? "Two objects: original source and animated GLSL result" : "GLSL shader effects are unavailable on this renderer."; color: "white" }
        }

        // Animation: several independent Qt Quick 1 animation mechanisms.
        Item { visible: root.section === 12; anchors.top: description.bottom; anchors.topMargin: 30; width: parent.width; height: 380
            Rectangle { id: animatedBox; x: 20; y: 80; width: 80; height: 80; radius: 12; color: "#4b78a8"
                Behavior on scale { SpringAnimation { spring: 2.2; damping: 0.25 } }
                MouseArea { anchors.fill: parent; onClicked: animatedBox.scale = animatedBox.scale === 1 ? 1.6 : 1 }
            }
            ParallelAnimation { running: root.section === 12; loops: Animation.Infinite
                SequentialAnimation { NumberAnimation { target: animatedBox; property: "x"; to: 500; duration: 1400; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: animatedBox; property: "x"; to: 20; duration: 1400; easing.type: Easing.InOutQuad } }
                RotationAnimation { target: animatedBox; property: "rotation"; from: 0; to: 360; duration: 2800 }
                ColorAnimation { target: animatedBox; property: "color"; from: "#4b78a8"; to: "#e05048"; duration: 1400 }
            }
            Text { y: 190; text: "Parallel + sequential + rotation + colour + spring behaviour"; color: "white" }
            Rectangle { id: stateBox; x: 40; y: 250; width: 80; height: 54; radius: 8; color: "#50a060"
                states: State { name: "expanded"; PropertyChanges { target: stateBox; x: 430; width: 170; color: "#8050a0" } }
                transitions: Transition { NumberAnimation { properties: "x,width"; duration: 600; easing.type: Easing.OutBack }
                    ColorAnimation { duration: 600 } }
                MouseArea { anchors.fill: parent; onClicked: stateBox.state = stateBox.state === "expanded" ? "" : "expanded" }
                Text { anchors.centerIn: parent; text: "State"; color: "white" }
            }
        }

        // ListView
        ListModel { id: fruitModel
            ListElement { group: "A"; name: "Apple"; tone: "#c04040" }
            ListElement { group: "A"; name: "Apricot"; tone: "#d08030" }
            ListElement { group: "B"; name: "Blueberry"; tone: "#4050b0" }
            ListElement { group: "B"; name: "Banana"; tone: "#c0a030" }
            ListElement { group: "G"; name: "Grape"; tone: "#804090" }
        }
        ListView { visible: root.section === 13; anchors.top: description.bottom; anchors.topMargin: 30; width: 600; height: 380; clip: true
            model: fruitModel; currentIndex: 0; section.property: "group"; section.criteria: ViewSection.FullString
            section.delegate: Rectangle { width: 600; height: 25; color: "#20242c"; Text { anchors.verticalCenter: parent.verticalCenter; text: "Section " + section; color: "#70c8ff" } }
            delegate: Rectangle { width: parent.width; height: 42; color: ListView.isCurrentItem ? "#4b78a8" : index%2 ? "#303641" : "#383f4b"
                Rectangle { x: 10; anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18; radius: 9; color: tone }
                Text { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 40; text: name; color: "white" }
                MouseArea { anchors.fill: parent; onClicked: parent.ListView.view.currentIndex = index }
            }
        }
        Flickable { visible: root.section === 13; x: 610; anchors.top: description.bottom; anchors.topMargin: 30; width: 90; height: 300
            contentWidth: width; contentHeight: 700; clip: true
            Column { width: parent.width; spacing: 4
                Repeater { model: 20; Rectangle { width: 86; height: 30; color: index % 2 ? "#303641" : "#4b5260"; Text { anchors.centerIn: parent; text: "Flick " + index; color: "white" } } }
            }
        }
    }
}
