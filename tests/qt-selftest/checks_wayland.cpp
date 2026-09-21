// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// QtWaylandCompositor - the module this kit skipped for years.
//
// The reason recorded in the Dockerfiles was that the base images had no
// wayland development libraries. That was true of the images, not of the
// distributions: Debian 12 carries libwayland 1.21 and Ubuntu 16.04 carries
// 1.12, while qtwayland asks for 1.8 or newer. Four packages turned 114
// classes - 58 in Qt 5, 56 in Qt 6 - from a permanent gap into ordinary
// coverage.
//
// What makes them checkable without a running Wayland session is the shape of
// the module. QtWaylandCompositor is a library for *writing* a compositor, not
// for talking to one: you assemble a QWaylandCompositor, hang outputs, seats
// and shell extensions off it, and only then call create(), which is what opens
// the socket and publishes the globals. Every check here stops short of that
// call. Nothing binds a socket, nothing talks to a display server, and the
// checks pass the same on a build machine as on a desktop.
//
// The client half of qtwayland is deliberately not here. QWaylandClientExtension
// and its template bind against a wl_registry, which only exists once you are
// connected to a compositor - there is no equivalent seam to stop at.
#include "../common/smokecheck.h"

#ifdef SMOKE_HAVE_WAYLANDCOMPOSITOR
#include <QWaylandBufferRef>
#include <QWaylandCompositor>
#include <QWaylandDestroyListener>
#include <QWaylandIdleInhibitManagerV1>
#include <QWaylandIviApplication>
#include <QWaylandKeyboard>
#include <QWaylandKeymap>
#include <QWaylandOutput>
#include <QWaylandOutputMode>
#include <QWaylandPointer>
#include <QWaylandQtWindowManager>
#include <QWaylandResource>
#include <QWaylandSeat>
#include <QWaylandSurface>
#include <QWaylandTextInputManager>
#include <QWaylandTouch>
#include <QWaylandView>
#include <QWaylandViewporter>
#include <QWaylandWlShell>
#include <QWaylandXdgDecorationManagerV1>
#include <QWaylandXdgOutputManagerV1>
#include <QWaylandXdgShell>

#include <QByteArray>
#include <QPoint>
#include <QRect>
#include <QSize>
#include <QString>
#endif

