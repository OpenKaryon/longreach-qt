// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// qt-selftest - smoke test of the non-visual Qt subsystems.
//
// Prints PASS/FAIL per check and exits non-zero if anything failed, so it runs
// in a batch and is diff-able across target OSes (Windows XP / 11, Linux). No
// external assets and no window: images round-trip in memory, network runs over
// loopback, SQL uses an in-memory SQLite database. Qt 4 nevertheless needs a
// GUI-enabled QApplication for QPixmap/font handling, so its Linux run uses
// Xvfb; Qt 5 and Qt 6 remain genuinely display-less.
//
// Uses QGuiApplication (not QCoreApplication) because the image-format plugins
// and the GUI value types (QImage/QPainter/QFont) live in QtGui; no window is
// ever shown. The checks are grouped into checks_*.cpp translation units.

#include "../common/smokecheck.h"
#include "checks.h"

#if SMOKE_QT5
#include <QGuiApplication>
#else
#include <QApplication>
#endif
#include <QFile>
#include <QTextStream>
#include <cstring>
#ifdef SMOKE_ANDROID_EXTRAS_DIAGNOSTIC
#include "../android/android-extras-behavior.h"
#endif

#include "../common/crashinfo.h"
#include "../android/atomic-cow.h"
#if defined(LONGREACH_ANDROID_APK) && SMOKE_QT5 && QT_VERSION_MAJOR >= 5 && !defined(SMOKE_ANDROID_SELFTEST_CORE)
#include "../android/sound-cache-teardown.h"
#endif
#if defined(LONGREACH_ANDROID_APK) && SMOKE_QT5 && QT_VERSION_MAJOR == 5 && !defined(SMOKE_ANDROID_SELFTEST_CORE)
#include "../android/compass-heading.h"
#endif

#if !SMOKE_QT5 && defined(SMOKE_STATIC_QSQLITE)
#include <QtPlugin>
Q_IMPORT_PLUGIN(qsqlite)
#endif

// Old Bionic has a fixed DSO pool. Android may run these disjoint groups
// in separate APK builds; the default profile still executes every check.
namespace {
#if !defined(SMOKE_ANDROID_SELFTEST_EXTENDED)
void runCoreChecks(SmokeReporter &r)
{
    checkCore(r);
    checkTime(r);
    checkIo(r);
    checkSerialization(r);
    checkImages(r);
    checkGuiValue(r);
    checkItemModels(r);
    checkText(r);
    checkConcurrency(r);
    checkNetwork(r);
    checkMiscUtility(r);
    checkDomExtras(r);
    checkNetworkExtras(r);
    checkStateMachineTail(r);
    checkSql(r);
    checkScript(r);
    checkXmlPatterns(r);
    checkSvg(r);
    checkWebSockets(r);
    checkWebChannel(r);
    checkNetworkAuth(r);
    checkSerialPort(r);
    checkCanBus(r);
    checkModbus(r);
    checkScxml(r);
    checkRemoteObjects(r);
    checkShaderTools(r);
    checkScriptExtras(r);
    checkXmlPatternsExtras(r);
    checkTextDocumentStructure(r);
    checkValidatorsAndRegexMatch(r);
    checkOpcUaValueTypes(r);
    checkGrpc(r);
    checkWaylandCompositor(r);
    checkWaylandShells(r);
    checkWaylandLive(r);
    checkMqtt(r);
    checkCoap(r);
    checkHttpServer(r);
    checkQt6PropertySystem(r);
    checkQt6Network(r);
    checkCore5Compat(r);
    checkDBusValueTypes(r);
    checkPlatformOnlyExtras(r);
    checkRhi(r);
    checkQt6ProtocolTypes(r);
    checkQt6QtBaseAdditions(r);
    checkQt6QtBaseAdditions2(r);
}
#endif

#if !defined(SMOKE_ANDROID_SELFTEST_CORE)
void runExtendedChecks(SmokeReporter &r)
{
    checkLocation(r);
    checkAudioValueTypes(r);
    checkSoundEffects(r);
    checkMediaPlayerPlaylist(r);
    checkCameraValueTypes(r);
    checkRadio(r);
    checkVideoSurfaceAndFilter(r);
    checkSensors(r);
    checkBluetoothClassic(r);
    checkLowEnergy(r);
    checkNfc(r);
    checkGamepad(r);
    checkTextToSpeech(r);
    checkPurchasing(r);
    checkAnimationDriverAndNdef(r);
    checkQt6Multimedia(r);
    checkLocationServiceChain(r);
    checkDeclarativeCore(r);
    checkMultimediaValueTypes2(r);
    checkAbstractAudioBackendClasses(r);
    checkAudioSelectorRoleControls(r);
    checkCameraControlSuite(r);
    checkMediaPlaybackRecordingControls(r);
    checkRadioControlSuite(r);
    checkVideoControlSuite(r);
    checkMediaServiceProviderInterfaces(r);
}
#endif
} // namespace

