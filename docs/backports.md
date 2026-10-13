# Backports

Qt drops old systems by calling newer APIs unconditionally. The patches in
`patches/qt<N>/<os>/` put each such call behind a check, so the code still
compiles for the floor and still takes the newer path where it exists:

- **at run time**, when the API may or may not be there: the symbol is
  resolved with `GetProcAddress`/`dlsym`, weak-linked and checked
  (`@available` on macOS), or chosen by the OS version (`GetVersionEx`,
  `Gestalt`);
- **at compile time**, from the deployment target, when an API cannot even be
  declared for the floor (macOS `MAC_OS_X_VERSION_MIN_REQUIRED`, Windows
  `_WIN32_WINNT`).

One binary therefore runs on the floor and on the newest system, and on the
newest system it behaves as unpatched Qt does. Where a feature cannot exist on
an old system it degrades: the API reports it unavailable, and the test suite
reports a SKIP rather than a failure.

## Layout

```
patches/qt4/{all,linux,macos,windows}/
patches/qt5/{all,linux,macos,windows}/
patches/qt6/{all,macos,windows}/
```

A build applies `qt<N>/all` and then its OS series, every patch in order;
nothing depends on the deployment target or the architecture. Each patch
starts with an SPDX line and a comment header saying what it changes, why,
and how it was checked. Qt 5 patches apply with `git apply`, Qt 4 and Qt 6
ones with `patch -p1`, from the root of the unpacked source archive. All
series are checked against pristine Qt 4.8.7, 5.15.19 and 6.8.4.

## Qt 4.8.7

- `all/` (6): OpenSSL 1.1/3 API port, guarded on the version so 1.0.2 builds
  as upstream did; TLS 1.2/1.3 cipher selection by name; three upstream
  crashes (accessibility on item views, static animation registration,
  JavaScriptCore frame tagging under clang).
- `windows/` (27): the mkspec (static runtime, size flags, `QT_WIN95_SUPPORT`)
  and the Windows 95/98/ME restoration. Qt removed the Win9x code in 4.6; these
  patches bring back runtime ANSI/Unicode selection in QtCore, the file system,
  events, settings, locale, processes, GUI, SQLite, the file system watcher,
  printing, the system tray and accessibility, so the same EXE uses the ANSI
  API on Win9x and the Unicode API on NT. Each patch's header says what it
  changes and, for the restored code, which Qt commit it comes from
  ([`5ae330b6`](https://github.com/qt/qt/commit/5ae330b6546dabada53c394b53ce9513f552a8a5),
  [`55137901`](https://github.com/qt/qt/commit/55137901012db28857fe7638e63c78743e277c56)).
- `linux/` (3): size flags and a static C++ runtime in the mkspec; Linux
  without futex syscalls (Sarge's 2.4/2.6 kernels); no repeated
  `glXMakeCurrent` of the current context, which loses a large window's
  frame on Debian 4.0's X server.
- `macos/` (17): Carbon cross-build from Linux, Tiger API substitutions
  (LaunchServices, print paper, font and file dialogs), the PowerPC timebase,
  and the Jaguar layer: a 10.2 floor, run-time checks for every 10.3/10.4 API
  in QtCore and QtGui, libSystem functions 10.2 lacks.

## Qt 5.15.19

- `all/` (8): upstream crashes found by the suite (OpenGL timer queries,
  QtScript frames, gamepad, D-Bus server, DataVisualization on Mesa) and a
  mapbox build fix.
- `windows/` (17): MinGW build fixes for every Windows target (01-04) and the
  Windows XP backport (05-17, prefixed `xp-`): the XP API level, then each
  Vista/7 API Qt uses resolved at run time - QtCore, networking, fonts,
  widgets, the platform plugin (file dialogs, touch, tray, DPI), the Vista
  style, multimedia, WinExtras, SCXML, Quick Controls, QProcess pipes,
  QCollator. Windows on ARM applies them too; there they always find the
  newer API.
- `linux/` (5): no Xinerama in the xcb plugin; run-time fallbacks for Lucid's
  libxcb 1.5 and libX11 1.3 (`xcb_poll_for_queued_event`, a missing
  libX11-xcb), and thread naming without glibc 2.12; GStreamer services only
  where GStreamer initializes (it is loaded at run time); QtBluetooth without
  a D-Bus system bus.
- `macos/` (47): from 10.12 down to 10.6 in steps - os_activity, unified
  logging, Metal, file system fast paths (pre-10.12); OS version queries,
  CoreGraphics, CoreText weights, the Metal RHI (pre-10.11); App Nap,
  gamepad, Bluetooth, multimedia, speech, WebView, implicit dylibs (pre-10.9
  and 10.8, the 10.7 port); then QtCore, networking, trust settings,
  CoreText, Cocoa coordinates, full screen, restoration, input, OpenGL, the
  style, QtTest, multimedia, purchasing, Bluetooth, positioning, Qt3D and
  DataVisualization below 10.7 (the 10.6 port); 43-47 move Objective-C
  instance variables into `@interface` for the 32-bit (fragile) runtime of
  the i386 build.

## Qt 6.8.4

- `all/` (4): OpenSSL symbol clash between QtOpcUa and QtNetwork in static
  builds; the D-Bus tray menu without a session bus; fonts without fontconfig;
  legacy libGL on Linux.
- `windows/` (15): the Windows 7 backport, from the diffs of
  [crystalidea/qt6windows7](https://github.com/crystalidea/qt6windows7) at
  `3df3aac7` (QtCore, QtGui, the platform plugin, networking, widgets,
  multimedia, Schannel), the Windows 7 API level with its header fixes,
  MSVCRT (`_fstat64` in Assimp), and no Windows 8 import libraries
  (`synchronization`, `shcore`) in the CMake link interface.
- `macos/` (19): macOS 12 down to 10.13 (11.0 on arm64): OpenXR's POSIX file
  system and camera APIs before 10.15; aligned allocation, file system, icon,
  key map, UTI, drag, permission and QML JIT (`MAP_JIT`) fallbacks before
  10.14; IOKit port, safe area and CoreVideo attachments before 12; os_activity
  and unified logging before 10.12; Metal, save dialog and text-to-speech
  calls guarded by version where the availability audit found them unguarded;
  QtNfc's PC/SC lookup made to work in projects that use the SDK.

## Writing a patch

Produce it against pristine sources (`git diff` in an unpacked archive put
under git works), put the SPDX line and header first, number it after the
last patch of its series, and check that the series still applies:
the scratch check used here unpacks the archive into a Docker volume,
commits it, and applies every patch in order. A patch that changes behaviour
needs a check in `tests/` that shows it on the floor and on a current system.
