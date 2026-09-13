// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// gl-heavy - visual Qt3D / QtCharts / QtDataVisualization showcase + headless
// self-test. Bundles the three GPU/scene-graph-heavy modules that don't fit
// the console/widgets/graphics/quick-qml apps.
//
//   gl-heavy-gallery              show the gallery window (Qt3D mesh/material
//                                 catalogue, QtCharts series catalogue,
//                                 QtDataVisualization Bars/Scatter/Surface)
//   gl-heavy-gallery --selftest   headless PASS/FAIL over the same modules'
//                                 node-graph APIs (no window shown)
#include "../common/smokecheck.h"
#include "gl-heavy.h"
#include "glcaps.h"

#include <QApplication>
#include <QMainWindow>
#include <QTabWidget>
#include <QStatusBar>

static bool dataVisVisualBrokenOnThisDriver(const GlCaps &caps)
{
    // No context at all (the offscreen platform with no X server behind it):
    // the Q3D windows dereference a null context while building their
    // renderer, so the tab crashed the gallery instead of explaining itself.
    if (!caps.contextCreated)
        return true;
#ifdef Q_OS_LINUX
    // Ubuntu 16.04 i386 under VMware SVGA3D/Mesa 18 exposes and updates the
    // embedded Q3D windows, but no DataVisualization frame is produced. Leave
    // Windows XP alone: its Bars and Scatter tabs render with local workarounds.
    return !caps.surfaceSupported()
            && caps.vendor.contains(QStringLiteral("VMware"), Qt::CaseInsensitive)
            && caps.renderer.contains(QStringLiteral("SVGA3D"), Qt::CaseInsensitive);
#else
    Q_UNUSED(caps);
    return false;
#endif
}

static int runSelfTest()
{
    SmokeReporter r("gl-heavy");
    checkQt3DNodes(r);
    checkQt3DMaterialsAndMeshes(r);
    checkQt3DFrameGraphAndInput(r);
    checkQt3DAnimation(r);
    checkQt3DCoreAndChanges(r);
    checkQt3DRenderStatesExtra(r);
    checkQt3DFrameGraphExtra(r);
    checkQt3DGeometryMaterialsExtra(r);
    checkQt3DTexturesAndShadersExtra(r);
    checkQt3DInputAndAnimationExtra(r);
    checkQt3DQuickBridgeExtra(r);
    checkCharts(r);
    checkDataVis(r);
    checkQt6GeometryViews(r);
    checkQt6GraphsWidgets(r);
    return r.summary();
}

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);

    if (app.arguments().contains("--selftest"))
        return runSelfTest();

    // A log of what a driver did is not worth much without naming the driver,
    // and the caps probe is the same one the tabs use to decide what they can
    // show - so the log states the reason for whatever placeholders appear.
    const GlCaps &caps = glCaps();
    qInfo("gl-heavy: OpenGL %d.%d | %s | %s | %s",
          caps.major, caps.minor, qPrintable(caps.vendor),
          qPrintable(caps.renderer), qPrintable(caps.version));
    qInfo("gl-heavy: vertex texture units=%d, GL_EXT_gpu_shader4=%s, "
          "Qt3D fully supported=%s, Q3DSurface supported=%s",
          caps.vertexTextureUnits, caps.gpuShader4 ? "yes" : "no",
          caps.qt3dFullySupported() ? "yes" : "no",
          caps.surfaceSupported() ? "yes" : "no");
    QMainWindow win;
    win.setWindowTitle("Qt gl-heavy Gallery - " QT_VERSION_STR);
    auto *tabs = new QTabWidget;
    tabs->addTab(buildChartsTab(), "Charts");
    if (dataVisVisualBrokenOnThisDriver(caps)) {
        tabs->addTab(makeUnsupportedPlaceholder(
            QStringLiteral("QtDataVisualization visual gallery is disabled on this OpenGL driver"),
            caps.contextCreated
                ? QStringLiteral("The DataVisualization API is still covered by --selftest. "
                                 "This VMware SVGA3D/Mesa driver exposes and updates the "
                                 "embedded Q3D windows, but does not produce reliable frames, "
                                 "so the visual tab is left as a placeholder.")
                : QStringLiteral("The DataVisualization API is still covered by --selftest. "
                                 "No OpenGL context could be created here, and the Q3D "
                                 "windows need one.")),
            "DataVisualization");
    } else {
        tabs->addTab(buildDataVisTab(), "DataVisualization");
    }
    if (!caps.qt3dFullySupported()) {
        tabs->addTab(makeUnsupportedPlaceholder(
            QStringLiteral("Qt3D visual gallery is disabled on this OpenGL driver"),
            QStringLiteral("The Qt3D API is still covered by --selftest. "
                           "This driver does not provide the OpenGL level needed to render "
                           "this visual scene reliably enough for a gallery.")),
            "Qt3D");
    } else {
        tabs->addTab(buildQt3DTab(), "Qt3D");
    }
    win.setCentralWidget(tabs);
    win.statusBar()->showMessage(QStringLiteral("gl-heavy gallery - Qt3D / Charts / DataVisualization"));
    win.resize(820, 620);
    win.show();
    return app.exec();
}
