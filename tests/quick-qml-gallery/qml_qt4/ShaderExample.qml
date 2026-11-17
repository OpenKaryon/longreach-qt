// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick 1.1
import Qt.labs.shaders 1.0

ShaderEffectItem {
    id: effect
    objectName: "shaderEffectProbe"
    property variant sampleSource
    property real pulse: 0.5
    property variant source: ShaderEffectSource { sourceItem: effect.sampleSource; hideSource: false }
    fragmentShader: "varying highp vec2 qt_TexCoord0; uniform sampler2D source; uniform highp float pulse; void main() { lowp vec4 c = texture2D(source, qt_TexCoord0); lowp float g = dot(c.rgb, vec3(0.299, 0.587, 0.114)); gl_FragColor = vec4(mix(vec3(g), c.rgb, pulse), c.a); }"
    Text { anchors.top: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; text: "shader output"; color: "#b8c0cc" }
}
