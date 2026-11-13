# Qt 5.15.19 Linux i386 SDK with LLVM 21.1.8 on Ubuntu 10.04

The local staged build installed a static GPL-enabled Qt SDK. Its 90
Qt archives matched the existing Linux i386 SDK, including both Qt Wayland
modules. The Mapbox GL plugin was installed, and qmake reported Qt 5.15.19.
The target uses the pinned Ubuntu 10.04 sysroot and a static LLVM runtime.

The Lucid compatibility changes use the C11 `_Static_assert` keyword in
compiler-rt and the existing `posix_memalign` fallback in libc++.
The Lucid i386 FreeType header drops the obsolete register specifier
while keeping the inline-assembly constraints.
QtQml's private x86 register enum has a signed underlying type for the
`-1` sentinel. Qt Location uses the existing Clang 21 Mapbox patch.

## Clean repository build

On November 12 UTC, `make qt5-linux-i386-llvm-examples PARALLEL_JOBS=4`
rebuilt the toolchain, SDK and nine executables. The extracted files passed
the ELF32 and glibc 2.10 audit and repeated the results below in a fresh
Lucid boot. The JSON records their hashes separately.

## Qt Quick 3D SDK parity

The follow-up build restored both asset importers and the `balsam` and
`meshdebug` tools. All 196 static archive paths, 42 tool paths, 162 qmake
module files and 324 qmake feature entries matched the previous SDK.
Both tools are i386 and require glibc symbols through 2.10.

Eight of the nine binaries are byte-identical to those tested on the
Lucid kernel, including the C++23 selftest and six GUI examples. The
full new suite also ran with Ubuntu 10.04 i386 userspace on the WSL2
host kernel. C++23 reported 25 PASS, 0 FAIL and 0 SKIP. The seven GUI
examples passed with 216 checks passed, 0 failed and 27 optional skips.
A fresh QEMU run on Ubuntu kernel 2.6.32-38 verified all nine binary
hashes. All 25 C++23 checks and seven GUI examples passed.
The rebuilt `quick-qml-gallery` reported 30 PASS, 0 FAIL and 13 optional skips.

## Runtime results

The binaries ran sequentially in QEMU system mode with Ubuntu's
`2.6.32-38-generic` kernel and Lucid userland packages. The guest reported
EGLIBC 2.11.1. The test initramfs used verified Lucid packages and seeded
the guest entropy pool from the host for the ordinary network example.

| Run | PASS | FAIL | SKIP |
|---|---:|---:|---:|
| Required C++23 | 25 | 0 | 0 |
| Seven GUI examples | 216 | 0 | 27 |

The ELF audit confirmed ELF32 i386, static Qt and LLVM C++ runtimes, and glibc
symbol requirements through 2.10. The manifest gate checked every
named C++23 behavior. The console used the offscreen platform. The GUI
apps used XCB with Debian 12 Xvfb outside the guest. Lucid's own Xvfb
crashed in this fixture, and GLX was disabled on the replacement server.
Those results cover the original kernel and Lucid client libraries.
OpenGL rendering and an installed VMware desktop are outside this run.

The [JSON record](qt5-linux-i386-llvm21-lucid-20261111.json) includes image IDs, binary and kernel package
hashes and individual results. For the repository build commands, see the
[Qt 5 Linux guide](../targets/qt5-linux.md#i386-with-llvm-2118).
