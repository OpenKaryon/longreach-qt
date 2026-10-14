# Qt 4.8.7 for Mac OS X

| Target | Image | Floor | Notes |
|--------|-------|-------|-------|
| `make qt4-macos-i386` | `qt4-macos-i386` | Mac OS X 10.4 Tiger, Intel | Carbon; osxcross with the 10.4u SDK; clang, libstdc++ from GCC 5.5 |
| `make qt4-macos-ppc` | `qt4-macos-ppc` | Mac OS X 10.2 Jaguar, PowerPC | Carbon; GCC 5.5 for PowerPC with the 10.2.8 SDK as sysroot |

`make qt4-macos-i386-examples` and `make qt4-macos-ppc-examples` build the test
suite as application bundles and pack them as a tar.gz (unpack it on the Mac:
copying loose bundles through Windows loses the executable bits).

Qt 4.8.7 on the Mac is Carbon for 10.4 and Cocoa for 10.5; Longreach Qt builds
Carbon, the only one that reaches 10.4 and 10.2. Intel Macs start at 10.4.4, so
the Intel build stops at Tiger; PowerPC goes down to Jaguar, Qt 3.3's floor.

## How the PowerPC build is made

One Dockerfile, `docker/qt4/macos/ppc`, in stages:

1. osxcross (its `ppc-test` branch, pinned) builds cctools and ld64 for
   PowerPC with the 10.4u SDK;
2. GCC 5.5 for `powerpc-apple-darwin8` against 10.4u, with the classic
   cctools linker and a patch for Objective-C++ exceptions, and libstdc++;
3. a second GCC 5.5 whose sysroot is the 10.2.8 SDK: 10.2 has no wide
   characters, no `__cxa_atexit` and no `dlopen`, so the compiler is
   configured without them, libgcc gets its own `dlfcn.h`, and a placeholder
   `libSystemStubs.a` satisfies the driver; its probes run on 10.2;
4. OpenSSL 1.0.2u and Qt with the `macx-jaguar-g++` mkspec. Every 10.3 and
   10.4 API Qt uses is weak-linked and checked before use
   (`patches/qt4/macos` 12-17); the suite script checks each executable's
   imports against the 10.2.8 SDK and that no Qt object references a weak
   import without a check.

The same binaries run on 10.2 through 10.4 (and 10.5, and 10.6 under
Rosetta). G5 Macs run them as 32-bit; there is no ppc64 build.

## Results

- PowerPC (the Jaguar build), with the current eight-application suite:
  8/8 on Mac OS X 10.2 and 10.2.8 (361 checks each) and on Tiger 10.4.10
  (363), on an emulated G4 in QEMU.
- With the earlier 24-application layout: Tiger Intel 24/24 (524 checks) on
  Tiger 10.4.10 in QEMU; PowerPC 24/24 on the same three systems and on an
  emulated G3.

See [platforms](../platforms.md#qt-487). The Jaguar build is a target of its
own from 0.1.0 on; before, it was built by probe scripts.

## Limits

- Repeated cold boots of Tiger Intel in QEMU are unreliable (IOGraphics);
  that is the emulator, not Qt.
- Real Macs have not run either build yet.
- macOS 10.7 dropped PowerPC and 10.15 dropped 32-bit applications: the Intel
  build stops at 10.14, the PowerPC build at 10.6 (Rosetta).
