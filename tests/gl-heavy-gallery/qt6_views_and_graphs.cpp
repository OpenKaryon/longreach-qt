// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// The Qt 6 replacements for things Qt 5's Qt3D did differently, and QtGraphs -
// the module Qt 6 introduced beside QtDataVisualization.
//
// Qt 6 split a mesh in two: a QGeometryView describes how to interpret a
// QGeometry, and a QGeometryRenderer draws one. Qt 5 had only the renderer, so
// the whole view side is new API the suite inherited no reason to name. The
// same split produced QBoundingVolume and QPickingProxy, and moved the aspect
// and settings for the core aspect into classes of their own.
//
// Nothing here needs a running Qt3D aspect engine: these are scene-graph nodes,
// which is to say QObjects with properties, until an engine is given the tree.
//
// QtCharts is deliberately not included here. Qt refuses to compile a
// translation unit that pulls in both QtCharts and QtGraphs - they share class
// names - so QColorAxis, the other Qt 6 addition covered in this batch, lives
// in charts_selftest.cpp with the rest of QtCharts.
#include "../common/smokecheck.h"
#include "gl-heavy.h"

#if QT_VERSION_MAJOR >= 6
#include <Qt3DCore/QBoundingVolume>
#include <Qt3DCore/QCoreAspect>
#include <Qt3DCore/QCoreSettings>
#include <Qt3DCore/QEntity>
#include <Qt3DCore/QGeometry>
#include <Qt3DCore/QGeometryView>

#include <Qt3DExtras/QConeGeometryView>
#include <Qt3DExtras/QCuboidGeometryView>
#include <Qt3DExtras/QCylinderGeometryView>
#include <Qt3DExtras/QPlaneGeometryView>
#include <Qt3DExtras/QSphereGeometryView>
#include <Qt3DExtras/QTorusGeometryView>

#include <Qt3DRender/QPickingProxy>
#endif

#ifdef SMOKE_HAVE_GRAPHS
#include <QGraphsTheme>
#endif

void checkQt6GeometryViews(SmokeReporter &r)
{
    r.check("qt3d/geometry-views", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        // Every node is parented into a scene tree: on 6.8.4 a stack-allocated
        // QBoundingVolume pointing at a stack-allocated QGeometryView corrupts the heap.
        Qt3DCore::QEntity root;

        auto *cone = new Qt3DExtras::QConeGeometryView(&root);
        cone->setRings(8);
        cone->setSlices(12);
        auto *cuboid = new Qt3DExtras::QCuboidGeometryView(&root);
        cuboid->setXExtent(2.0f);
        auto *cylinder = new Qt3DExtras::QCylinderGeometryView(&root);
        cylinder->setRadius(1.5f);
        auto *plane = new Qt3DExtras::QPlaneGeometryView(&root);
        plane->setWidth(3.0f);
        auto *sphere = new Qt3DExtras::QSphereGeometryView(&root);
        sphere->setRadius(2.0f);
        sphere->setRings(16);
        auto *torus = new Qt3DExtras::QTorusGeometryView(&root);
        torus->setMinorRadius(0.25f);

        // Reached through the real base every shape view derives from, which
        // is what a custom mesh would subclass.
        Qt3DCore::QGeometryView *viewBase = sphere;
        viewBase->setInstanceCount(2);
        viewBase->setPrimitiveType(Qt3DCore::QGeometryView::Triangles);

        auto *volume = new Qt3DCore::QBoundingVolume(&root);
        volume->setView(viewBase);

        QStringList misses;
        if (cone->rings() != 8 || cone->slices() != 12) misses << QStringLiteral("cone");
        if (!qFuzzyCompare(cuboid->xExtent(), 2.0f)) misses << QStringLiteral("cuboid");
        if (!qFuzzyCompare(cylinder->radius(), 1.5f)) misses << QStringLiteral("cylinder");
        if (!qFuzzyCompare(plane->width(), 3.0f)) misses << QStringLiteral("plane");
        if (sphere->rings() != 16) misses << QStringLiteral("sphere");
        if (!qFuzzyCompare(torus->minorRadius(), 0.25f)) misses << QStringLiteral("torus");
        if (viewBase->instanceCount() != 2) misses << QStringLiteral("view");
        if (viewBase->geometry() == nullptr) misses << QStringLiteral("geometry");
        if (volume->view() != viewBase) misses << QStringLiteral("boundingvolume");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("the geometry-view split is Qt 6 only"));
        return false;
#endif
    });

    r.check("qt3d/core-aspect-settings-and-picking-proxy", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        // Qt 5 had no core aspect to configure: the settings that live here
        // were spread across the render aspect.
        Qt3DCore::QCoreAspect coreAspect;
        Qt3DCore::QCoreSettings settings;
        settings.setBoundingVolumesEnabled(false);

        Qt3DCore::QEntity root;
        // QPickingProxy adds nothing of its own: it is a QBoundingVolume that
        // marks a cheaper shape to hit-test against than the visible mesh.
        auto *proxy = new Qt3DRender::QPickingProxy(&root);
        Qt3DCore::QBoundingVolume *proxyBase = proxy;
        root.addComponent(proxy);

        QStringList misses;
        if (coreAspect.parent() != nullptr) misses << QStringLiteral("coreaspect");
        if (settings.boundingVolumesEnabled()) misses << QStringLiteral("coresettings");
        if (proxyBase->view() != nullptr) misses << QStringLiteral("pickingproxy");
        if (!root.components().contains(proxy)) misses << QStringLiteral("component");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QCoreAspect and QPickingProxy are Qt 6 only"));
        return false;
#endif
    });

    r.check("graphs/theme", [&](QString &d) {
#ifdef SMOKE_HAVE_GRAPHS
        QStringList misses;
        // QtGraphs is Qt 6's successor to QtDataVisualization; the theme is
        // the part of it that needs no 3D surface to exist.
        QGraphsTheme theme;
        theme.setColorScheme(QGraphsTheme::ColorScheme::Dark);
        theme.setTheme(QGraphsTheme::Theme::QtGreen);
        theme.setLabelsVisible(false);
        if (theme.colorScheme() != QGraphsTheme::ColorScheme::Dark)
            misses << QStringLiteral("colorscheme");
        if (theme.theme() != QGraphsTheme::Theme::QtGreen) misses << QStringLiteral("theme");
        if (theme.labelsVisible()) misses << QStringLiteral("labels");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
#ifdef SMOKE_GRAPHS_STATIC_SYMBOL_COLLISION
        r.skip(d, QStringLiteral("static QtCharts and QtGraphs export colliding QValueAxis symbols"));
#else
        r.skip(d, QStringLiteral("QtGraphs is not in this SDK"));
#endif
        return false;
#endif
    });
}
