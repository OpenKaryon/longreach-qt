// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Exercises QtQuick.Shapes (ShapePath, gradients, dashed/joined strokes) - the
// Quick-side equivalent of QPainterPath in the graphics gallery.
import QtQuick 2.15
import QtQuick.Shapes 1.15

Item {
    Row {
        anchors.centerIn: parent
        spacing: 30

        // Filled + stroked star
        Shape {
            width: 120; height: 120
            ShapePath {
                strokeWidth: 3
                strokeColor: "#7a007a"
                fillColor: "#e6b4e6"
                startX: 60; startY: 4
                PathLine { x: 73; y: 42 }
                PathLine { x: 114; y: 42 }
                PathLine { x: 81; y: 66 }
                PathLine { x: 93; y: 106 }
                PathLine { x: 60; y: 82 }
                PathLine { x: 27; y: 106 }
                PathLine { x: 39; y: 66 }
                PathLine { x: 6; y: 42 }
                PathLine { x: 47; y: 42 }
                PathLine { x: 60; y: 4 }
            }
        }

        // Gradient-filled rounded rect via cubic path
        Shape {
            width: 120; height: 120
            ShapePath {
                strokeWidth: 2
                strokeColor: "#204060"
                fillGradient: LinearGradient {
                    x1: 0; y1: 0; x2: 120; y2: 120
                    GradientStop { position: 0.0; color: "#1e3cc8" }
                    GradientStop { position: 1.0; color: "#c83c1e" }
                }
                startX: 10; startY: 60
                PathArc { x: 110; y: 60; radiusX: 50; radiusY: 50; useLargeArc: true }
                PathArc { x: 10; y: 60; radiusX: 50; radiusY: 50; useLargeArc: true }
            }
        }

        // Dashed stroke
        Shape {
            width: 120; height: 120
            ShapePath {
                strokeWidth: 4
                strokeColor: "#208020"
                strokeStyle: ShapePath.DashLine
                dashPattern: [4, 2]
                fillColor: "transparent"
                startX: 10; startY: 10
                PathLine { x: 110; y: 10 }
                PathLine { x: 110; y: 110 }
                PathLine { x: 10; y: 110 }
                PathLine { x: 10; y: 10 }
            }
        }
    }
}
