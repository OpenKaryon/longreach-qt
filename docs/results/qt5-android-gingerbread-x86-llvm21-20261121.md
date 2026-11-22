# Qt 5.15.19 Android API 10 x86 on LLVM 21.1.8

The complete SDK and all eight shared applications passed qualification in
the official API 10 x86 emulator. The guest actually reports **Android 2.3.7**.
Both core and extended selftest APKs passed **C++23 25/25, with zero FAIL and
zero SKIP**. All 13 final suite cases returned zero.

This is the 32-bit x86 Gingerbread profile. ARMv7/API 10 remains the default;
the ARM64/x86_64 profiles retain API 21. No separate application source trees
were introduced.

## Installed SDK and provenance

| Item | Observed result |
| --- | --- |
| Qt / qmake | 5.15.19 / 3.1 |
| SDK prefix | /opt/qt5-android-x86-llvm |
| Installed target Qt libraries | 67 |
| Target DSOs including runtime/plugins | 198 |
| Loader checks | ELF32/i386, SysV DT_HASH, no native TLS or newer packed relocations |
| Compiler | Source-built upstream LLVM/Clang/LLD 21.1.8 |
| Guest | Android 2.3.7, API 10, x86 |
| CPU baseline | i686/SSSE3, no SSE4 or AVX in the captured guest |
| Native SDK producer | exit 0, no OOM |

Consumer image: `sha256:290ef7e959623083b7b7dc6e0bb9c0da2badf74ff0049db70c7ea2dbee886cf1`.

Compiler executable SHA256:
`6c31c191790134904d2b562c4fb82114e3d6540f0f860a253a05bd2d412c94c4`.

Final shared libc++/ABI/unwinder/compiler-rt SHA256:
`c253eff8207403db045f4980c07620f213e7e31427e9f2680c784570eee33489`.

QtCore SHA256:
`9f5e7b4f72925d4fc8ea4c5ce3d9604dce6c35ff62b4d3d586f32003604386d2`.
It is byte-identical to the original uninstrumented SDK library. Temporary
trace libraries were used only in the isolated diagnostic APK.

The runtime provenance records 813 effective headers, source archives,
compiler/helper/patch hashes, the classic locale profile and the shared
pthread-backed generic atomic implementation. All five generic __atomic_*
entry points are supplied by the one shared LLVM runtime, without a GNU/NDK
atomic library. Long double is 8 bytes with 53 mantissa bits on this ABI.

## Pinned platform inputs

- AOSP NDK r7 API 9 x86, prebuilt commit
  `968372cd8fffab51ff89c6b3cb40bc74ede24cb9`; SHA256
  `b439f09f897cda29bb7600308f5b928c4ba00407c1503f76d9c6482807e78b92`.
  NDK r7 has no separate native API 10 directory.
- Official Google x86 API 10 revision 5 image, 75,386,095 bytes; SHA1
  `a166d5ccbb165e1dd5464fbfeec30a61f77790d8` checked against Google's
  system-image metadata; SHA256
  `1c0ecc0c76e64aa011e9f3739ab72b41537f4f7c5ffde0d59da23e9939665666`.
  Its source.properties says 2.3.3, while build properties and the actual guest
  say 2.3.7. No Android 2.3.3 x86 runtime success is claimed.
- Upstream LLVM 21.1.8 archive; SHA256
  `4633a23617fa31a3ea51242586ea7fb1da7140e426bd62fc164261fe036aa142`.
- SDK Tools 24.4.1, Android 35 Java declarations, OpenSSL 3.5.7 and Qt 5.15.19
  use the existing locked hashes.

The fetcher selects inputs by ABI and phase. The common Dockerfile selects
the matching API 10 or API 21 runtime and installed SDK stages.

## Final emulator results

The authoritative run is `sdk-suite-3`. Every case starts a fresh
headless guest, checks its release/API/ABI, installs the matching APK and
captures stdout, native exit status and logcat. Boots took
19.1–24.3 seconds, with 0 boot-query timeouts.

| Case | PASS | FAIL | SKIP |
| --- | ---: | ---: | ---: |
| strict-cxx23 | 25 | 0 | 0 |
| qt-selftest | 209 | 0 | 63 |
| widgets-gallery | 90 | 0 | 5 |
| graphics-gallery | 32 | 0 | 0 |
| painting-lab | 16 | 0 | 0 |
| multimedia-lab | 4 | 0 | 0 |
| gl-heavy-gallery | 38 | 0 | 8 |
| quick-qml-gallery | 24 | 0 | 14 |
| network-gui | 7 | 0 | 0 |
| strict-cxx23-extended | 25 | 0 | 0 |
| qt-selftest-extended | 106 | 0 | 4 |
| widgets-gallery-render | 16 | 0 | 0 |
| quick-qml-gallery-render | 3 | 0 | 0 |

The ordinary SKIPs describe unavailable generation/platform/hardware paths.
They are separate from the mandatory modern-C++ runs, which both have no
SKIP. The emulator cannot create the ES 2 context required by Scene2D and
Data Visualization; the OpenGL gallery records those limits. QML uses Qt
Quick's software backend.

