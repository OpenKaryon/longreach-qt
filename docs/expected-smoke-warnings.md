# Expected Smoke Warning Noise

These messages are expected in some smoke runs and do not by themselves mark a
failure. A run still fails if an app exits non-zero, crashes, times out, or
prints a failing self-test line.

## Static Plugin Discovery

Expected patterns:

- `Could not load  Q...Plugin(...)`
- `Could not load  ...Factory...(...)`

Reason: the static build links plugin metadata into the process. Some smoke
checks intentionally enumerate plugin interfaces even when the current platform
does not support every plugin backend.

## Multimedia Backends

Expected patterns:

- `defaultServiceProvider::requestService(): no service found for - "..."`
- `QSoundEffect(qaudio): Error decoding source file:nonexistent.wav`
- backend-specific media player or audio device messages followed by `SKIP` or
  `PASS`.

Reason: VM images and minimal systems often lack audio/video services. Tests
that need a real backend should report `SKIP` when the service is absent.

## Bluetooth, NFC, Gamepad, And Sensors

Expected patterns:

- dummy Bluetooth backend messages;
- missing local radio/controller messages;
- `Unable to load 'bluetoothapis' library.`;
- inaccessible `/dev/input/...` device messages;
- missing XInput library messages.

Reason: most smoke environments do not expose these devices to the guest OS.
The tests exercise value types, construction paths, and safe discovery behavior.

## Printer And Desktop Helpers

Expected patterns:

- `QPrintDialog: Cannot be used on non-native printers`
- `QPageSetupDialog: Cannot be used on non-native printers`
- Windows taskbar/jumplist COM interface messages on pre-Windows-7 systems.

Reason: the smoke suite runs on minimal VMs and legacy OS versions where native
desktop shell services are missing or intentionally older.

## OpenGL And Visual Gallery Guards

Expected patterns:

- `makeCurrent: SetPixelFormat() failed` on legacy Windows OpenGL paths when a
  guarded shell test reports `SKIP`;
- DataVisualization or Qt3D visual placeholders on documented driver stacks.

Reason: visual examples are gated by platform and driver capability. API-level
self-tests remain active where a visual gallery is intentionally disabled.

Not a warning but a hard stop: `Could not initialize GLX` followed by an abort
means the X server offers no GLX visual at all. `xvfb-run` with no `-s`
starts an 8-bit screen, which is such a server, and Qt 6's GLX code (both the
`offscreen` and `xcb` platforms) calls `qFatal` there; stock Qt does the same.
Run headless with `xvfb-run -a -s "-screen 0 1280x1024x24"`, as the Makefile's
proofs do, or with `QT_QPA_PLATFORM=offscreen` and no `DISPLAY`, where no GL
context is created and the GL checks skip themselves.

## TLS Trust Store Messages

Expected patterns:

- `qt.network.ssl: Error receiving trust for a CA certificate`

Reason: the TLS smoke test uses local loopback certificates. Some platforms log
trust-store diagnostics while still completing the loopback handshake.

