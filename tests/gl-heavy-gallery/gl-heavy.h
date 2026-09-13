// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Declarations shared between the gl-heavy gallery (visual) and its self-test.
// gl-heavy bundles the three GPU/scene-graph-heavy modules that don't fit the
// other apps: Qt3D, QtCharts, QtDataVisualization.
#ifndef GL_HEAVY_H
#define GL_HEAVY_H

class SmokeReporter;
class QWidget;

// Visual gallery: each returns a widget the caller puts in a QTabWidget page.
QWidget *buildQt3DTab();
QWidget *buildChartsTab();
QWidget *buildDataVisTab();

// Headless behavioural / construction checks (--selftest). Qt3D and
// DataVisualization are QNode-graph APIs - objects can be built and wired
// (parented, geometry attached, materials assigned) without a running aspect
// engine or GPU context, so these checks exercise real API surface headlessly.
void checkQt3DNodes(SmokeReporter &r);
void checkQt3DMaterialsAndMeshes(SmokeReporter &r);
void checkQt3DFrameGraphAndInput(SmokeReporter &r);
void checkQt3DAnimation(SmokeReporter &r);
void checkQt3DCoreAndChanges(SmokeReporter &r);
void checkQt3DRenderStatesExtra(SmokeReporter &r);
void checkQt3DFrameGraphExtra(SmokeReporter &r);
void checkQt3DGeometryMaterialsExtra(SmokeReporter &r);
void checkQt3DTexturesAndShadersExtra(SmokeReporter &r);
void checkQt3DInputAndAnimationExtra(SmokeReporter &r);
void checkQt3DQuickBridgeExtra(SmokeReporter &r);
void checkCharts(SmokeReporter &r);
void checkDataVis(SmokeReporter &r);
void checkQt6GeometryViews(SmokeReporter &r);
void checkQt6GraphsWidgets(SmokeReporter &r);

#endif // GL_HEAVY_H
