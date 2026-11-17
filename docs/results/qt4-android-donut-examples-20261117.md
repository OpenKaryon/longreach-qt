# Shared Qt 4 example applications on Android 1.6

The Android APKs use Qt 4.8.7 and LLVM 21.1.8. Each test ran on an ARM
Android 1.6 guest that reported API 4 and `armeabi`. The Windows runner
boots each APK with separate userdata and retrieves its report with ADB.

The Android JNI adapter invokes the existing application entry points and
stores their existing PASS/FAIL/SKIP output in app-private storage. The
ordinary suite runs with `--qt-checks-only` and the shared C++23 checks
have their own APK.

## qt-selftest

**102 PASS, 0 FAIL, 122 SKIP.** The passing checks cover Core, timers,
file I/O, serialization, threading, TCP/UDP loopback, XML DOM, image and
font operations, QtScript and in-memory SQLite through QSQLITE.

Donut's Bionic lacks `fdatasync`, so the bundled SQLite code uses its
`fsync` fallback. The minimal QPA plugin reuses the Qt 4 FreeType font
database to read Android's system fonts from `/system/fonts`.

| Unavailable check | Reason |
| --- | --- |
| Starting a second copy of the suite with `QProcess` | Java starts the Qt test inside its Android Activity process |
| TLS loopback and SSL value classes | This Qt 4 profile is built without OpenSSL |
| QtScript debugger and XQuery | QtScriptTools and QtXmlPatterns are disabled |
| ICO, WebP and SVG image-plugin round trips | The respective image plugins are absent from this APK. QtSvg renderer and generator checks pass separately |
| GIF image write | Qt 4's GIF handler decodes images |
| Classes and modules added in Qt 5 or 6 | The shared test source reports these by name as SKIP |

The complete report, including all 122 SKIP reasons and passing checks,
is under `run/selftest/qt-selftest-guest.stdout` in the selected output
directory.

## Strict C++23

**25 PASS, 0 FAIL, 0 SKIP.** The existing suite ran in a separate APK
and reported `__cplusplus=202302`. The classic C locale check also passed.

## Additional examples

| APK | Application and result |
| --- | --- |
| `quick.apk` | The original switch, first frame and pause/resume checks passed. An Android launcher Activity also opens the shared 14-section Qt Quick gallery. Instrumentation rendered Controls and tapped through to Controls 2. |
| `quick.apk` | A separate Widgets Gallery launcher Activity renders Buttons, Inputs, Ranges and Item Views using the shared widget factories. Android taps changed the Qt checkbox state and selected the Inputs tab. |
| `graphics.apk` | Graphics Gallery `--selftest` passed 32 checks. Coverage includes raster rendering, SVG, animation, widgets, a shaped Qt window and contact sheet output. |
| `network.apk` | Network GUI `--selftest` passed 2 checks for TCP listening and UDP bind. The QtWebSockets and SSL checks reported SKIP. The separate Qt selftest exercised actual TCP/UDP loopback transfers. |
| `painting.apk` | Painting Lab `--selftest` passed 16 checks. Coverage includes alpha composition, SVG, PNG, text and fonts, print preview and page rendering. |

The gallery uses the existing QML and statically linked FolderListModel,
Gestures, Particles and SVG plugins. OpenGL effects require the shader
plugin and are unavailable on this raster profile. Android tap, drag and
navigation events use the same canvas bridge. Soft keyboard integration
remains unavailable in that bridge.

Graphics Gallery reuses the repository's static GUI interpolation fix.
The Donut build also keeps the weak-style-pointer lookup out of line
across synchronous Qt style changes to avoid the observed Clang-generated
null dereference. Graphics Gallery and Painting Lab save their render
artifacts in the Activity's private working directory.

The Android runner serves the role of the desktop `smoke-runner` for APKs.
The Android Widgets Gallery uses the same raster and touch bridge as the
Qt Quick Gallery. The full desktop widget selftest requires Qt3Support,
QtTest and Qt Multimedia. Multimedia Lab and GL Heavy Gallery are
omitted from the Android 1.6 examples.
