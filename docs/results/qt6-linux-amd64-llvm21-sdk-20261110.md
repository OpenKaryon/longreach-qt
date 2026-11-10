# Qt 6 Linux amd64 SDK with upstream LLVM 21.1.8

On 2026-11-10 UTC, the complete configured static Qt 6.8.5 Linux amd64 SDK
was rebuilt with upstream Clang/LLD 21.1.8 and static libc++, libc++abi,
libunwind and compiler-rt. The local SDK image is `qt6-linux-amd64:llvm21`:

```text
sha256:653d1dacfbb6444837b35ff51f1b0a10ebf1d1f7139d78cea8823dd8fd9e174c
```

The [JSON record](qt6-linux-amd64-llvm21-sdk-20261110.json) contains image
identities, build timings, source/binary hashes, captured test output and
the Qt configuration. No LLVM-MinGW distribution or experimental-library
flag was used. The source recipe and wrappers are under
`docker/qt6/linux/amd64/Dockerfile-llvm` and
`scripts/build/qt6-linux-amd64/`; Docker directories contain only
Dockerfiles. The ordinary GCC make target and earlier images remain available.

## Build and runtime scope

The existing shared upstream compiler image was reused. Its locked-RPM
CentOS 7 base supplies patched Qt 6.8.5 source and the existing C dependencies.
The native LLVM runtimes were installed beside the compiler, then Qt was
compiled again into `/opt/qt6-linux-amd64-llvm`. The selected GPL-enabled
module profile excludes Qt WebEngine/WebView, matching the earlier pilot.
The installed library inventory and configure summary are in the JSON record.

The source archive pin remains
`4633a23617fa31a3ea51242586ea7fb1da7140e426bd62fc164261fe036aa142` for LLVM
21.1.8. Linux retains the explicit libc++abi weak-symbol TLS fallback for
glibc 2.17 found by the [earlier behavior probes](modern-cpp-behavior-20261110.md).
The installed wrappers were independently checked before building Qt; they
have no dependency on the work volume. LLVM sources were not patched.

Builds and checks ran sequentially, with four CPUs, an 8 GiB memory limit,
network disabled and a single Qt link pool. Qt build/install/image-save
took 81.57 minutes; SDK checks took 1.15
minutes. Both retained build containers exited zero without an OOM kill.
The Qt object volume is retained for incremental rebuilds. The SBOM,
configure summary and CMake cache were installed with the SDK.

## Required C++23 and ordinary Qt checks

| Run | PASS | FAIL | SKIP |
|---|---:|---:|---:|
| Installed upstream LLVM toolchain | 25 | 0 | 0 |
| QtCore consumer C++17 | 7 | 0 | 18 |
| QtCore consumer C++20 | 18 | 0 | 7 |
| QtCore consumer C++23 | 25 | 0 | 0 |
| qmake QtCore consumer C++23 | 25 | 0 | 0 |
| Qt console --modern-cpp C++23 | 25 | 0 | 0 |
| Ordinary Qt console --selftest C++23 | 308 | 0 | 38 |
| QtCore C++23 in stock CentOS 7.9.2009 | 25 | 0 | 0 |

All required C++23 runs passed the same exact 25-name manifest gate, with
zero FAIL/SKIP. This includes CMake and qmake QtCore consumers, the full
console target's `--modern-cpp` path and a separate execution of the QtCore
binary in stock CentOS 7.9.2009 without the compiler/SDK installed.
The required CMake compile commands are captured and contain no
`-fexperimental-library`. jthread, stop tokens, stop-aware waits, atomic
wait/notify, TLS destructors, exception unwinding, filesystem and Unicode
format/print all execute in ordinary libc++ 21.

The subsequent `qt-selftest --selftest` is the ordinary Qt API console run;
unavailable hardware/platform/module checks may SKIP there. Its modern C++
section must still pass every required check. C++17/20 builds retain guarded
SKIP for unavailable newer language/library features. The unchanged shared
header's C++14 compatibility was checked in the
[preceding Qt 4/GCC 5.4 run](modern-cpp-behavior-20261110.md).

Each consumer passed the GLIBC 2.17 symbol-floor audit and the screen for
shared C++/unwind/libgcc/LLVM runtime dependencies. The required C++23
consumer is an ELF64 x86_64 binary. The stock runtime check used the same
binary read-only, with no dependency copies, downloads or compiler image.

## Reproduction and evidence

See the [SDK guide](../targets/qt6-linux-llvm.md) for pinned prerequisites,
compiler wrappers and direct Dockerfile usage. The coordinator's default
sequence now includes mandatory validation:

```sh
python scripts/build/qt6-linux-amd64/build-sdk.py
python scripts/build/qt6-linux-amd64/build-sdk.py --stage checks
```

The second command repeats checks on the existing SDK. The coordinator
holds the common SDK lock, refuses a concurrent container and preserves
failed-run evidence. For qmake consumers, explicitly select `QMAKE_CC=$CC`,
`QMAKE_CXX=$CXX` and `QMAKE_LINK=$CXX`; the qmake validation uses those wrappers.

Raw logs are `build/qt6-linux-amd64-llvm21-{toolchain,qt,checks}.log`.
Programs, per-stage records, compile commands and runtime output remain in
`artifacts/tests-qt6-linux-amd64-llvm21/`. The JSON retains the start-time
build records separately from the final source fingerprints; an executed
coordinator snapshot is retained with the local artifacts. Control-plane
changes added automatic checks while the Qt build was running; the compiler
wrappers and actual Qt/runtime build helpers remained the tested inputs.

No security tests, Qt upstream test suites, GUI galleries or virtual
machines were launched. The ordinary console uses Xvfb/offscreen internally.
Containers verify the old userland on the current host kernel; minimum-kernel
and VM certification remain separate. Other Qt 6 SDK targets were not rebuilt
in this run. These checks cover the named behaviors, not complete C++23
conformance. No push or publication was performed.
