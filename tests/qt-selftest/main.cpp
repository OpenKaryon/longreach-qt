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

#include "../common/crashinfo.h"

#if !SMOKE_QT5 && defined(SMOKE_STATIC_QSQLITE)
#include <QtPlugin>
Q_IMPORT_PLUGIN(qsqlite)
#endif

int main(int argc, char *argv[])
{
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

    SmokeReporter r("qt-selftest");

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
    checkLocation(r);
    checkScript(r);
    checkXmlPatterns(r);
    checkSvg(r);
    checkWebSockets(r);
    checkWebChannel(r);
    checkNetworkAuth(r);
    checkSerialPort(r);
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
    checkCanBus(r);
    checkModbus(r);
    checkScxml(r);
    checkRemoteObjects(r);
    checkShaderTools(r);
    checkScriptExtras(r);
    checkXmlPatternsExtras(r);
    checkGamepad(r);
    checkTextToSpeech(r);
    checkTextDocumentStructure(r);
    checkValidatorsAndRegexMatch(r);
    checkPurchasing(r);
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
    checkAnimationDriverAndNdef(r);
    checkPlatformOnlyExtras(r);
    checkRhi(r);
    checkQt6Multimedia(r);
    checkQt6ProtocolTypes(r);
    checkQt6QtBaseAdditions(r);
    checkQt6QtBaseAdditions2(r);
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

    return r.summary();
}
