// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Declarations of the check groups that make up qt-selftest. Each group lives
// in its own .cpp and registers a batch of PASS/FAIL checks on the reporter.
#ifndef CHECKS_H
#define CHECKS_H

class SmokeReporter;

void checkCore(SmokeReporter &r);        // strings, containers, variant, meta, datastream
void checkTime(SmokeReporter &r);        // date/time/zone/locale/collator/easing
void checkIo(SmokeReporter &r);          // files, dirs, settings, mimetype, storage
void checkSerialization(SmokeReporter &r);// json, xml stream, dom, cbor
void checkImages(SmokeReporter &r);      // image format round-trips
void checkGuiValue(SmokeReporter &r);    // geometry, color, font, painter-on-image, transform
void checkItemModels(SmokeReporter &r);  // QStandardItemModel, proxies, selection
void checkConcurrency(SmokeReporter &r); // threads, pool, mutex, future, process
void checkNetwork(SmokeReporter &r);     // tcp/udp/qnam/interfaces/cookies/datagram
void checkSql(SmokeReporter &r);         // sqlite driver + models
void checkText(SmokeReporter &r);        // text document/cursor/layout/boundary
void checkLocation(SmokeReporter &r);    // QGeo*/QPlace* value types
void checkScript(SmokeReporter &r);      // QScriptEngine (deprecated but built)
void checkXmlPatterns(SmokeReporter &r); // XQuery/XPath evaluation
void checkSvg(SmokeReporter &r);         // QSvgRenderer/QSvgGenerator
void checkWebSockets(SmokeReporter &r);  // QWebSocket client/server loopback
void checkWebChannel(SmokeReporter &r);  // QWebChannel + custom transport
void checkNetworkAuth(SmokeReporter &r); // QOAuth1/QOAuth2 flow objects
void checkSerialPort(SmokeReporter &r);  // QSerialPort/QSerialPortInfo
void checkAudioValueTypes(SmokeReporter &r);      // QAudioFormat/DeviceInfo/Input/Output/Buffer
void checkSoundEffects(SmokeReporter &r);         // QSoundEffect/QSound
void checkMediaPlayerPlaylist(SmokeReporter &r);  // QMediaPlayer/Playlist/Content/Recorder
void checkCameraValueTypes(SmokeReporter &r);     // QCamera*/QCameraInfo
void checkRadio(SmokeReporter &r);                // QRadioTuner/QRadioData
void checkVideoSurfaceAndFilter(SmokeReporter &r);// custom QAbstractVideoSurface/Filter
void checkSensors(SmokeReporter &r);              // sensor/reading/filter catalogue
void checkBluetoothClassic(SmokeReporter &r);
void checkLowEnergy(SmokeReporter &r);
void checkNfc(SmokeReporter &r);
void checkCanBus(SmokeReporter &r);
void checkModbus(SmokeReporter &r);
void checkScxml(SmokeReporter &r);
void checkRemoteObjects(SmokeReporter &r);
void checkShaderTools(SmokeReporter &r);
void checkScriptExtras(SmokeReporter &r);
void checkXmlPatternsExtras(SmokeReporter &r);
void checkGamepad(SmokeReporter &r);
void checkTextToSpeech(SmokeReporter &r);
void checkTextDocumentStructure(SmokeReporter &r);
void checkValidatorsAndRegexMatch(SmokeReporter &r);
void checkMiscUtility(SmokeReporter &r);
void checkDomExtras(SmokeReporter &r);
void checkNetworkExtras(SmokeReporter &r);
void checkStateMachineTail(SmokeReporter &r);
void checkPurchasing(SmokeReporter &r);
void checkOpcUaValueTypes(SmokeReporter &r);
void checkGrpc(SmokeReporter &r);
void checkWaylandCompositor(SmokeReporter &r);
void checkWaylandShells(SmokeReporter &r);
void checkWaylandLive(SmokeReporter &r);
int runWaylandChildMode(int argc, char *argv[]);
void checkMqtt(SmokeReporter &r);
void checkCoap(SmokeReporter &r);
void checkHttpServer(SmokeReporter &r);
void checkQt6PropertySystem(SmokeReporter &r);
void checkQt6Network(SmokeReporter &r);
void checkCore5Compat(SmokeReporter &r);
void checkDBusValueTypes(SmokeReporter &r);
void checkAnimationDriverAndNdef(SmokeReporter &r);
void checkPlatformOnlyExtras(SmokeReporter &r);
void checkRhi(SmokeReporter &r);
void checkQt6Multimedia(SmokeReporter &r);
void checkQt6ProtocolTypes(SmokeReporter &r);
void checkQt6QtBaseAdditions(SmokeReporter &r);
void checkQt6QtBaseAdditions2(SmokeReporter &r);
void checkLocationServiceChain(SmokeReporter &r);
void checkDeclarativeCore(SmokeReporter &r);
void checkMultimediaValueTypes2(SmokeReporter &r);
void checkAbstractAudioBackendClasses(SmokeReporter &r);
void checkAudioSelectorRoleControls(SmokeReporter &r);
void checkCameraControlSuite(SmokeReporter &r);
void checkMediaPlaybackRecordingControls(SmokeReporter &r);
void checkRadioControlSuite(SmokeReporter &r);
void checkVideoControlSuite(SmokeReporter &r);
void checkMediaServiceProviderInterfaces(SmokeReporter &r);

#endif // CHECKS_H