int main(int argc, char *argv[])
{
    // A QtService needs its own QCoreApplication, before GUI initialization.
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--android-extras-service") == 0) {
#ifdef SMOKE_ANDROID_EXTRAS_DIAGNOSTIC
            return SmokeAndroidExtras::runService(argc, argv);
#else
            std::fprintf(stderr, "AndroidExtras service requires Qt5 Android core profile\n");
            return 2;
#endif
        }
    }
#if defined(LONGREACH_ANDROID_APK) && defined(__i386__) && SMOKE_QT5
    // Run before QGuiApplication: a bad emulator must fail without entering
    // the Android dispatcher that a false CAS can leave suspended forever.
    if (SmokeAndroidAtomicCow::requested(argc, argv))
        return SmokeAndroidAtomicCow::run();
#endif

#ifdef Q_OS_WIN
    // Before anything else, so it also covers the teardown after main()
    // returns - which is where the XP build dies with 0xC0000005.
    SmokeCrashInfo::install();
#endif

    // The live Wayland probe needs two QGuiApplications with different QPA
    // backends. Its server/client modes therefore have to branch before this
    // process creates the ordinary offscreen application.
    const int waylandChildResult = runWaylandChildMode(argc, argv);
    if (waylandChildResult >= 0)
        return waylandChildResult;

#if SMOKE_QT5
    QGuiApplication app(argc, argv); // no window is shown
#else
    // Qt 4 has no QGuiApplication.  Its pixmap/font/image-plugin code requires
    // a real QApplication (the false overload prints "Cannot create a QPixmap"
    // even when no window is shown), so Qt 4 Linux runs this under Xvfb just as
    // the other Qt 4 GUI smoke apps do.
    QApplication app(argc, argv);
#endif

    if (app.arguments().contains("--selftest-child")) {
        const int markerIndex = app.arguments().indexOf("--selftest-child") + 1;
        if (markerIndex < app.arguments().size()) {
            QFile marker(app.arguments().at(markerIndex));
            if (marker.open(QIODevice::WriteOnly | QIODevice::Truncate))
                marker.write("smoke\n");
        } else {
            QTextStream(stdout) << "smoke\n";
        }
        return 0;
    }

    if (app.arguments().contains(QStringLiteral("--compass-heading"))) {
        if (app.arguments().size() != 3 || app.arguments().at(1) != QStringLiteral("--compass-heading")) return 2;
#if defined(LONGREACH_ANDROID_APK) && SMOKE_QT5 && QT_VERSION_MAJOR == 5 && !defined(SMOKE_ANDROID_SELFTEST_CORE)
        return SmokeCompassHeading::run(app.arguments().at(2));
#else
        QTextStream(stdout) << "FAIL: compass-heading requires Qt5 Android extended/full profile\n";
        return 2;
#endif
    }

    if (app.arguments().contains(QStringLiteral("--sound-cache-teardown"))) {
        if (app.arguments().size() != 2) {
            QTextStream(stdout) << "FAIL: sound-cache-teardown requires exactly one diagnostic argument\n";
            return 2;
        }
#if defined(LONGREACH_ANDROID_APK) && SMOKE_QT5 && QT_VERSION_MAJOR >= 5 && !defined(SMOKE_ANDROID_SELFTEST_CORE)
        return SmokeSoundCacheTeardown::run();
#else
#if QT_VERSION_MAJOR >= 6
        QTextStream(stdout) << "FAIL: sound-cache-teardown requires Qt5/Qt6 Android extended or full profile\n";
#else
        QTextStream(stdout) << "FAIL: sound-cache-teardown requires Qt5 Android extended or full profile\n";
#endif
        return 2;
#endif
    }

    if (app.arguments().contains(QStringLiteral("--android-extras"))) {
        if (app.arguments().size() != 2) return 2;
#ifdef SMOKE_ANDROID_EXTRAS_DIAGNOSTIC
        return SmokeAndroidExtras::runClient();
#else
        QTextStream(stdout) << "FAIL: AndroidExtras requires Qt5 Android core profile\n";
        return 2;
#endif
    }

    SmokeReporter r("qt-selftest");

    const bool modernOnly = app.arguments().contains("--modern-cpp");
    if (modernOnly || !app.arguments().contains("--qt-checks-only"))
        checkModernCpp(r);
    if (modernOnly)
        return r.summary();
#if !defined(SMOKE_ANDROID_SELFTEST_EXTENDED)
    runCoreChecks(r);
#endif
#if !defined(SMOKE_ANDROID_SELFTEST_CORE)
    runExtendedChecks(r);
#endif

    return r.summary();
}
