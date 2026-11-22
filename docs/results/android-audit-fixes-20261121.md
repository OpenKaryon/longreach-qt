# Android audit follow-up — 2026-11-21

This correction pass covers the confirmed API10 x86 futex defect, Qt 4 cache
inputs, Android artifact ownership/provenance, Qt 4 native ABI preflight and
ordinary coverage gates. Builds and guests run sequentially. No push, release
tag or local security suite is part of this pass.

## M1: API10 x86 timed futex waits

The existing SDK reproduced the Bionic generic `syscall()` return defect in
Qt 5 timed waits. With stale `errno=ETIMEDOUT`, a mutex and semaphore released
by a worker were incorrectly reported as timeouts (about 268 ms and 261 ms).
Actual 200 ms timeout checks and QFileSystemWatcher file delivery passed.
The baseline failure is retained under
`artifacts/android-review-20261121/m1/baseline-2/`.

The exact locked NDK r7 x86 input exports Bionic's six-argument `futex` stub.
`patches/qt5/android/x86/01-api10-futex-stub.patch` makes Qt's `_q_futex` call
that stub only on Android i386 before API21. Other targets retain their
existing implementation. The locked x86 headers do not define
`__NR_inotify_init1`; the old inotify fallback already works. No broad generic
syscall replacement or speculative inotify patch was introduced.

The retained native build recompiled only `qmutex.cpp` and `qsemaphore.cpp`,
reinstalled QtCore and passed the existing 198-library API10 ELF validation.
The focused fixed APK passed all five Qt behavior checks: timed mutex wake,
mutex timeout, semaphore wake, semaphore timeout and a real file-change event.
Evidence is in `m1/fixed-1/files/selftest.stdout`; the raw generic syscall
remains a diagnostic OS limitation, not a newly supported consumer interface.

Four timed mutex/semaphore checks were added to the shared Qt 5/6 selftest,
including successful wakeups with stale ETIMEDOUT. The same application sources
remain shared with desktop targets; Qt 4's existing source branch is retained.
The canonical 25 modern-C++ checks remain a separate strict profile.

The refreshed installed SDK is
`sha256:b039116780201a5fb4e7395396184ded7a570ea91e6c572ffaddfb355e51c5c6`.
Its QtCore SHA256 is `2f290de9cf1b94c6216fdba1c256b7d6d30411ddc5829a80ee5a0c562de49345`; runtime remains
`c253eff8207403db045f4980c07620f213e7e31427e9f2680c784570eee33489`.
All 58 recorded patch hashes match the target stack used in that batch, fingerprint
`2ebdeee0f2abfdc2d54bc2c9bde0a777533326aacaf6cec434a3274c985e1c53`.
A comparison of installed shared libraries found only QtCore changed relative
to the previous qualified x86 SDK. The other native modules were reused.

## M3: retained Qt 4 caches

SDK configuration fingerprints now include the actual compiler executable and
version, runtime wrappers/target settings, mkspec and runtime/platform headers.
Public Docker SDK builds retain an ABI-specific `/work` BuildKit cache with
exclusive sharing. Public example builds retain a client volume per ABI/output
root and include installed headers and qmake/moc/rcc/uic in the compile key.
Archive-manifest changes retain objects and trigger only relinking.

A small actual installed-SDK Qt 4 x86 client verified this sequence:

| Operation | C++ compilations |
| --- | ---: |
| First build | 1 |
| Unchanged repeat | 0 |
| Changed SDK header | 1 |
| Changed archive manifest only | 0 |

The controlled SDK/header changes were confined to a disposable diagnostic
container and never promoted into a factory SDK. Logs are retained under
`artifacts/android-review-20261121/cache/`. Ordinary fixtures additionally
verify compiler binary, flags, mkspec and header invalidation. An older cache
without the expanded key may need one conservative rebuild on first use.
No complete Qt 4 SDK rebuild was needed for this correction.

## M7 and L1: generations, packaging and ABI

Qt 5/6 APK schema 2 records the native generation digest and captures host Java
sources, package scripts, actual Android/JDK tool files, SDK producer reports
and signing inputs before replacing APKs. Completion rechecks that snapshot.
A Java-only host-adapter edit can repackage a frozen native generation; the
receipt does not misrepresent it as a new native compilation. APK symlinks or
junctions are rejected. In-progress markers cannot silently be overwritten.
An OS file lease prevents concurrent phase entry into one artifact root.
The JDK snapshot includes tools and modules/configuration, including Java
selected by JAVA_HOME/PATH for D8/apksigner rather than assuming javac's JDK.