void checkWaylandCompositor(SmokeReporter &r)
{
#ifndef SMOKE_HAVE_WAYLANDCOMPOSITOR
    r.check("wayland/module-available", [&](QString &d) {
        r.skip(d, QStringLiteral("QtWaylandCompositor is Linux-only and not in this SDK"));
        return false;
    });
#else
    r.check("wayland/compositor-before-create", [](QString &d) {
        // The seam the whole file rests on: a compositor is inert until
        // create() is called. Setting the socket name records a name, it does
        // not bind one - so this runs on a machine with no Wayland session and
        // leaves nothing behind.
        QWaylandCompositor compositor;
        compositor.setSocketName(QByteArrayLiteral("qt-smoke-0"));
        compositor.setRetainedSelectionEnabled(true);
        d = QStringLiteral("socket \"%1\", created=%2, default output=%3")
                .arg(QString::fromLatin1(compositor.socketName()))
                .arg(int(compositor.isCreated()))
                .arg(compositor.defaultOutput() ? QLatin1String("set") : QLatin1String("none"));
        return !compositor.isCreated()
            && compositor.socketName() == QByteArrayLiteral("qt-smoke-0")
            && compositor.retainedSelectionEnabled()
            && compositor.defaultOutput() == nullptr;
    });

    r.check("wayland/output-and-mode", [](QString &d) {
        // An output is a screen the compositor publishes. Its geometry comes
        // from the mode, and a mode is a plain value type - size plus refresh
        // rate in mHz, which is how the protocol spells it.
        QWaylandOutputMode mode(QSize(1920, 1080), 60000);
        const QWaylandOutputMode copy = mode;

        QWaylandCompositor compositor;
        QWaylandOutput output;
        output.setCompositor(&compositor);
        output.setManufacturer(QStringLiteral("qt-smoke"));
        output.setModel(QStringLiteral("virtual"));
        output.setPosition(QPoint(100, 50));
        output.setPhysicalSize(QSize(520, 320));
        output.setTransform(QWaylandOutput::Transform90);
        output.setSubpixel(QWaylandOutput::SubpixelHorizontalRgb);

        d = QStringLiteral("%1x%2 @ %3 mHz, output at %4,%5 on %6")
                .arg(copy.size().width()).arg(copy.size().height()).arg(copy.refreshRate())
                .arg(output.position().x()).arg(output.position().y())
                .arg(output.manufacturer());
        return copy.size() == QSize(1920, 1080) && copy.refreshRate() == 60000
            && copy.isValid() && mode == copy
            && output.compositor() == &compositor
            && output.position() == QPoint(100, 50)
            && output.physicalSize() == QSize(520, 320)
            && output.transform() == QWaylandOutput::Transform90
            && output.subpixel() == QWaylandOutput::SubpixelHorizontalRgb;
    });

    r.check("wayland/seat-and-input-devices", [](QString &d) {
        // A seat's devices are created by initialize(), not the constructor, so
        // keyboard(), pointer() and touch() are null until then; the capability
        // bookkeeping is the constructor's.
        QWaylandCompositor compositor;
        QWaylandSeat seat(&compositor, QWaylandSeat::DefaultCapabilities);
        QWaylandSeat pointerOnly(&compositor, QWaylandSeat::Pointer);

        d = QStringLiteral("caps default=%1 pointer-only=%2, devices before initialize: %3")
                .arg(int(seat.capabilities())).arg(int(pointerOnly.capabilities()))
                .arg(seat.keyboard() || seat.pointer() || seat.touch()
                         ? QLatin1String("some") : QLatin1String("none"));
        return seat.compositor() == &compositor
            && !seat.isInitialized()
            && seat.keyboard() == nullptr && seat.pointer() == nullptr
            && seat.touch() == nullptr
            && seat.capabilities().testFlag(QWaylandSeat::Keyboard)
            && seat.capabilities().testFlag(QWaylandSeat::Pointer)
            && seat.capabilities().testFlag(QWaylandSeat::Touch)
            && pointerOnly.capabilities().testFlag(QWaylandSeat::Pointer)
            && !pointerOnly.capabilities().testFlag(QWaylandSeat::Touch);
    });

    r.check("wayland/keymap", [](QString &d) {
        // What layout the compositor tells clients to use. Pure description -
        // no xkb context is built until a keyboard actually needs one.
        QWaylandKeymap keymap(QStringLiteral("us"), QStringLiteral("dvorak"),
                              QStringLiteral("terminate:ctrl_alt_bksp"),
                              QStringLiteral("pc105"), QStringLiteral("evdev"));
        d = QStringLiteral("%1/%2 on %3 (%4)")
                .arg(keymap.layout()).arg(keymap.variant())
                .arg(keymap.model()).arg(keymap.rules());
        return keymap.layout() == QStringLiteral("us")
            && keymap.variant() == QStringLiteral("dvorak")
            && keymap.model() == QStringLiteral("pc105")
            && keymap.rules() == QStringLiteral("evdev")
            && keymap.options().contains(QStringLiteral("terminate"));
    });

    r.check("wayland/shell-extensions", [](QString &d) {
        // The three shell protocols a Qt compositor can speak, plus the
        // ancillary extensions. All of them are compositor extensions: they
        // attach to a compositor and publish a global when it is created, so
        // before create() they are inert objects with a name.
        QWaylandCompositor compositor;
        QWaylandWlShell wlShell(&compositor);
        QWaylandXdgShell xdgShell(&compositor);
        QWaylandIviApplication ivi(&compositor);
        QWaylandViewporter viewporter(&compositor);
        QWaylandQtWindowManager windowManager(&compositor);
        QWaylandIdleInhibitManagerV1 idleInhibit(&compositor);
        QWaylandTextInputManager textInput(&compositor);
        QWaylandXdgOutputManagerV1 xdgOutput(&compositor);
        QWaylandXdgDecorationManagerV1 decoration;

        const QByteArray wlShellName = QWaylandWlShell::interfaceName();
        const QByteArray xdgShellName = QWaylandXdgShell::interfaceName();
        d = QStringLiteral("wl_shell=\"%1\", xdg_shell=\"%2\", ivi=\"%3\"")
                .arg(QString::fromLatin1(wlShellName))
                .arg(QString::fromLatin1(xdgShellName))
                .arg(QString::fromLatin1(QWaylandIviApplication::interfaceName()));
        return wlShell.extensionContainer() == &compositor
            && xdgShell.extensionContainer() == &compositor
            && ivi.extensionContainer() == &compositor
            && viewporter.extensionContainer() == &compositor
            && windowManager.extensionContainer() == &compositor
            && idleInhibit.extensionContainer() == &compositor
            && textInput.extensionContainer() == &compositor
            && xdgOutput.extensionContainer() == &compositor
            && decoration.extensionContainer() == nullptr
            && !wlShellName.isEmpty() && !xdgShellName.isEmpty()
            && wlShellName != xdgShellName;
    });

    r.check("wayland/surface-view-and-buffer", [](QString &d) {
        // With no client the surface has no buffer and the reference is null, as
        // every compositor sees before the first commit.
        QWaylandSurface surface;
        QWaylandBufferRef bufferRef;
        // Not const: QWaylandBufferRef::operator== is declared without a const
        // qualifier, so a const copy could not be compared at all.
        QWaylandBufferRef copy = bufferRef;

        d = QStringLiteral("surface has buffer=%1, cursor=%2, ref null=%3")
                .arg(int(surface.hasContent())).arg(int(surface.isCursorSurface()))
                .arg(int(!copy.hasBuffer()));
        return !surface.hasContent() && !surface.isCursorSurface()
            && !copy.hasBuffer() && copy == bufferRef
            && surface.compositor() == nullptr;
    });

    r.check("wayland/view-attach", [](QString &d) {
        // Attaching a view reaches into the surface's private state, so it is a check
        // of its own.
        QWaylandSurface surface;
        QWaylandView view;
        view.setSurface(&surface);
        d = QStringLiteral("view attached to a surface with no compositor");
        return view.surface() == &surface && view.output() == nullptr;
    });

    r.check("wayland/resource-and-destroy-listener", [](QString &d) {
        // Two small helpers the compositor API hands around: a wrapper for a
        // raw wl_resource, and the hook that fires when one goes away. A
        // default QWaylandResource wraps nothing, which is the only state
        // reachable without a client.
        QWaylandResource resource;
        QWaylandDestroyListener listener;
        d = QStringLiteral("resource wraps %1, listener parent %2")
                .arg(resource.resource() ? QLatin1String("something") : QLatin1String("nothing"))
                .arg(listener.parent() ? QLatin1String("set") : QLatin1String("none"));
        return resource.resource() == nullptr && listener.parent() == nullptr
            && listener.metaObject()->inherits(&QObject::staticMetaObject);
    });
#endif
}
