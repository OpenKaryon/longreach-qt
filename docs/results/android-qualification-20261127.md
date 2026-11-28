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
| Qt5 AndroidExtras at each native floor | API10 ARMv7/x86 and API21 ARM64/x64: eight checks, two natural service exits, 16 transactions/callbacks and natural parent exit per ABI | Callers must quiesce callbacks before C++ destruction, including derived destruction; concurrent callback/destruction and asynchronous close are outside the agreed contract. Exhaustive API/class coverage is unqualified |
| Qt5 TTS at the API10 native floor | Eight muted functional checks and natural exit on ARMv7/x86 | API21 provider behavior is separate; no audible-output guarantee |
| Qt5 WAV20 at the API10 native floor | Twenty distinct successful native/natural/owned runs on ARMv7 and on x86 | All 20 retain OpenSLES engine Destroy ignored/two-active-object warnings; no leak-freedom claim |
| Qt5 API10 APK forward Extras on API21 | x86 functional8/native0 and two natural service exits/16RPC verified separately | Both overall controls FAILED on observer timeouts; parent natural exit unproven. ARMv7 has no completed functional summary. Core-only forward compatibility does not imply Extras qualification |
| Native sensor input and compass | API10 x86 queue teardown; API21 ARM64 stock32 nonzero input/32 callbacks, plus five input-controlled directions with 25 measured Qt samples and five natural exits | API10 ARMv7 stock inventory is zero; physical calibration/accuracy, compass timestamps and raw-angle range remain unqualified |
| Library TLS lifetime | Retained QLibrary controls on API10 ARMv7/API21 ARM64+x64; positive Qt5 API21 ARM64 QPluginLoader: six checks, one worker43, TLS destructor1 before unload, plugin object deleted after join; natural/final/owned exit | Keep owner loaded through every using thread/TLS destructor. Other Qt5 ABIs/concurrency and OS unmapping remain unqualified; the separate Qt6 matrix below does not permit live-TLS unload or callback after unmapping |
| API21 files larger than 2 GiB | POSIX64 passes on all four ABIs; native C/C++ stdio also passes on 64-bit |32-bit fstream seek fails; use POSIX64. API10/YAFFS, arbitrary sizes and Qt filesystem APIs require separate validation |

The separate Qt5 ARM64 compass run reuses native SDK `80f28520`/`f25be055`
with fresh `8c214a8` clients/APKs. All five known directions pass four checks
and five consecutive input-matched samples each: 20 PASS, 0 FAIL, 0 SKIP.
Observed raw angles are `0`, `45`, `90`, `-180`, `-90` for expected directions
`0`, `45`, `90`, `180`, `270`; errors modulo a turn are zero in these samples.
The first runner attempt failed before checks on a multiword `am` extra;
its native return 2, logs and disks remain failed. Quoting was corrected with the
existing shell helper, without changing the SDK/APKs or original reports.
All 25 native compass timestamps are zero, so timestamp/rate behavior and
physical calibration accuracy are not qualified by this direction result.

The separate positive Qt5 ARM64/API21 plugin control reuses native SDK
`80f28520`/`f25be055` with a fresh opt-in `cc752474` core client and real Qt
plugin. All six checks pass. One worker call returns 43, with exactly one TLS
destructor completed by `std::thread::join` while the loaded owner and plugin
object remain alive. Only then is the loader unloaded and the object deleted.
The compiled/deployed/packaged native bytes, absence of eager loading, native
return, natural application exit, final capture and owned process closure were
independently verified. This does not qualify another ABI/Qt generation,
arbitrary concurrency or operating-system mapping removal.

The separate Qt6 API21 plugin matrix uses opt-in source `169725a0` with the
original `d82ca045` SDK producer. All four ABIs pass six native functional
checks: an authoritative application native-library directory, real plugin
metadata/interface, one worker return of 43, exactly one TLS destructor before
unload, and plugin-object deletion after join.

| Qt6 ABI | Native checks | Whole bounded procedure |
| --- | --- | --- |
| `armeabi-v7a` | 6/0/0, return 0 | FAILED/DEFERRED: capped host-exit observer; required strict exit/APK release receipts are incomplete |
| `arm64-v8a` | 6/0/0, return 0 | PASS: natural application exit, final log capture and owned host closure |
| `x86` | 6/0/0, return 0 | PASS: natural application exit, final log capture and owned host closure |
| `x86_64` | 6/0/0, return 0 | PASS with the baseline explicit AM32 helper: natural exit, final capture and owned host closure |

The ARMv7 final log separately records the same PID's natural death, but this
does not replace missing producer receipts or relabel the original failed
procedure. It is not retried. Earlier lookup and typed-context compilation
failures remain preserved. The source-correction budget stays at 9 of 10;
unchanged-source ABI qualification does not reset it. Neither this matrix nor
the single x64 AM32 run establishes general helper reliability, arbitrary plugin
concurrency, OS unmapping, or physical behavior. Baseline full11 identities and
results remain unchanged.

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