Qt 4 native manifests now record ABI/API/SDK/runtime identity. Package mode
checks all twelve native client hashes and ELF class/machine before touching
any APK. The fixture rejects x86 bytes requested as ARM64; the shared ELF
unit fixture covers all five Android ABI names. Direct Qt 4 packaging uses
the same actual-ELF check, including Donut. A read-only check of the 39 saved
Qt 4 JNI/runtime libraries (13 each for x86, x86_64 and ARM64) also passed.

## M5: ordinary coverage

A committed baseline records minimum PASS and maximum SKIP for every qualified
case/target, plus named critical GL and repaired synchronization PASS results.
The runners and final collectors enforce those limits. A degraded Qt 4 GL
report with 2 PASS / 12 SKIP fails, as does a missing shader PASS even if the
summary retains the old totals. All 118 available historical ordinary/strict
reports inspected for the unaffected targets met their selected baselines.
This is a parser/coverage check of saved evidence, not a new runtime run.
Strict C++23 still requires all canonical 25 checks and zero SKIP.

The historical Qt 5 API10 final batch used a thirteen-case collector. It binds each
result to a hash/SDK receipt made before APK installation, captured stdout,
correct guest properties, native exit zero and exact packaged ABI/runtime.
The public suite writes `final-results.json`, `final-results-table.md` and
`apk-native-abi-check.json` through that collector.

## Additional failure exposed by the full consumer run

The first refreshed suite stopped at QML visual-file compilation: the Fusion
module was reported unavailable. Its plugin and resources were present and
matched the earlier deployment. A separate debug-plugin run passed but showed
API10 Bionic's 96-DSO pool exhausting while loading image handlers. This is consistent with a plugin-load-order failure; that
diagnostic pass is not full qualification.
The failed `audit-suite-1` and `qml-debug-1` logs are retained.

API10 QML example packaging now limits optional image handlers to the deployer's
GIF/JPEG/SVG selection and retains Qt's built-in PNG support. Unused desktop image
handlers are omitted from that APK
so that the loader has headroom. Other applications and API21 packages retain
the full deployer selection. In the measured x86 APK this retains GIF/JPEG and
reduces packaged native libraries from 62 to 57. The repeated debug run
`qml-debug-2` passed 24/0/14 with no loader-pool errors. The installed native SDK, QML
resources and application binaries are unchanged by this packaging correction. A small
PowerShell fixture verifies optional selection and the unchanged default.

## API10 guest suspension during longer selftests

A later full run timed out after `process/run`. A trace-only rebuild of the
shared selftest located the next check at TCP loopback. A native stack snapshot
showed Qt's Android event dispatcher waiting on its suspension semaphore.
Bringing the existing Activity back to the foreground immediately continued
network checks. This diagnostic was not counted as successful qualification.
The timed-out `audit-suite-2`, `audit-suite-3` and `selftest-trace-1` reports are
retained. The separate `selftest-awake-2` passed, but the repeated full run
showed that power policy alone was insufficient: Android still reported the
Activity RESUMED/focused while Qt waited on its suspension semaphore.

The legacy runner now explicitly enables stay-awake on all emulator power
sources before launching the APK, verifies the guest's setting and saves
`power-before.txt`. The launch receipt binds that file's hash and the API10
collector requires the confirmed policy (AC/USB value 3 on API10, or value 7
including wireless on later releases). A fixture rejects an unconfirmed
power setting. The power setting affects the disposable guest, not host power
settings. The Qt 5 console `qt-selftest` APK additionally uses
Qt's existing `android.app.background_running=true` metadata: it runs its
synchronous checks without an outer app.exec(), so those checks must not wait
for an Activity resume. Other GUI example APKs retain their normal lifecycle
policy. This is a test-package setting; the Qt SDK is not patched to ignore
suspension for arbitrary applications.


## Final installed-APK qualification

The public `examples` / `package` / `test` entry points completed with the
refreshed x86 SDK. The final ordinary run is
`artifacts/android-review-20261121/qt5-x86/audit-suite-4/`.
The repository API10 collector accepted all thirteen cases, verified each
pre-install APK/SDK receipt, native exit zero, guest/API/ABI, saved stdout,
confirmed power policy and exact packaged ELF/runtime. Both core and extended
strict C++23 profiles passed the canonical 25 checks without SKIP.

