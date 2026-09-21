// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// The rest of QtWaylandCompositor: the shell surfaces, the extension base
// classes and the helpers that hang off a seat or a surface.
//
// Same rule as checks_wayland.cpp next door - nothing calls
// QWaylandCompositor::create(), so no socket is bound and no client is needed.
// What is different here is how the abstract half of the module gets covered.
// QWaylandShell, QWaylandShellSurface and QWaylandCompositorExtension are bases
// nobody instantiates directly, and the three Template classes are CRTP:
// QWaylandWlShell *is a* QWaylandShellTemplate<QWaylandWlShell>, and the
// template's own methods are the ones a shell inherits. So the way to reach
// them is through a concrete shell rather than by trying to build one, and
// that is what the type-relationship assertions below do - they are not a
// weaker substitute for constructing something, they are how these classes are
// used at all.
#include "../common/smokecheck.h"

#ifdef SMOKE_HAVE_WAYLANDCOMPOSITOR
#include <QWaylandCompositor>
#include <QWaylandCompositorExtension>
#include <QWaylandDrag>
#include <QWaylandIviApplication>
#include <QWaylandIviSurface>
#include <QWaylandOutput>
#include <QWaylandSeat>
#include <QWaylandShell>
#include <QWaylandShellSurface>
#include <QWaylandSurface>
#include <QWaylandSurfaceGrabber>
#include <QWaylandWlShell>
#include <QWaylandXdgOutputManagerV1>
#include <QWaylandXdgOutputV1>
#include <QWaylandViewporter>
#include <QWaylandXdgShell>

#if QT_VERSION_MAJOR < 6
// The xdg-shell protocol went through two unstable revisions before it was
// standardised; Qt 5 still ships a compositor implementation of each and Qt 6
// dropped them all.
#  include <QWaylandWlScaler>
#  include <QWaylandXdgShellV5>
#  include <QWaylandXdgShellV6>
#endif

#include <QObject>
#include <QPoint>
#include <QSize>
#include <QString>

#include <type_traits>
#endif

