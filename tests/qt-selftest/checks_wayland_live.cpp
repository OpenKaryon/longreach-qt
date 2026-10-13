// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// A real, local Wayland round trip. The ordinary qt-selftest process remains
// offscreen; it starts this executable twice more, once as a compositor and
// once as a client using the wayland QPA plugin. This is intentionally more
// than a catalogue check: the client extension binds through wl_registry and
// real xdg-shell requests create compositor-side role objects.

#include "../common/smokecheck.h"
#include "checks.h"

#include <QCoreApplication>
#include <QFile>
#include <QLibrary>
#include <QProcess>
#include <QProcessEnvironment>
#include <QRect>
#include <QScopedPointer>
#include <QSize>
#include <QThread>
#include <QVector>

#if defined(SMOKE_HAVE_WAYLANDCOMPOSITOR) && defined(SMOKE_HAVE_WAYLANDCLIENT) && defined(Q_OS_LINUX)

#include <QTemporaryDir>
#include <QGuiApplication>
#include <QMouseEvent>
#include <QTimer>
#include <QWindow>
#include <QtWaylandClient/QWaylandClientExtension>
#include <QtWaylandCompositor/QWaylandClient>
#include <QtWaylandCompositor/QWaylandCompositor>
#include <QtWaylandCompositor/QWaylandPointer>
#include <QtWaylandCompositor/QWaylandSeat>
#include <QtWaylandCompositor/QWaylandView>
#include <QtWaylandCompositor/QWaylandXdgShell>

#if QT_VERSION_MAJOR < 6
#include <QtWaylandCompositor/QWaylandXdgShellV6>
#else
#include <QtWaylandCompositor/QWaylandQtTextInputMethodManager>
#include <QtWaylandCompositor/QWaylandTextInputManagerV3>
#endif

#include <wayland-client-protocol.h>

