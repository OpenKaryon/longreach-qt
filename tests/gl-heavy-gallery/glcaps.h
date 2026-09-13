// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// What this machine's OpenGL can actually do, asked once and shared by the
// gallery tabs.
//
// The gallery used to assume a working modern context and show a black
// rectangle when there was not one. On the XP box - VMware SVGA3D with Mesa
// 10.0, which tops out at OpenGL 2.1 - that produced three different silent
// failures at once: Qt3D drew some entities and not others, Q3DSurface drew
// nothing, and clicking the surface tab left the two that had been working
// broken as well. None of them said why.
//
// A tab that cannot work should say so, in the same spirit as a check that
// skips itself with a reason rather than failing.
#ifndef GLCAPS_H
#define GLCAPS_H

#include <QString>

class QWidget;

struct GlCaps
{
    bool contextCreated = false;
    int major = 0;
    int minor = 0;
    int vertexTextureUnits = 0;   // 0 means no vertex texture fetch at all
    bool gpuShader4 = false;      // GL_EXT_gpu_shader4, needed by the flat qualifier
    QString vendor;
    QString renderer;
    QString version;

    int versionValue() const { return major * 10 + minor; }

    // Qt3D's OpenGL renderer wants a 3.2 core context. Below that it still
    // brings up an aspect engine and draws part of a scene, which is worse than
    // failing outright: what you get is a window with some entities missing.
    bool qt3dFullySupported() const { return versionValue() >= 32; }

    // Q3DSurface's renderer compiles a shader using the flat qualifier and
    // samples textures in the vertex stage. Without either it renders nothing,
    // and on Mesa 10.0 it leaves the shared context in a state the sibling
    // graphs do not recover from.
    bool surfaceSupported() const { return vertexTextureUnits > 0 && gpuShader4; }

    QString describe() const;
};

// Probed once on first call, on an offscreen surface, before any tab is built.
const GlCaps &glCaps();

// A framed, word-wrapped explanation to put where a 3D view would have gone.
QWidget *makeUnsupportedPlaceholder(const QString &title, const QString &why);

#endif // GLCAPS_H
