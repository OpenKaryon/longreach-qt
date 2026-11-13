# Qt 5.15.19 Linux amd64 SDK with LLVM 21.1.8 on Ubuntu 10.04

The local staged build installed a static GPL-enabled Qt SDK. Its 90
Qt archives matched the existing Linux amd64 SDK, including both Qt Wayland
modules. The Mapbox GL plugin was installed, and qmake reported Qt 5.15.19.
The target uses the pinned Ubuntu 10.04 sysroot and a static LLVM runtime.

The Lucid compatibility changes use the C11 `_Static_assert` keyword in
compiler-rt and the existing `posix_memalign` fallback in libc++.
QtQml's private x86 register enum has a signed underlying type for the
`-1` sentinel. Qt Location uses the existing Clang 21 Mapbox patch.

## Clean repository build

`make qt5-linux-amd64-llvm-examples PARALLEL_JOBS=4` rebuilt the toolchain,
SDK and all nine binaries from the repository recipe. The extracted
artifacts passed the same ELF audit and repeated the results below in
the Lucid guest. The JSON records their hashes separately.

## Qt Quick 3D SDK parity

The follow-up build restored the two Qt Quick 3D asset importer plugins
and the `balsam` and `meshdebug` tools. The audit matched all 196 static
archive paths, 42 tool paths, 162 qmake module files and 324 qmake
feature entries from the previous SDK. Both tools are x86-64 and
require glibc symbols through 2.10.

Eight extracted binaries are byte-identical to the repository build
run on the Lucid kernel, including the C++23 selftest, the runner and
six GUI examples. The rebuilt `quick-qml-gallery` retained the same 14 ELF
library dependencies. All 14 added strong imports are present in Lucid's
libc and libm with the required symbol version. The rebuilt example ran
with Ubuntu 10.04 amd64 userspace under QEMU user mode on the WSL2 host
kernel and reported 30 PASS, 0 FAIL and 13 optional skips. On Ubuntu kernel 2.6.32-38 in QEMU,
all 25 C++23 checks and six GUI examples passed. The rebuilt
`quick-qml-gallery` reported 29 PASS, 1 FAIL and 13 optional skips.
`qml/visual-files-compile` could not load the static Fusion style plugin
`qtquickcontrols2fusionstyleplugin` while resolving `VerticalHeaderView`.

Four subsequent boots on the same kernel with the same nine SHA-256
verified binaries each passed all seven GUI examples and all 25 strict
C++23 checks. Quick/QML reported 30 PASS, 0 FAIL and 13 optional skips
on each retry. The initial Fusion load failure remains unexplained.

A separate boot on the same kernel ran the same Quick/QML binary 20 times
with `QML_IMPORT_TRACE=1`. All 20 invocations passed. The trace recorded
the `QtQuick.Controls.Fusion` library import and successful compilation
of the visual QML files.

## Runtime results

The binaries ran sequentially in QEMU system mode with Ubuntu's
`2.6.32-38-generic` kernel and Lucid userland packages. The guest reported
EGLIBC 2.11.1. The test initramfs used verified Lucid packages and seeded
the guest entropy pool from the host for the ordinary network example.

| Run | PASS | FAIL | SKIP |
|---|---:|---:|---:|
| Required C++23 | 25 | 0 | 0 |
| Seven GUI examples | 216 | 0 | 27 |

The ELF audit confirmed x86-64, static Qt and LLVM C++ runtimes, and glibc
symbol requirements through 2.10. The manifest gate checked every
named C++23 behavior. The console used the offscreen platform. The GUI
apps used XCB with Debian 12 Xvfb outside the guest. Lucid's own Xvfb
crashed in this fixture, and GLX was disabled on the replacement server.
Those results cover the original kernel and Lucid client libraries.
OpenGL rendering and an installed VMware desktop are outside this run.

The [JSON record](qt5-linux-amd64-llvm21-lucid-20261111.json) includes image IDs, binary and kernel package
hashes and individual results. For the repository build commands, see the
[Qt 5 Linux guide](../targets/qt5-linux.md#amd64-with-llvm-2118).
