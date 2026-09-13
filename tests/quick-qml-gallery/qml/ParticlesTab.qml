// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Particles 2.15

Item {
    id: root
    property bool running: true

    RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        GroupBox {
            title: "Particle system"
            Layout.fillWidth: true
            Layout.fillHeight: true

            Rectangle {
                anchors.fill: parent
                color: "#0f172a"
                clip: true

                ParticleSystem {
                    id: system
                    running: root.running
                }

                Emitter {
                    id: emitter
                    system: system
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 18
                    width: parent.width * 0.7
                    height: 10
                    emitRate: 140
                    lifeSpan: 2600
                    lifeSpanVariation: 900
                    size: 10
                    sizeVariation: 8
                    velocity: AngleDirection {
                        angle: 270
                        angleVariation: 35
                        magnitude: 115
                        magnitudeVariation: 45
                    }
                    acceleration: PointDirection {
                        y: 22
                        xVariation: 18
                    }
                }

                Wander {
                    system: system
                    xVariance: 70
                    pace: 80
                }

                ImageParticle {
                    system: system
                    color: "#7dd3fc"
                    colorVariation: 0.45
                    alpha: 0.8
                    entryEffect: ImageParticle.Fade
                }

                Label {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: 12
                    color: "white"
                    text: "QtQuick.Particles"
                }

                Row {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: 12
                    spacing: 8

                    Button {
                        text: root.running ? "Pause" : "Run"
                        onClicked: root.running = !root.running
                    }
                    Button {
                        text: "Burst"
                        onClicked: emitter.burst(180)
                    }
                }
            }
        }

        GroupBox {
            title: "ShaderEffectSource"
            Layout.fillWidth: true
            Layout.fillHeight: true

            Rectangle {
                id: scene
                anchors.fill: parent
                color: "#f8fafc"

                Rectangle {
                    id: sourceItem
                    width: Math.min(parent.width, parent.height) * 0.42
                    height: width
                    anchors.centerIn: parent
                    radius: 12
                    color: "#fde68a"
                    border.color: "#92400e"

                    Text {
                        anchors.centerIn: parent
                        text: "source"
                        font.pixelSize: 22
                    }

                    RotationAnimation on rotation {
                        from: 0
                        to: 360
                        duration: 3600
                        loops: Animation.Infinite
                    }
                }

                ShaderEffectSource {
                    id: sourceTexture
                    sourceItem: sourceItem
                    hideSource: false
                    live: true
                    recursive: false
                }

                ShaderEffect {
                    width: sourceItem.width
                    height: sourceItem.height
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 26
                    property variant src: sourceTexture
                    property real pulse: 0
                    fragmentShader: "
                        uniform lowp float qt_Opacity;
                        uniform sampler2D src;
                        uniform highp float pulse;
                        varying highp vec2 qt_TexCoord0;
                        void main() {
                            highp vec2 uv = qt_TexCoord0;
                            highp float wave = sin((uv.x + uv.y + pulse) * 18.0) * 0.015;
                            lowp vec4 c = texture2D(src, uv + vec2(wave, -wave));
                            gl_FragColor = vec4(c.rgb * vec3(0.75, 0.95, 1.15), c.a * qt_Opacity);
                        }"
                    NumberAnimation on pulse {
                        from: 0
                        to: 6.28318
                        duration: 1800
                        loops: Animation.Infinite
                    }
                }

                Label {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: 12
                    text: "Live texture source"
                }
            }
        }
    }
}
