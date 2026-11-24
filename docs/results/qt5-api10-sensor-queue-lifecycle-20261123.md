# Qt5 API10 x86 sensor queue and shutdown result, 2026-11-23

Qt5.15.19 / LLVM21.1.8 was rebuilt for x86/API10 with the futex forward-compatibility
correction, condition-clock patch28 and sensor queue lifecycle patch29. Native
queue destruction waits for looper dispatch to return; queued delivery observes
retirement, and polling stops before application/Binder teardown. The compass
uses the same ownership path. Temporary crash recording is absent from the APK.

| Run | Measured result |
| --- | --- |
| SDK producer | 198 libraries passed the producer checks |
| API10 focused extended selftest | 109 PASS, 0 FAIL, 4 SKIP; natural exit |
| API10 complete suite | 14/14; observed application and owned guest termination |
| API10 core APK on API21 | 213 PASS, 0 FAIL, 63 SKIP; natural exit |
| API21 extended selftest | 109 PASS, 0 FAIL, 4 SKIP; natural exit |

Sensor observations include 32 accelerometer lifecycles with actual readings
on API10 and API21, plus32 compass lifecycles on each guest. API10 compass
coverage is teardown during a verified acceleration stream: its HAL expects
`magnetic-field`, while the fixed classic emulator sends `magnetic`, so headings
were unavailable. API21 supplied actual compass readings for all 32 lifecycles.
The API21 compatibility runs remain diagnostics, not full API21 suite results.

SDK image: `longreach-qt5-android-gingerbread-x86:sensor-clock-20261123-v8`.
Immutable image ID:
`sha256:9316ba8f58be01ee3f1b2e40fbdc8d13fd1a36c04713ac3a9f62fbc21d29f5a9`.
The already-built classic emulator was unchanged, SHA256
`0c37bfe93b3f9d9cfb5ffa829624f9b36dae301eee05926ba4a45837bc0b1986`.

One OpenGL APK transfer expired at the former 180s limit before application
launch; its successful same-batch retry took 188s. Classic x86 APK push now has
a bounded 600s budget and an elapsed-time receipt. The final collector accepted
all 14 cases bound to the same unchanged SDK/APK batch.

Eleven host callback/retirement behavior checks and three positive transfer
wrapper checks passed. They supplement the guest results without qualifying
other ABIs or Qt4/Qt6. No emulator rebuild or security suite was involved.
Raw receipts, paths and working notes are retained in the private test lab.
The subsequent script-directory/documentation cleanup did not rebuild this SDK;
these measurements describe the generation identified above.