The Widgets contact sheet and QML first-frame PNG were also inspected:
both contain the expected rendered UI. This establishes emulator raster
rendering, not real-device GPU, camera, audio capture or sensor operation.

All nine current APKs were checked for x86-only native entries,
ELF32/machine 3 code, and the exact shared runtime SHA256 above. Their
min/target SDK is 10 and they use v1 signatures.

## Compatibility changes and retained failures

- The old headers lack PT_GNU_EH_FRAME and C11 static_assert. Narrow patches
  retain BSD-2-Clause and BSD-3-Clause respectively. Pointer format macros now
  match int/unsigned-int intptr_t/uintptr_t, preserving the ISC licence of the
  OpenBSD header. All eight header patches apply and recheck for clean ARM
  and x86 fixtures.
- The x86 DWARF unwinder uses Bionic's four-field program-header iterator.
  The [Android 2.3.7 linker declaration](https://android.googlesource.com/platform/bionic/+/android-2.3.7_r1/linker/linker.h)
  and [export](https://android.googlesource.com/platform/bionic/+/android-2.3.7_r1/linker/dlfcn.c)
  agree. Frame-header caching stays disabled: this old interface lacks
  add/remove counters and concurrent dynamic unloading during unwinding has
  not been qualified.
- Initial SDK configuration found missing x86 atexit glue. The shared legacy
  CRT now registers callbacks with a hidden per-DSO handle; ARM is unchanged.
  QtNetwork's atexit and __dso_handle are LOCAL/HIDDEN and absent from dynamic
  exports. A retry of failed Qt configuration uses -recheck so a cached
  negative dependency result does not survive a correction.
- The initial full suite passed strict C++23, but core selftest had four SQL
  failures. A diagnostic exposed the 96-DSO Bionic pool limit. The split
  profiles had limited calls while still compiling all translation units;
  MOC registration retained unused Sensors/NFC libraries. CMake now filters
  translation units owned only by the other profile, retaining mixed units
  in both. A coverage guard verifies all 74 called check functions remain,
  the source union is preserved and modern C++ stays in both profiles.
  The full/default desktop profile is unchanged.
- A second suite exposed a QProcess completion hang. A small probe and
  trace-only QtCore found the child correctly reaped but wait4 returning a
  negative address. The stock
  [x86 syscall implementation](https://android.googlesource.com/platform/bionic/+/android-2.3.7_r1/libc/arch-x86/bionic/syscall.S)
  restores the incoming EAX, losing the kernel return value. The API 10 x86
  runtime's wait4 adapter now calls Bionic's exported __wait4 stub directly;
  ARM retains its previous implementation. The fixed probe completed 8/8
  children with normal exit 7 while four worker threads were active.
  The shared process check now also requires actual completion and normal
  exit, not merely a marker file.

The SDK's 67 Qt binaries and compiler/runtime objects were retained for the
small runtime correction; they were not rebuilt from scratch. The refreshed
runtime and installed SDK passed the 198-DSO check again, then all examples
and APKs were rebuilt and the complete third suite ran successfully.

Earlier evidence remains separate: runtime-probe-1 (unsupported Conroe model
name in Tools 24), runtime-probe-2 (initial runtime 25/0/0), sdk-suite-1
(SQL/loader-pool failures), debug-sql-1 (verbose diagnostic timeout),
sdk-suite-2 (process completion timeout), and the isolated QProcess probes.
The legacy emulator uses its supported core2duo model with acceleration off.

## Boundaries and reproduction

The libc++ locale is C/POSIX, with wide-character and named Unicode locales
disabled; Qt's Unicode/QLocale data is separate. The stock x86 system's
generic syscall return bug is not globally replaced for arbitrary consumer
C calls. The adapter avoids it where needed by this runtime.

The existing SDK/examples/package/test phase entry point accepts -Abi x86.
It reuses an inspected immutable SDK image for examples and performs no
implicit SDK rebuild during packaging or tests. See the
[target guide](../targets/qt5-android-gingerbread.md) for commands.

Evidence is under `artifacts/qt5-android-gingerbread-x86`:
`sdk-suite-3/summary.json`, per-case logs/PNGs,
`runtime-input-provenance.json`, `sdk-api10-elf.json`,
`sdk-modules.txt` and `apk-native-abi-check.json`.
The normal phase-routing/coverage/syntax checks passed. Native builds and
guests ran serially with two build CPUs and 3 GiB RAM; emulator guests were
headless. No local security suites, push or new tag were run.


## Later timed-wait correction

The saved `sdk-suite-3` report above predates the targeted QtCore futex repair.
Strict C++23 passed there, but it did not exercise Qt's timed mutex/semaphore
wakeups with stale ETIMEDOUT. The [audit follow-up](android-audit-fixes-20261121.md)
records that reproduced defect, its x86-only repair and the refreshed shared
selftest. The older APK/SDK identities above remain historical evidence.