| Case | PASS | FAIL | SKIP |
| --- | ---: | ---: | ---: |
| qt-selftest | 213 | 0 | 63 |
| widgets-gallery | 90 | 0 | 5 |
| graphics-gallery | 32 | 0 | 0 |
| painting-lab | 16 | 0 | 0 |
| multimedia-lab | 4 | 0 | 0 |
| gl-heavy-gallery | 38 | 0 | 8 |
| quick-qml-gallery | 24 | 0 | 14 |
| network-gui | 7 | 0 | 0 |
| strict-cxx23 | 25 | 0 | 0 |
| strict-cxx23-extended | 25 | 0 | 0 |
| qt-selftest-extended | 106 | 0 | 4 |
| widgets-gallery-render | 16 | 0 | 0 |
| quick-qml-gallery-render | 3 | 0 | 0 |

The final APK manifest captures nine APKs, two local signing-key hashes and
315 Android/JDK tool files, including JDK modules. The native source generation
and SDK stayed unchanged during packaging corrections. No trace-only binary
or manually resumed diagnostic was used in this full qualification.

One earlier focused start of this same headless APK (`selftest-background-1`)
still timed out after `process/run`; its cause was not isolated before the
successful `selftest-background-2` and full `audit-suite-4` runs. These results
establish the successful final batch, not elimination of every intermittent
API10 startup stall. That remaining stability issue needs a separate captured
native stack if it recurs; failed attempts remain available for inspection.

Forty ordinary Python unit tests and seven PowerShell fixtures passed. They
cover phase isolation, cache invalidation, incomplete generations, input changes,
root ownership, native ABI, coverage degradation, packaging policy, guest power
policy and complete API10 finalization. Python/PowerShell syntax, the existing
coverage inventory and license reports were also checked separately. Local
security suites/scanners were not run.

## Later x86 preflight and local review

The current x86 suite adds an `--atomic-cow` check before QGuiApplication and
requires fourteen cases with one consistent emulator identity. The historical
thirteen-case batch above predates that check and does not qualify the new
fourteen-case suite or establish that the intermittent stall is fixed.

The COW probe checks Qt, standard-library and compiler atomics on a separate
private mapping after fork. A supplied already-built classic emulator can be
selected with `-Mode test -Abi x86 -Emulator /path/to/emulator-x86.exe`; its
hash is recorded for every case. Without an override, SDK emulator launch
arguments are retained and an affected stock emulator fails the preflight.

Local review on 2026-11-22 also corrected stale aggregate results after a
failed new run or collection. Regression fixtures exercise emulator selection,
preflight ordering, default SDK-tool routing and invalidation without launching
guests. Review validation passed 41 ordinary Python tests and eight PowerShell
fixtures, plus compilation syntax checks of the two changed C++ translation
units against the saved Qt 5 x86 SDK. The emulator was not rebuilt. At the end
of that review, a new installed-APK run was still pending.

## Sound-cache shutdown follow-up, 2026-11-22

The first subsequent fourteen-case attempt found a real extended-selftest
teardown SIGSEGV after its 106 successful checks. The failure was retained.
A narrow x86 QtMultimedia correction stops the loader before locking and
detaches samples before cache-owned deletion. Two focused non-instrumented
runs and a new complete fourteen-case batch passed the existing cleanup gate.
See the [recorded result](qt5-android-gingerbread-x86-sample-cache-fix-20261122.md) for the 59-patch SDK identity, unchanged
QtCore/runtime/emulator hashes, exact counts and remaining scope limits.

## Findings not converted into speculative changes

The claimed hidden `__emutls_get_address` defect was not present in the
inspected eight Qt 5/6 C++ runtimes: the symbol was WEAK/DEFAULT, and the six
inspected QtCore DSOs referenced it as undefined. LLVM 21.1.8's emutls source
explicitly exports it for cross-DSO coalescing. The audit's proposed check for
`__emutls_register_common` is not applicable to that source version. No TLS
runtime rebuild was performed on that premise.

A desktop regression from the default-font glyph check was not reproduced.
That check is unchanged in this pass. Hardware/backend gaps and the broader
lower-priority audit list remain separate from the confirmed corrections.

## Historical provenance and reproduction

The Qt 5 ARM64 report retains its actual 56-patch fingerprint. Later Java-only
patch 02/27 changes are not a native rebuild or a fresh ARM64 installed-APK
qualification. The older ARMv7 API10 consumer report likewise does not qualify
later runtime-header producer changes. Those limits are explicit in the older
result documents; passing x86/x86_64 runs do not substitute for ARM results.

See [Android generations and coverage](../targets/android-artifacts.md) for
receipt recovery, the explicit private-ADB environment and ordinary test names.