namespace {

static void appendMarker(const QString &path, const QByteArray &line)
{
    QFile marker(path);
    if (marker.open(QIODevice::WriteOnly | QIODevice::Append)) {
        marker.write(line);
        marker.write("\n");
        marker.flush();
    }
}

class SmokeRegistryExtension
    : public QWaylandClientExtensionTemplate<SmokeRegistryExtension>
{
public:
    SmokeRegistryExtension()
        : QWaylandClientExtensionTemplate<SmokeRegistryExtension>(1)
    {
    }

    ~SmokeRegistryExtension() override
    {
        if (m_compositor)
            wl_compositor_destroy(m_compositor);
    }

    static const wl_interface *interface() { return &wl_compositor_interface; }

    void init(wl_registry *registry, int id, int version)
    {
        m_compositor = static_cast<wl_compositor *>(
            wl_registry_bind(registry, uint32_t(id), &wl_compositor_interface,
                             uint32_t(version)));
    }

    bool bound() const { return m_compositor != nullptr; }

private:
    wl_compositor *m_compositor = nullptr;
};

class SmokeClientWindow : public QWindow
{
public:
    bool popupCreated() const { return !m_popup.isNull(); }

protected:
    void mousePressEvent(QMouseEvent *event) override
    {
        if (m_popup.isNull()) {
            m_popup.reset(new QWindow);
            m_popup->setTransientParent(this);
            m_popup->setFlags(Qt::Popup);
            m_popup->resize(24, 16);
            m_popup->show();
        }
        event->accept();
    }

private:
    QScopedPointer<QWindow> m_popup;
};

static void sendPointerClick(QWaylandCompositor *compositor,
                             QWaylandSurface *surface)
{
    QWaylandView *view = new QWaylandView(nullptr, compositor);
    view->setSurface(surface);
    QTimer::singleShot(100, compositor, [compositor, view]() {
        QWaylandPointer *pointer = compositor->defaultSeat()->pointer();
        pointer->sendMouseMoveEvent(view, QPointF(8, 8), QPointF(8, 8));
        pointer->sendMousePressEvent(Qt::LeftButton);
        pointer->sendMouseReleaseEvent(Qt::LeftButton);
    });
}

static int runServer(int argc, char *argv[], const QString &socket,
                     const QString &markerPath)
{
    QGuiApplication app(argc, argv);
    QWaylandCompositor compositor;
    compositor.setSocketName(socket.toUtf8());
    QWaylandXdgShell xdgShell(&compositor);

    QObject::connect(&xdgShell, &QWaylandXdgShell::toplevelCreated,
                     [&markerPath, &compositor](QWaylandXdgToplevel *toplevel,
                                                QWaylandXdgSurface *surface) {
        appendMarker(markerPath, "TOPLEVEL");
#if QT_VERSION_MAJOR < 6
        toplevel->sendConfigure(QSize(96, 64), QVector<QWaylandXdgToplevel::State>());
#else
        toplevel->sendConfigure(QSize(96, 64), QList<QWaylandXdgToplevel::State>());
#endif
        sendPointerClick(&compositor, surface->surface());
    });
    QObject::connect(&xdgShell, &QWaylandXdgShell::popupCreated,
                     [&markerPath](QWaylandXdgPopup *popup, QWaylandXdgSurface *) {
        appendMarker(markerPath, "POPUP");
        popup->sendConfigure(QRect(0, 0, 24, 16));
    });

#if QT_VERSION_MAJOR < 6
    QWaylandXdgShellV6 xdgShellV6(&compositor);
    QObject::connect(&xdgShellV6, &QWaylandXdgShellV6::toplevelCreated,
                     [&markerPath, &compositor](QWaylandXdgToplevelV6 *toplevel,
                                                QWaylandXdgSurfaceV6 *surface) {
        appendMarker(markerPath, "TOPLEVEL_V6");
        toplevel->sendConfigure(QSize(96, 64),
                                QVector<QWaylandXdgToplevelV6::State>());
        sendPointerClick(&compositor, surface->surface());
    });
    QObject::connect(&xdgShellV6, &QWaylandXdgShellV6::popupCreated,
                     [&markerPath](QWaylandXdgPopupV6 *popup, QWaylandXdgSurfaceV6 *) {
        appendMarker(markerPath, "POPUP_V6");
        popup->sendConfigure(QRect(0, 0, 24, 16));
    });
#else
    // These are real globals on the private compositor, not sizeof mentions.
    QWaylandQtTextInputMethodManager qtTextInput(&compositor);
    QWaylandTextInputManagerV3 textInputV3(&compositor);
#endif

    compositor.create();
    if (!compositor.isCreated())
        return 2;
    appendMarker(markerPath, "READY");

    QTimer pollClients;
    QObject::connect(&pollClients, &QTimer::timeout, [&]() {
        if (!compositor.clients().isEmpty())
            appendMarker(markerPath, "CLIENT");
    });
    pollClients.start(20);
    QTimer::singleShot(15000, &app, &QCoreApplication::quit);
    return app.exec();
}

static int runClient(int argc, char *argv[], const QString &markerPath)
{
    QGuiApplication app(argc, argv);
    SmokeRegistryExtension extension;

    SmokeClientWindow topLevel;
    topLevel.resize(96, 64);
    topLevel.setTitle(QStringLiteral("longreach-qt-wayland-live"));
    topLevel.show();

    QTimer deadline;
    deadline.setSingleShot(true);
    QObject::connect(&deadline, &QTimer::timeout, &app, &QCoreApplication::quit);
    deadline.start(3000);

    QTimer poll;
    bool extensionRecorded = false;
    QObject::connect(&poll, &QTimer::timeout, [&]() {
        if (!extensionRecorded && extension.isActive() && extension.bound()) {
            appendMarker(markerPath, "EXTENSION");
            extensionRecorded = true;
        }
    });
    poll.start(10);
    const int result = app.exec();
    return result == 0 && extension.isActive() && extension.bound()
           && topLevel.popupCreated() ? 0 : 3;
}

static bool waitForMarker(const QString &path, const QByteArray &needle, int timeoutMs)
{
    const int steps = qMax(1, timeoutMs / 20);
    for (int i = 0; i < steps; ++i) {
        QFile marker(path);
        if (marker.open(QIODevice::ReadOnly) && marker.readAll().contains(needle))
            return true;
        QThread::msleep(20);
    }
    return false;
}

static QByteArray markerContents(const QString &path)
{
    QFile marker(path);
    return marker.open(QIODevice::ReadOnly) ? marker.readAll() : QByteArray();
}

static bool runOneClient(const QProcessEnvironment &baseEnvironment,
                         const QString &socket, const QString &markerPath,
                         const QString &shell, QString &detail)
{
    QProcess client;
    QProcessEnvironment environment = baseEnvironment;
    environment.insert(QStringLiteral("QT_QPA_PLATFORM"), QStringLiteral("wayland"));
    environment.insert(QStringLiteral("WAYLAND_DISPLAY"), socket);
    environment.insert(QStringLiteral("QT_WAYLAND_DISABLE_WINDOWDECORATION"),
                       QStringLiteral("1"));
    environment.insert(QStringLiteral("QT_WAYLAND_SHELL_INTEGRATION"), shell);
    client.setProcessEnvironment(environment);
    client.start(QCoreApplication::applicationFilePath(),
                 QStringList() << QStringLiteral("--wayland-live-client") << markerPath);
    if (!client.waitForStarted(3000) || !client.waitForFinished(5000)) {
        detail = QStringLiteral("client %1 did not finish: %2")
                     .arg(shell, client.errorString());
        return false;
    }
    if (client.exitStatus() != QProcess::NormalExit || client.exitCode() != 0) {
        detail = QStringLiteral("client %1 exit=%2 stderr=%3")
                     .arg(shell).arg(client.exitCode())
                     .arg(QString::fromLocal8Bit(client.readAllStandardError()));
        return false;
    }
    return true;
}

} // namespace

