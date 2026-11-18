// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// quick-qml - visual Qt Quick / Controls 2 / Shapes showcase + headless self-test.
//
//   quick-qml-gallery              show the gallery window (Controls, Shapes,
//                                 animations, a model-backed ListView)
//   quick-qml-gallery --selftest   run headless QQmlEngine/QJSEngine checks,
//                                 print PASS/FAIL, exit non-zero on failure
//                                 (no window shown)
//   quick-qml-gallery --gallery-selftest  verify the real Qt 5/6 QML window
#include "../common/smokecheck.h"
#include "../common/crashinfo.h"

#include <QApplication>
#include <QUrl>
#if defined(QT_WIN95_SUPPORT)
#include <cstdio>
#endif

#if QT_VERSION_MAJOR >= 6
#include <QQuickStyle>
#include <cstring>
#endif

#if SMOKE_QT5
#include <QElapsedTimer>
#include <QImage>
#include <QQuickWindow>
#include <QTimer>
#include <QOperatingSystemVersion>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#else
// Qt 4's QtDeclarative is QtQuick 1: a QGraphicsView scene driven by
// QDeclarative* classes. The engine, the view and the QML dialect all differ,
// so the Qt 4 window is built separately rather than guarded line by line, and
// it loads its own QML 1 file from qml_qt4/.
#include <QDeclarativeView>
#include <QDeclarativeEngine>
#include <QDeclarativeExtensionPlugin>
#include <QGLWidget>
#include <QtPlugin>
#include "qt4_static_imports.h"

Q_IMPORT_PLUGIN(qsvg)

#endif

int runSelfTest();
#if QT_VERSION_MAJOR >= 6
bool configureNativeTextureProbe(const QByteArray &backend);
int runNativeTextureProbe(const QByteArray &backend);
int runQuick3DExtensionProbe();
#endif

#if SMOKE_QT5
static int runGallerySelftest(QApplication &app, QQmlApplicationEngine &engine)
{
    SmokeReporter reporter("quick-qml-gallery-render");
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    if (!window) {
        reporter.check("qml/gallery-window", [](QString &detail) {
            detail = QStringLiteral("QML root is not a window");
            return false;
        });
        return reporter.summary();
    }

    int frames = 0;
    QElapsedTimer elapsed;
    elapsed.start();
    QTimer timer;
    QObject::connect(window, &QQuickWindow::frameSwapped, &timer, [&] { ++frames; });
    QObject::connect(&timer, &QTimer::timeout, &timer, [&] {
        if (frames == 0 && elapsed.elapsed() < 20000)
            return;
        timer.stop();
        reporter.check("qml/gallery-first-frame", [&](QString &detail) {
            detail = QStringLiteral("frames=%1 visible=%2 size=%3x%4")
                    .arg(frames).arg(window->isVisible()).arg(window->width()).arg(window->height());
            return frames > 0 && window->isVisible() && window->width() > 0 && window->height() > 0;
        });
        const QImage image = frames > 0 ? window->grabWindow() : QImage();
        reporter.check("qml/gallery-pixels", [&](QString &detail) {
            if (image.isNull()) {
                detail = QStringLiteral("window capture is empty");
                return false;
            }
            const QRgb first = image.pixel(0, 0);
            for (int y = 0; y < image.height(); y += qMax(1, image.height() / 16))
                for (int x = 0; x < image.width(); x += qMax(1, image.width() / 16))
                    if (image.pixel(x, y) != first)
                        return true;
            detail = QStringLiteral("window capture is a uniform fill");
            return false;
        });
        reporter.check("qml/gallery-artifact", [&](QString &) {
            return !image.isNull()
                && image.save(smokeArtifactDirectory().filePath(QStringLiteral("quick-gallery.png")));
        });
        app.exit(reporter.summary());
    });
    timer.start(100);
    window->update();
    return app.exec();
}

static bool isWindowsXpFamily()
{
#ifdef Q_OS_WIN
    const QOperatingSystemVersion current = QOperatingSystemVersion::current();
    return current.type() == QOperatingSystemVersion::Windows && current.majorVersion() <= 5;
#else
    return false;
#endif
}

