# Qt5 API10 ARMv7 SDK qualification, 2026-11-24 campaign

A fresh Qt5.15.19 / LLVM21.1.8 SDK, examples and nine APK deployments were
built from `e35b4b7910bea868b94c807012976acfb8c3bc6f` for `armeabi-v7a`. All 13 required smoke
profiles completed on stock Android 2.3.3/API10, with native return code zero,
observed app termination and empty owned host process trees.
Retained API10 and API21 evidence was revalidated unchanged with the stricter
ordinary/native coverage floor in `abe6ae982f2d04a1e25a7e3d1a6e1846e6d550b0`; native inputs
were unchanged by that validator correction.

**Native sensor queues remain unqualified on this guest.** Three native sensor
checks are named SKIPs: Android's C and Java APIs expose zero sensors. This was
also measured in a minimal C APK without Qt or libc++, and with libc++ preloaded.
Early boot reports that the stock Sensors HAL cannot open its device (`EINVAL`).
Four static HAL entries in `dumpsys` do not establish an available sensor list.
Neither the emulator nor the guest HAL was patched to obtain a passing result.

| API10 profile | PASS | FAIL | SKIP |
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
| qt-selftest-extended | 106 | 0 | 7 |
| widgets-gallery-render | 16 | 0 | 0 |
| quick-qml-gallery-render | 3 | 0 | 0 |

Both strict C++23 profiles passed all 25 mandatory checks without skips.
Widgets and QML gallery cases include rendered PNG evidence. Timed mutex and
semaphore observations passed the current waiting/timeout gates.

The extended policy retains its 106 ordinary PASS floor and requires the
ordinary Qt Sensors checks. Its three native outcomes are independently bound
to an Android C API inventory: only `count=0` permits their exact named SKIPs;
a positive count requires all three PASS results. Missing, failed or ambiguous
inventory and unrelated SKIPs fail. The collector records `native_sensor_count=0`
and `native_sensor_coverage=unavailable`. Verified console input values alone
do not establish delivery through the guest HAL.

| Separate API21 check | PASS | FAIL | SKIP |
| --- | ---: | ---: | ---: |
| API10 core APK on Android 5.0.2/API21 | 213 | 0 | 63 |

This is one compatibility diagnostic with clean observed exits,
`source_api=coverage_api=10`, `guest_api=21` and `qualification=false`.
It does not qualify the full API21 suite or native sensor queues. Afterward,
the API10 collector revalidated the retained complete batch and reproduced its
report without rerunning guests or replacing their evidence.

## Corrections and generation

- Legacy ARM `atexit` callbacks bind to their own DSO through `__cxa_atexit`,
  retaining independent teardown ownership and removing an unavailable API21
  import. Actual guest compatibility supplements the symbol availability gate.
- The API10 runner keeps file-backed logcat in the emulator's Windows Job.
  Readiness, snapshot fences and hashes preserve launch/PID evidence through
  noisy QML/EGL kernel ring rotation. Fatal and termination gates remain strict.
- Classic API21 ARM uses an AVD inside its owned run. Mutable hardware files
  stay outside sealed media; exact AVD/config inputs are retained in identity
  receipts. Prepared media hashes and the complete file set remain mandatory.
- Native sensor availability is measured separately from Qt backend behavior.
  The upstream self-importing static plugin is retained. Failed diagnostic
  attempts remain preserved, including the discarded metadata-IID hypothesis.

SDK image: `longreach-qt5-android-gingerbread:armv7-qualification-20261124-r6`.

Immutable image ID: `sha256:405212fabc8e8152d82a7f0b9de25fe96bd842cdb6992514e1d319bb345e0909`.

Source tree: `b105d35ee3626573385f7ee2d9e75a4a433e8877`.

APK manifest SHA256: `c32a8b56cd0ffd8821c70fa3414e635a5aaa83555c94649e4632d9d47639c93b`.

API10 emulator SHA256: `793999bc180773d822ea2c7c6725c54a0e3b588afc177209b2d91bd0e6af1274`.

The sealed SDK producer reports cover all 198 installed libraries, including
API21 dependency symbol availability. SDK compilation used four jobs through
QtBase, with the later module limit raised to at most eight; examples
ran sequentially with two jobs, two CPUs and 3 GiB RAM. BuildKit caches were
retained and Docker provenance stayed enabled. Sealed producer reports and
bound guest receipts, rather than the completeness of compiler-log text,
establish the measured generation.

The [source CI](https://github.com/OpenKaryon/longreach-qt/actions/runs/45528930461) passed 303 Android Python tests (11 environment
skips), 33 PowerShell fixtures and the ordinary repository checks, including
automatic leak/SPDX checks. Security suites were not run locally.

Stock API10 Qt Quick uses software rendering. Console APKs retain
`android.app.background_running=true`; Activity pause/resume remains outside
this qualification. The classic API10 frontend used 1024 MiB RAM; this run
does not establish a lower memory floor. Physical hardware, repeated WAV teardown and other Android
profiles retain their stated gaps. Raw receipts, named skips, source/CI records
and host paths are retained in the private lab.
