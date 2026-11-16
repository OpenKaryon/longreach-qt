# Qt 4.8.7 for Mac OS X

| Target | Image | Floor | Notes |
|--------|-------|-------|-------|
| `make qt4-macos-i386` | `qt4-macos-i386-llvm21` | Mac OS X 10.4 Tiger, Intel | Carbon, LLVM 21.1.8 and the 10.4u SDK |
| `make qt4-macos-ppc` | `qt4-macos-ppc-llvm21` | Mac OS X 10.2 Jaguar, PowerPC | Carbon, LLVM 21.1.8 and the 10.2.8 SDK |

`make qt4-macos-i386-examples` and `make qt4-macos-ppc-examples` build the test
suite as application bundles and pack them as a tar.gz (unpack it on the Mac:
copying loose bundles through Windows loses the executable bits).

Qt 4.8.7 on the Mac is Carbon for 10.4 and Cocoa for 10.5; Longreach Qt builds
Carbon, the only one that reaches 10.4 and 10.2. Intel Macs start at 10.4.4, so
the Intel build stops at Tiger; PowerPC goes down to Jaguar, Qt 3.3's floor.

## Tiger i386

The [Tiger Dockerfile](../../docker/qt4/macos/i386/Dockerfile) builds
osxcross from pinned sources and normalizes the 10.4u SDK. It builds
OpenSSL 1.0.2u with the osxcross Clang wrapper. Qt and the examples
use upstream LLVM 21.1.8 with patched libc++ and libc++abi. The
runtime and toolchain retain the 10.4u startup files, legacy linker
and SDK libgcc support.

Tiger shares the patched emulated TLS compiler with Qt 5 Snow
Leopard. To bootstrap the compiler image if missing, build the
compiler stage after the shared LLVM compiler is available:

```sh
make qt5-macos-snow-llvm-compiler
make qt4-macos-i386
make qt4-macos-i386-examples
make qt4-macos-i386-probe
```

Probe and example exports go to `artifacts/tests-qt4-macos-i386-llvm21`.
Run the strict bundle's `Contents/MacOS/qt-selftest --modern-cpp` in a
Tiger desktop session.

## Jaguar PowerPC

The [Jaguar Dockerfile](../../docker/qt4/macos/ppc/Dockerfile) builds
osxcross and Apple's classic linker, then the GCC 5.5 driver and CRT
with the 10.2.8 sysroot. GCC provides the link driver, ABI shims,
libgcc and the OpenSSL 1.0.2u build. Qt and the examples use the
patched PowerPC Darwin backend of LLVM 21.1.8, libc++, libc++abi and
compiler-rt emulated TLS. Mach-O import checks compare binaries
against the Jaguar SDK and check references to weak imports.

With the shared LLVM compiler image available:

```sh
make qt4-macos-ppc PARALLEL_JOBS=3
make qt4-macos-ppc-examples PARALLEL_JOBS=3
make qt4-macos-ppc-probe PARALLEL_JOBS=3
```

Probe and example exports go to `artifacts/tests-qt4-macos-ppc-llvm21`.
Run `qt-selftest-jaguar-strict --modern-cpp` from a logged-in
Jaguar desktop session. The SDK targets also accept the previous
LLVM trial command names.

## Migration validation

On Tiger 10.4.10 (8R3032, Core Duo in QEMU), the canonical SDK passed
all eight applications (366 checks, zero failures and 154 optional
skips). The strict selftest passed 25/25 C++23 checks with zero skips.
The guest verified both archives, and the Mach-O audit confirmed the
10.4 deployment target for all ten executables. See the
[Tiger migration record](../results/qt4-macos-tiger-llvm-migration-20261115.json).

On Jaguar 10.2 (6C115, PowerPC G3 in QEMU), the canonical SDK passed
all eight applications (363 checks, zero failures and 157 optional
skips). QtCore passed 16/16, QtGui 11/11, and both the standalone
C++23 probe and strict selftest passed 25/25 without skips. All 16
static libraries matched the trial inventory. The Mach-O checks found
zero missing imports across the probes, selftest and examples.
See the [Jaguar migration record](../results/qt4-macos-jaguar-llvm-migration-20261115.json).

## Previous LLVM validation

The LLVM trial SDKs passed all eight ordinary applications, the
standalone C++23 probe and the SDK-linked C++23 selftest in QEMU on
Tiger 10.4.10 and Jaguar 10.2. Each strict run passed 25/25 with zero
skips. The [Tiger report](../results/qt4-macos-i386-tiger-llvm21-20261113.md)
records the widget style fix and Mach-O audit. The
[Jaguar report](../results/qt4-macos-ppc-jaguar-llvm21-20261114.md)
also records QtCore 16/16, QtGui 11/11 and the inventory of 16 static
Qt libraries.

## Limits

- Repeated cold boots of Tiger Intel in QEMU are unreliable (IOGraphics);
  that is the emulator, not Qt.
- Real Macs have not run either build yet.
- macOS 10.7 dropped PowerPC and 10.15 dropped 32-bit applications: the Intel
  build stops at 10.14, the PowerPC build at 10.6 (Rosetta).
