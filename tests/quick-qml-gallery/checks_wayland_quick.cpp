// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// The Qt Quick half of QtWaylandCompositor.
//
// These live here rather than beside the other Wayland checks in console/ for
// the obvious reason - they are QQuickItems and need QtQuick - and for a less
// obvious one: they exist only when Qt itself was configured with Quick support
// for the compositor. That is a build-time feature of the module rather than a
// module of its own, so the guard is QT_CONFIG(wayland_compositor_quick), which
// is how qtwayland's own headers guard the same declarations.
//
// Same rule as the console-side checks: nothing calls
// QWaylandCompositor::create(), so no socket is bound and no display server is
// involved. A QWaylandQuickCompositor with no window and no client is exactly
// what a compositor looks like in the moment before it starts.
#include "../common/smokecheck.h"

#ifdef SMOKE_HAVE_WAYLANDCOMPOSITOR
#  include <QtWaylandCompositor/qtwaylandcompositorglobal.h>
#  if QT_CONFIG(wayland_compositor_quick)
#    define SMOKE_WAYLAND_QUICK 1
#    include <QWaylandQuickCompositor>
#    include <QWaylandQuickItem>
#    include <QWaylandQuickOutput>
#    include <QWaylandQuickShellIntegration>
#    include <QWaylandQuickShellSurfaceItem>
#    include <QWaylandQuickSurface>
#    include <QWaylandQuickXdgOutputV1>
#    include <QQuickItem>
#    include <QString>
#  endif
#endif

void checkWaylandQuick(SmokeReporter &r)
{
#ifndef SMOKE_WAYLAND_QUICK
    r.check("wayland-quick/module-available", [&](QString &d) {
        r.skip(d, QStringLiteral("QtWaylandCompositor with Quick support is not in this SDK"));
        return false;
    });
#else
    r.check("wayland-quick/compositor-and-output", [](QString &d) {
        // The Quick compositor is the same compositor with a scene graph
        // attached, so the create()-is-the-line rule holds unchanged here.
        QWaylandQuickCompositor compositor;
        QWaylandQuickOutput output;
        output.setCompositor(&compositor);
        output.setAutomaticFrameCallback(false);

        d = QStringLiteral("quick compositor created=%1, output frame callback %2")
                .arg(int(compositor.isCreated()))
                .arg(output.automaticFrameCallback() ? QLatin1String("on") : QLatin1String("off"));
        return !compositor.isCreated()
            && output.compositor() == &compositor
            && !output.automaticFrameCallback()
            && compositor.metaObject()->inherits(&QWaylandCompositor::staticMetaObject);
    });

    // Three checks, one per object: a compositor surface, the item that shows one,
    // and the shell surface item. QWaylandQuickItem::setSurface() is not called: on
    // a surface without a compositor it dereferences the missing compositor.
    r.check("wayland-quick/surface", [](QString &d) {
        QWaylandQuickSurface surface;
        d = QStringLiteral("%1 constructed with no compositor")
                .arg(QString::fromLatin1(surface.metaObject()->className()));
        return surface.compositor() == nullptr
            && surface.metaObject()->inherits(&QWaylandSurface::staticMetaObject);
    });

    r.check("wayland-quick/item", [](QString &d) {
        // A QQuickItem that shows a client surface. Constructed with no surface,
        // which is what a QML compositor has before a client connects.
        QWaylandQuickItem item;
        QQuickItem *asQuickItem = &item;
        d = QStringLiteral("%1 as a QQuickItem, surface %2")
                .arg(QString::fromLatin1(item.metaObject()->className()))
                .arg(item.surface() ? QLatin1String("set") : QLatin1String("none"));
        return item.surface() == nullptr && asQuickItem == &item
            && item.metaObject()->inherits(&QQuickItem::staticMetaObject);
    });

    r.check("wayland-quick/shell-surface-item", [](QString &d) {
        QWaylandQuickShellSurfaceItem shellItem;
        d = QStringLiteral("%1, shell surface %2")
                .arg(QString::fromLatin1(shellItem.metaObject()->className()))
                .arg(shellItem.shellSurface() ? QLatin1String("set") : QLatin1String("none"));
        return shellItem.shellSurface() == nullptr
            && shellItem.metaObject()->inherits(&QWaylandQuickItem::staticMetaObject);
    });

    r.check("wayland-quick/shell-item-move-item", [](QString &d) {
        QWaylandQuickShellSurfaceItem shellItem;
        QQuickItem *moveItem = shellItem.moveItem();
        d = QStringLiteral("moveItem is %1")
                .arg(moveItem == &shellItem ? QLatin1String("the item itself")
                                            : (moveItem ? QLatin1String("another item")
                                                        : QLatin1String("null")));
        return moveItem != nullptr;
    });

    r.check("wayland-quick/shell-integration-and-xdg-output", [](QString &d) {
        // QWaylandQuickShellIntegration is the hook a shell extension provides
        // so a QML compositor can drive it; QWaylandQuickXdgOutputV1 is the
        // QML-instantiable form of the xdg-output description.
        QWaylandQuickShellIntegration integration;
        QWaylandQuickXdgOutputV1 xdgOutput;
        d = QStringLiteral("integration parent=%1, xdg output manager=%2")
                .arg(integration.parent() ? QLatin1String("set") : QLatin1String("none"))
                .arg(xdgOutput.manager() ? QLatin1String("set") : QLatin1String("none"));
        return integration.parent() == nullptr
            && integration.metaObject()->inherits(&QObject::staticMetaObject)
            && xdgOutput.manager() == nullptr && xdgOutput.output() == nullptr;
    });
#endif
}
