# Android qualification snapshot — updated 2026-11-28

The twelve recorded installed-SDK profiles have complete passing emulator
suites or the explicitly limited API4 resident diagnostics below. Android as
a whole remains incomplete: separate audio/provider, forward-lifecycle and
physical-device requirements are still open.

The [machine-readable snapshot](android-qualification-20261127.json) contains
the exact SDK image IDs, producer/client/runner commits, APK manifest and APK
SHA256 values, per-case counts, named SKIPs and gallery image hashes. SDK reuse
keeps the original producer identity; rebuilding clients does not create a new SDK.

| Profile | API | ABI | Cases | PASS/FAIL/SKIP | SDK image ID prefix |
| --- | ---: | --- | ---: | --- | --- |
| Qt4 | 4 | `armeabi` | 8 | 185/0/124 | `43b0b06e8532` |
| Qt4 | 10 | `x86` | 12 | 383/0/138 | `6634cc1782d2` |
| Qt4 | 21 | `arm64-v8a` | 12 | 383/0/138 | `d3ed268c36d7` |
| Qt4 | 21 | `x86_64` | 12 | 383/0/138 | `5277aa06c21a` |
| Qt5 | 10 | `armeabi-v7a` | 13 | 599/0/97 | `f58612b1c4ba` |
| Qt5 | 10 | `x86` | 14 | 605/0/94 | `0442f5f17ba0` |
| Qt5 | 21 | `arm64-v8a` | 13 | 618/0/91 | `f25be055bb4f` |
| Qt5 | 21 | `x86_64` | 13 | 618/0/91 | `c2060eb2ac4f` |
| Qt6 | 21 | `arm64-v8a` | 11 | 584/0/53 | `e24197b44d64` |
| Qt6 | 21 | `armeabi-v7a` | 11 | 584/0/53 | `a49e9448acd8` |
| Qt6 | 21 | `x86` | 11 | 584/0/53 | `0aa0740fd365` |
| Qt6 | 21 | `x86_64` | 11 | 584/0/53 | `dd9121c8c6c7` |

Qt5/Qt6 results require observed natural application exits, final log capture
and closed owned host trees. Qt4 uses resident JNI with explicit release/cleanup
and owned host closure; it does not claim natural Android process termination.
Two actual gallery PNGs were reviewed for each profile except API4. API4 has
five GUI interaction assertions, but no exported PNG/visual-review evidence.
The host PNG export was added in `9e861e2` and its ordinary fixtures/source CI
pass. A fresh follow-up using the unchanged SDK6982/e990 native/APKs passed
bootstrap, then stopped before strict native execution on a 5-second ADB
readiness query timeout. Quick did not execute and no PNG was exported. This
failed follow-up leaves API4 visual coverage open and preserves the original
eight-diagnostic result and producer identities above.

## Separate behavior coverage

| Check | Confirmed scope | Remaining boundary |
| --- | --- | --- |
| Qt6 TTS on API21 ARMv7/x86 | Eight muted functional checks, including oversized-input error/recovery, bounded stop/pause/resume/replacement and recreation; natural app/owned exit | No audible-output or sample-position guarantee |
| Qt6 TTS on API21 ARM64 | One check passes; short-speech output fails, six checks do not execute; stock AudioTrack/output and Pico64 shutdown failures retained | No successful TTS diagnostic or natural-exit proof |
| Qt6 TTS on API21 x86_64 | Eight functional checks/native0, then stock Pico64 shutdown SIGSEGV | Overall FAILED; native0 does not imply natural process exit |
| Qt5 AndroidExtras at each native floor | API10 ARMv7/x86 and API21 ARM64/x64: eight checks, two natural service exits, 16 transactions/callbacks and natural parent exit per ABI | Bounded API paths; not exhaustive API/class or concurrent destruction coverage |
| Qt5 TTS at the API10 native floor | Eight muted functional checks and natural exit on ARMv7/x86 | API21 provider behavior is separate; no audible-output guarantee |
| Qt5 WAV20 at the API10 native floor | Twenty distinct successful native/natural/owned runs on ARMv7 and on x86 | All 20 retain OpenSLES engine Destroy ignored/two-active-object warnings; no leak-freedom claim |
| Qt5 API10 APK forward Extras on API21 | x86 functional8/native0 and two natural service exits/16RPC verified separately | Both overall controls FAILED on observer timeouts; parent natural exit unproven. ARMv7 has no completed functional summary. Core-only forward compatibility does not imply Extras qualification |
| Native sensor input | API10 x86 has recorded acceleration/compass queue teardown; API21 ARM64 stock32 supplies nonzero magnetic input and 32 Qt compass callbacks | API10 ARMv7 stock inventory is zero; ARM64 numeric azimuth/calibration and physical accuracy remain unqualified |
| Library TLS lifetime | Keep QLibrary/QPluginLoader alive until all using threads and TLS destructors complete; bounded QLibrary controls on recorded API10 ARMv7/API21 ARM64+x64 | No live-TLS unload or callback after unmapping; other ABI/plugin scenarios need separate evidence |
| API21 files larger than 2 GiB | POSIX64 passes on all four ABIs; native C/C++ stdio also passes on 64-bit |32-bit fstream seek fails; use POSIX64. API10/YAFFS, arbitrary sizes and Qt filesystem APIs require separate validation |

WAV stress is independent of the full suites and muted TTS probes. The current
Qt6 x86 whole series passed all twenty fresh guest/app runs, with independently
reverified native results, natural exits and owned host closure. The current
Qt6 ARMv7 series stops after one pass and a second pre-Qt boot failure. The x86
whole 20 status is recorded separately in the JSON snapshot; no failed series
is resumed or relabeled as 20 PASS. The x64 series failed on run six after
five verified successes: the Android AM32 command crashed in a Binder thread
at VM shutdown. The application was launched, but no sixth native/WAV/natural
result was obtained. Final logs and closed owned-tree proof were retained;
this does not establish a Qt/WAV or Pico root cause. ARM64 output and x64
whole 20 remain unqualified.
WAV probes use silent PCM Ready/play for 100 ms/stop/destroy; they do not establish
audible sound, leak freedom or physical-device behavior.

No physical Android device was available. Camera, Bluetooth/NFC/GPS, real sensor
accuracy and audible output remain unqualified. Retained historical failures
are not reclassified by newer successful generations. The frozen corrected
classic x86 emulator is reused without a new build; complete rebuild
reproducibility is not established by successful runtime recovery.