static bool hasUnreliableNativeQmlPopups()
{
#ifdef Q_OS_MACOS
    // In this static/osxcross build, separate native QML popup windows on
    // macOS can show as solid gray surfaces while staying clickable. Keep the
    // API checks in --selftest, but do not present unreadable manual examples.
    return true;
#else
    return isWindowsXpFamily();
#endif
}
#endif  // SMOKE_QT5

int main(int argc, char *argv[])
{
#if defined(QT_WIN95_SUPPORT)
    std::fputs("QML startup: entered main\n", stdout);
    std::fflush(stdout);
#endif
#ifdef Q_OS_WIN
    SmokeCrashInfo::install();
#endif
#if QT_VERSION_MAJOR >= 6
    // Qt 5's Default Controls 2 style was renamed Basic in Qt 6. Qt 6
    // otherwise selects the native Windows style, which changes every control
    // in this visual comparison. Preserve explicit user style overrides.
    bool explicitQuickStyle = qEnvironmentVariableIsSet("QT_QUICK_CONTROLS_STYLE");
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "-style") == 0
                || std::strncmp(argv[i], "-style=", 7) == 0)
            explicitQuickStyle = true;
    }
    QByteArray nativeTextureBackend;
    for (int i = 1; i + 1 < argc; ++i) {
        if (QByteArray(argv[i]) == "--native-texture-probe") {
            nativeTextureBackend = argv[i + 1];
            if (!configureNativeTextureProbe(nativeTextureBackend))
                return 77;
            break;
        }
    }
#endif

    // QApplication (not QGuiApplication): the selftest constructs a
    // QQuickWidget, which is a real QWidget and needs one. Qt 4 has no
    // QGuiApplication at all, so this is also the only spelling that works
    // across all three versions.
    QApplication app(argc, argv);
#if defined(QT_WIN95_SUPPORT)
    std::fputs("QML startup: QApplication created\n", stdout);
    std::fflush(stdout);
#endif

#if !SMOKE_QT5
    // Qt 4's QML loader only resolves a qmldir plugin entry to a physical DLL;
    // unlike later Qt it does not consult the static plugin registry there.
    // Register the four linked-in labs modules directly before any engine is
    // created, keeping the deployed gallery a single executable.
    registerQt4QmlPlugins();
#if defined(QT_WIN95_SUPPORT)
    std::fputs("QML startup: static plugins registered\n", stdout);
    std::fflush(stdout);
#endif
#endif

#if QT_VERSION_MAJOR >= 6
    if (app.arguments().contains(QStringLiteral("--quick3d-extension-probe")))
        return runQuick3DExtensionProbe();
    if (!nativeTextureBackend.isEmpty())
        return runNativeTextureProbe(nativeTextureBackend);
#endif

    if (app.arguments().contains("--selftest"))
        return runSelfTest();

#if SMOKE_QT5
#if QT_VERSION_MAJOR >= 6
    if (!explicitQuickStyle)
        QQuickStyle::setStyle(QStringLiteral("Basic"));
#endif
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("appLegacyWindowsXp"), isWindowsXpFamily());
    engine.rootContext()->setContextProperty(QStringLiteral("appUnreliableNativeQmlPopups"),
                                             hasUnreliableNativeQmlPopups());
    engine.load(QUrl(QStringLiteral("qrc:/qml/main.qml")));
    if (engine.rootObjects().isEmpty())
        return 1;
    if (app.arguments().contains(QStringLiteral("--gallery-selftest")))
        return runGallerySelftest(app, engine);
#else
    // QDeclarativeView is a QGraphicsView that owns the engine, so there is no
    // separate root-object check: a QML error leaves the view without a root
    // and status() says so.
    QDeclarativeView view;
    configureQt4QmlView(view);
    view.setSource(QUrl(QLatin1String("qrc:/qml_qt4/qml_qt4/main.qml")));
    if (view.status() == QDeclarativeView::Error)
        return 1;
    view.setWindowTitle(QLatin1String("Qt Quick 1 gallery - " QT_VERSION_STR));
    view.setMinimumSize(720, 540);
    view.resize(960, 680);
    view.show();
#endif
    return app.exec();
}