void checkWaylandShells(SmokeReporter &r)
{
#ifndef SMOKE_HAVE_WAYLANDCOMPOSITOR
    r.check("wayland/shells-module-available", [&](QString &d) {
        r.skip(d, QStringLiteral("QtWaylandCompositor is Linux-only and not in this SDK"));
        return false;
    });
#else
    r.check("wayland/extension-base-chain", [](QString &d) {
        // Every extension in this module sits on the same three-step chain, and
        // the middle step is a template parameterised on the extension itself.
        QWaylandCompositor compositor;
        QWaylandWlShell shell(&compositor);
        shell.setFocusPolicy(QWaylandShell::ManualFocus);

        QWaylandShell *asShell = &shell;
        QWaylandCompositorExtension *asExtension = &shell;
        QWaylandObject *asObject = &compositor;

        // An extension knows its container from the constructor but registers with it
        // only in initialize(), so findIn() is null here.
        QWaylandWlShell *found = QWaylandWlShell::findIn(&compositor);
        d = QStringLiteral("container set=%1, registered=%2, focus policy %3")
                .arg(int(asExtension->extensionContainer() == &compositor))
                .arg(found ? QLatin1String("yes") : QLatin1String("not until initialize"))
                .arg(int(asShell->focusPolicy()));
        return std::is_base_of<QWaylandShellTemplate<QWaylandWlShell>, QWaylandWlShell>::value
            && std::is_base_of<QWaylandShell, QWaylandWlShell>::value
            && std::is_base_of<QWaylandCompositorExtension, QWaylandShell>::value
            && std::is_base_of<QWaylandObject, QWaylandCompositor>::value
            && asShell->focusPolicy() == QWaylandShell::ManualFocus
            && asExtension->extensionContainer() == &compositor
            && !asExtension->isInitialized()
            && found == nullptr
            && asObject == &compositor;
    });

    r.check("wayland/shell-surfaces", [](QString &d) {
        // The per-window half of each shell protocol. Default-constructed they
        // are not yet bound to a surface - which is the state the compositor
        // sees between a client asking for a shell surface and the surface
        // being committed.
        QWaylandWlShellSurface wlSurface;
        QWaylandXdgSurface xdgSurface;
        QWaylandIviSurface iviSurface;

        // The base carries the window type and nothing else: surface() lives on
        // each concrete shell surface, not on QWaylandShellSurface.
        QWaylandShellSurface *asShellSurface = &wlSurface;
        d = QStringLiteral("wl=%1 xdg=%2 ivi=%3, window type %4, all unbound")
                .arg(QString::fromLatin1(wlSurface.metaObject()->className()))
                .arg(QString::fromLatin1(xdgSurface.metaObject()->className()))
                .arg(QString::fromLatin1(iviSurface.metaObject()->className()))
                .arg(int(asShellSurface->windowType()));
        return std::is_base_of<QWaylandShellSurfaceTemplate<QWaylandWlShellSurface>,
                               QWaylandWlShellSurface>::value
            && std::is_base_of<QWaylandShellSurface, QWaylandWlShellSurface>::value
            && asShellSurface->windowType() == Qt::WindowType::Window
            && wlSurface.surface() == nullptr
            && xdgSurface.surface() == nullptr
            && iviSurface.surface() == nullptr;
    });

    r.check("wayland/drag-and-surface-grabber", [](QString &d) {
        // The drag object comes from a seat; a grabber is bound to one surface.
        // grab() is not called: with no buffer there is nothing to grab.
        QWaylandCompositor compositor;
        QWaylandSeat seat(&compositor);
        QWaylandSurface surface;
        QWaylandSurfaceGrabber grabber(&surface);

        QWaylandDrag *drag = seat.drag();
        d = QStringLiteral("seat drag=%1, grabber parent=%2")
                .arg(drag ? QLatin1String("present") : QLatin1String("none"))
                .arg(grabber.parent() ? QLatin1String("set") : QLatin1String("none"));
        return drag != nullptr
            && drag->metaObject()->inherits(&QObject::staticMetaObject)
            && !drag->visible()
            && grabber.parent() == nullptr;
    });

    r.check("wayland/xdg-output", [](QString &d) {
        // xdg-output describes an output in logical coordinates, which is what
        // a client needs when the compositor scales. The manager publishes one
        // per output; both halves are constructible before create().
        QWaylandCompositor compositor;
        QWaylandXdgOutputManagerV1 manager(&compositor);
        QWaylandOutput output;
        QWaylandXdgOutputV1 xdgOutput(&output, &manager);
        xdgOutput.setLogicalPosition(QPoint(10, 20));
        xdgOutput.setLogicalSize(QSize(1280, 720));
        xdgOutput.setName(QStringLiteral("smoke-output"));
        xdgOutput.setDescription(QStringLiteral("headless check"));

        d = QStringLiteral("\"%1\" at %2,%3 sized %4x%5")
                .arg(xdgOutput.name())
                .arg(xdgOutput.logicalPosition().x()).arg(xdgOutput.logicalPosition().y())
                .arg(xdgOutput.logicalSize().width()).arg(xdgOutput.logicalSize().height());
        return xdgOutput.logicalPosition() == QPoint(10, 20)
            && xdgOutput.logicalSize() == QSize(1280, 720)
            && xdgOutput.name() == QStringLiteral("smoke-output")
            && xdgOutput.description() == QStringLiteral("headless check")
            && xdgOutput.output() == &output
            && xdgOutput.manager() == &manager;
    });

    r.check("wayland/compositor-extension-template", [](QString &d) {
        // The CRTP base every non-shell extension uses. Reached through one of
        // them for the same reason QWaylandShellTemplate is reached through a
        // shell: the template is what an extension inherits, not something to
        // instantiate.
        QWaylandCompositor compositor;
        QWaylandViewporter viewporter(&compositor);
        d = QStringLiteral("QWaylandViewporter over QWaylandCompositorExtensionTemplate");
        return std::is_base_of<QWaylandCompositorExtensionTemplate<QWaylandViewporter>,
                               QWaylandViewporter>::value
            && std::is_base_of<QWaylandCompositorExtension, QWaylandViewporter>::value
            && viewporter.extensionContainer() == &compositor;
    });

    r.check("wayland/legacy-xdg-shells", [&r](QString &d) {
#if QT_VERSION_MAJOR < 6
        // The two unstable xdg-shell revisions Qt 5 implements (Qt 6 dropped them).
        // Their toplevel and popup types need a live wl_resource.
        QWaylandCompositor compositor;
        QWaylandXdgShellV5 shellV5(&compositor);
        QWaylandXdgShellV6 shellV6(&compositor);
        QWaylandXdgSurfaceV5 surfaceV5;
        QWaylandXdgSurfaceV6 surfaceV6;
        QWaylandXdgPopupV5 popupV5;
        QWaylandWlScaler scaler(&compositor);

        // QWaylandWlScaler has no interfaceName() of its own - it is the one
        // extension here that does not go through the CRTP template.
        d = QStringLiteral("v5=\"%1\", v6=\"%2\", plus wl_scaler")
                .arg(QString::fromLatin1(QWaylandXdgShellV5::interfaceName()))
                .arg(QString::fromLatin1(QWaylandXdgShellV6::interfaceName()));
        return shellV5.extensionContainer() == &compositor
            && shellV6.extensionContainer() == &compositor
            && scaler.extensionContainer() == &compositor
            && surfaceV5.surface() == nullptr && surfaceV6.surface() == nullptr
            && popupV5.surface() == nullptr
            && QWaylandXdgShellV5::interfaceName() != QWaylandXdgShellV6::interfaceName();
#else
        r.skip(d, QStringLiteral("the unstable xdg-shell revisions are Qt 5 only"));
        return false;
#endif
    });
#endif
}
