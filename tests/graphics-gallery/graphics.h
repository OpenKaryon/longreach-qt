// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Declarations shared between the graphics gallery (visual) and its self-test.
#ifndef GRAPHICS_H
#define GRAPHICS_H

class SmokeReporter;
class QWidget;

// Visual gallery: a QMainWindow central widget with painter/animation/effects
// tabs. Returns a widget the caller parents into a window.
QWidget *buildGraphicsGallery();

// Pop up a frameless translucent window, or an opaque region-shaped window
// on Win9x/NT4 where layered alpha is unavailable. Parented to `parent`.
void showShapedWindow(QWidget *parent);

// Headless behavioural checks (--selftest). Each renders/animates and asserts.
void checkPainter(SmokeReporter &r);
void checkPaths(SmokeReporter &r);
void checkTransforms(SmokeReporter &r);
void checkImageOps(SmokeReporter &r);
void checkAnimations(SmokeReporter &r);
void checkStateMachine(SmokeReporter &r);
void checkGraphicsEffectsAndItems(SmokeReporter &r);

#endif // GRAPHICS_H