int runWaylandChildMode(int argc, char *argv[])
{
    // There is no QCoreApplication yet, so inspect argv directly.
    for (int i = 1; i < argc; ++i) {
        const QByteArray option(argv[i]);
        if (option == "--wayland-live-server" && i + 2 < argc)
            return runServer(argc, argv, QString::fromLocal8Bit(argv[i + 1]),
                             QString::fromLocal8Bit(argv[i + 2]));
        if (option == "--wayland-live-client" && i + 1 < argc)
            return runClient(argc, argv, QString::fromLocal8Bit(argv[i + 1]));
    }
    return -1;
}

void checkWaylandLive(SmokeReporter &r)
{
    r.check("wayland/live-client-and-shells", [&r](QString &d) {
        // Builds that load libwayland at run time (the Lucid ones) run on
        // systems without it; there is then no Wayland to connect to.
        QLibrary waylandClient(QStringLiteral("wayland-client"), 0);
        QLibrary waylandServer(QStringLiteral("wayland-server"), 0);
        if (!waylandClient.load() || !waylandServer.load()) {
            r.skip(d, QStringLiteral("libwayland-client and libwayland-server are not installed"));
            return false;
        }
        // Qt's Wayland client needs libwayland 1.11 (wl_proxy_create_wrapper);
        // the stubs find older ones but not what is missing from them.
        if (!waylandClient.resolve("wl_proxy_create_wrapper")) {
            r.skip(d, QStringLiteral("libwayland-client is older than 1.11"));
            return false;
        }
        QTemporaryDir runtime;
        if (!runtime.isValid()) {
            d = QStringLiteral("could not create XDG_RUNTIME_DIR");
            return false;
        }
        QFile::setPermissions(runtime.path(), QFileDevice::ReadOwner
                             | QFileDevice::WriteOwner | QFileDevice::ExeOwner);

        const QString socket = QStringLiteral("smoke-wayland-%1")
                                   .arg(QCoreApplication::applicationPid());
        const QString serverMarker = runtime.filePath(QStringLiteral("server.txt"));
        const QString stableMarker = runtime.filePath(QStringLiteral("stable.txt"));
        const QString v6Marker = runtime.filePath(QStringLiteral("v6.txt"));

        QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
        environment.insert(QStringLiteral("XDG_RUNTIME_DIR"), runtime.path());

        QProcess server;
        QProcessEnvironment serverEnvironment = environment;
        serverEnvironment.insert(QStringLiteral("QT_QPA_PLATFORM"),
                                 QStringLiteral("offscreen"));
        server.setProcessEnvironment(serverEnvironment);
        server.start(QCoreApplication::applicationFilePath(),
                     QStringList() << QStringLiteral("--wayland-live-server")
                                   << socket << serverMarker);
        if (!server.waitForStarted(3000) || !waitForMarker(serverMarker, "READY", 4000)) {
            d = QStringLiteral("compositor failed to become ready: %1 %2")
                    .arg(server.errorString(),
                         QString::fromLocal8Bit(server.readAllStandardError()));
            return false;
        }

        bool ok = runOneClient(environment, socket, stableMarker,
                               QStringLiteral("xdg-shell"), d);
        const QString clientFailure = ok ? QString() : d;
#if QT_VERSION_MAJOR < 6
        if (ok)
            ok = runOneClient(environment, socket, v6Marker,
                              QStringLiteral("xdg-shell-v6"), d);
#endif
        QThread::msleep(150);
        server.terminate();
        if (!server.waitForFinished(1500)) {
            server.kill();
            server.waitForFinished(1000);
        }

        const QByteArray observed = markerContents(serverMarker);
        const QByteArray stable = markerContents(stableMarker);
        ok = ok && observed.contains("CLIENT") && observed.contains("TOPLEVEL")
             && observed.contains("POPUP") && stable.contains("EXTENSION");
#if QT_VERSION_MAJOR < 6
        const QByteArray v6 = markerContents(v6Marker);
        ok = ok && observed.contains("TOPLEVEL_V6") && observed.contains("POPUP_V6")
             && v6.contains("EXTENSION");
#endif
        d = QStringLiteral("server=%1 stable=%2%3")
                .arg(QString::fromLatin1(observed.trimmed()).replace('\n', ','),
                     QString::fromLatin1(stable.trimmed()).replace('\n', ','),
                     clientFailure.isEmpty()
                         ? QString()
                         : QStringLiteral(" client-error=") + clientFailure);
        return ok;
    });
}

#else

int runWaylandChildMode(int, char *[])
{
    return -1;
}

void checkWaylandLive(SmokeReporter &r)
{
    r.check("wayland/live-client-and-shells", [&r](QString &d) {
        r.skip(d, QStringLiteral("requires WaylandClient and WaylandCompositor on Linux"));
        return false;
    });
}

#endif
