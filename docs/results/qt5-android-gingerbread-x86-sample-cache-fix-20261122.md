# Qt 5 API10 x86: sound-cache shutdown correction, 2026-11-22

The corrected SDK passed all fourteen required installed-APK cases in one
sequential batch, including clean application teardown. The existing corrected
emulator was reused byte for byte. Only one QtMultimedia source object was
rebuilt; the QtCore and C++ runtime were retained.

## Failure and correction

The earlier `patched-emulator-14` attempt completed the extended selftest's
106 checks with 4 intentional SKIP and wrote native result zero, but then
received SIGSEGV during process teardown. The captured stack passed through
`QSampleCache`, `QSample`, `removeUnreferencedSample` and `QMutex::lock`.
That attempt remains recorded as thirteen successful cases and one failure;
its zero-valued result file was not accepted as clean completion.

`patches/qt5/android/x86/02-sample-cache-shutdown.patch` stops and joins the
loader before taking the cache mutex. Cache-owned samples are detached from
their parent before deletion, so their destructor does not re-enter a cache
that is already being destroyed. Ordinary deletion still updates a live
cache's stale-sample set. The correction is currently enabled only for x86.

A trace-only diagnostic passed once; it was not promoted to qualification.
Two subsequent focused runs using the non-instrumented corrected module
completed 106 PASS / 0 FAIL / 4 SKIP and passed the unchanged fatal-cleanup
gate. The full batch below adds a third successful extended-selftest teardown
inside a freshly built and packaged example generation.

## Identities and procedure

- Source commit: `8d198ef3d8eddc21dcd6a1788d35fa247fd68830`.
- SDK: `sha256:946c79273e7869bd58b8ffe7c01e712bb6169e25a907ddfef5f859d3b50b0b35`.
- Qt 5.15.19; LLVM 21.1.8; Android API10 x86.
- QtMultimedia SHA-256: `651abfdb4b1ea2c65632b6f0d3642398d2eb7ad4fc52394bc1507572c142ac82`.
- Unchanged QtCore SHA-256: `2f290de9cf1b94c6216fdba1c256b7d6d30411ddc5829a80ee5a0c562de49345`.
- Unchanged C++ runtime SHA-256: `c253eff8207403db045f4980c07620f213e7e31427e9f2680c784570eee33489`.
- Unchanged emulator SHA-256: `0c37bfe93b3f9d9cfb5ffa829624f9b36dae301eee05926ba4a45837bc0b1986`.
- Native application generation: `f45bb6a50afb4873b1864021c17153df`.
- Producer patch stack: 59 patches, fingerprint `8494e75f08e667952c55776d5883894aa845b158c5dfb2efe4444c14ba309e7c`.

The narrow module rebuild passed the existing validation of all 198 target
DSOs. A byte comparison of the exported SDK shared libraries found exactly
one changed file: `lib/libQt5Multimedia_x86.so`. The application source checks,
required counts, native-result policy and fatal-cleanup checks were unchanged.

Public `examples`, `package` and `test` modes produced a new native generation,
nine APKs and the fourteen-case run. Test mode selected the already-built
classic emulator using `-Emulator`. Each case used a fresh disposable guest
and a separate local ADB server isolated the batch from other projects.

The collector verified every complete launch receipt, exact APK/runtime,
guest/API/ABI, stdout hashes, power policy, coverage and clean native exit,
including one identical emulator hash for all fourteen cases. Both strict
C++23 profiles passed the canonical 25 checks without SKIP. Post-run checks
matched current application/packaging sources and all 59 patch hashes.

## Results

| Case | PASS | FAIL | SKIP |
| --- | ---: | ---: | ---: |
| atomic-cow | 3 | 0 | 0 |
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


## Evidence and limits

Machine-readable result: [qt5-android-gingerbread-x86-sample-cache-fix-20261122.json](qt5-android-gingerbread-x86-sample-cache-fix-20261122.json).
Raw evidence is retained under the ignored local root
`artifacts/qt5-sample-cache-fixed-qualification-20261122/`. Its
`sample-cache-fixed-14/` directory contains each case's launch receipt,
stdout, result, guest details and logcat; the root contains native/APK/final
manifests and `apk-native-abi-check.json`.

The two focused fixed runs and the earlier trace are retained separately under
`artifacts/qt5-sample-cache-exit-20261122/`. The previous thirteen-of-fourteen
attempt remains under `artifacts/qt5-api10-fixed-emulator-20261122/`.

These results establish this recorded x86 SDK/emulator batch and the focused
cleanup regressions. They do not establish unlimited startup/teardown stress
coverage or qualify another ABI, device or the affected stock emulator.
No security suites, repository scanners or emulator rebuilds were run.
