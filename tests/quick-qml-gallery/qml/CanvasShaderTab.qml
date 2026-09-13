// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root

    RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        GroupBox {
            title: "Canvas"
            Layout.fillWidth: true
            Layout.fillHeight: true

            Canvas {
                id: canvas
                anchors.fill: parent
                property real phase: 0
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    ctx.fillStyle = "#f8fafc"
                    ctx.fillRect(0, 0, width, height)
                    ctx.lineWidth = 3
                    ctx.strokeStyle = "#0f766e"
                    ctx.beginPath()
                    for (var x = 0; x < width; x += 8) {
                        var y = height / 2 + Math.sin((x + phase) / 26) * height * 0.28
                        if (x === 0)
                            ctx.moveTo(x, y)
                        else
                            ctx.lineTo(x, y)
                    }
                    ctx.stroke()
                    ctx.fillStyle = "#1f2937"
                    ctx.font = "16px sans-serif"
                    ctx.fillText("Canvas 2D paint", 18, 28)
                }
                NumberAnimation on phase {
                    from: 0
                    to: 240
                    duration: 2200
                    loops: Animation.Infinite
                    onRunningChanged: canvas.requestPaint()
                }
                onPhaseChanged: requestPaint()
            }
        }

        GroupBox {
            title: "ShaderEffect and transforms"
            Layout.fillWidth: true
            Layout.fillHeight: true

            Rectangle {
                anchors.fill: parent
                color: "#111827"

                ShaderEffect {
                    id: shader
                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height) * 0.72
                    height: width
                    property real t: 0
                    fragmentShader: "
                        uniform lowp float qt_Opacity;
                        uniform highp float t;
                        varying highp vec2 qt_TexCoord0;
                        void main() {
                            highp vec2 p = qt_TexCoord0 - vec2(0.5, 0.5);
                            highp float d = length(p);
                            gl_FragColor = vec4(qt_TexCoord0.x, 0.65 + 0.25 * sin(t + d * 18.0), qt_TexCoord0.y, qt_Opacity);
                        }"
                    NumberAnimation on t {
                        from: 0
                        to: 6.28318
                        duration: 2400
                        loops: Animation.Infinite
                    }

                    RotationAnimation on rotation {
                        from: 0
                        to: 360
                        duration: 9000
                        loops: Animation.Infinite
                    }
                }

                Label {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: 12
                    color: "white"
                    text: "ShaderEffect"
                }
            }
        }
    }
}
