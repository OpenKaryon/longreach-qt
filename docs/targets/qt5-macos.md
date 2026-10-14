# Qt 5.15.19 for macOS

| Target | Image | Floor | |
|--------|-------|-------|---|
| `make qt5-macos-amd64` | `qt5-macos-amd64-<profile>` | Mac OS X 10.6 Snow Leopard, x86_64 | osxcross, SDK 11.3, static libc++ 14 |
| `make qt5-macos-i386` | `qt5-macos-i386-<profile>` | Mac OS X 10.6, 32-bit Intel | the same, plus the i386 drivers |
| `make qt5-macos-arm64` | `qt5-macos-arm64-<profile>` | macOS 11.0, Apple silicon | osxcross, SDK 11.3 |

The SDK is fetched from Apple's software-update CDN (the package MacPorts
uses), checked by SHA256, unpacked in a container and never redistributed;
osxcross is pinned to a commit. Apple licenses its SDKs for use on Apple
hardware. `QT5_MACOS_TARGET_AMD64` selects a higher deployment target for the
x86_64 build (10.7 or 10.11, for example), which leaves out the static
OpenSSL and libc++ the oldest systems need.

## Down to 10.6

`patches/qt5/macos` lowers the deployment target in steps; each API newer
than the target is selected at run time with `@available`, and data symbols,
which a weak import leaves at address 0, are guarded or spelled out:

| Below | What changes on the older system |
|-------|----------------------------------|
| 10.12 | no os_activity scopes or unified logging (stderr instead); Metal features and file system fast paths chosen at run time |
| 10.11 | no Metal RHI; CoreText weights by number; Qt links a static OpenSSL 3.5.7 (10.7's SecureTransport stops at TLS 1.0); applications link with `-no_implicit_dylibs` (CFNetwork lives inside CoreServices on 10.7) |
| 10.9-10.7 | no App Nap; the gamepad, Bluetooth LE, multimedia and speech plugins check the system first |
| 10.7 | QtCore keeps thread data in a pthread key instead of `thread_local`; device pixel ratio 1; full screen emulated; no window restoration; wheel in notches; legacy OpenGL profile; legacy scrollers; no GSSAPI; CA certificates by trust setting; no camera or media player (AVFoundation is 10.7), audio works; no store in QtPurchasing; classic Bluetooth only; positions without course or speed |

10.6 has no libc++: the image builds libc++ and libc++abi from LLVM 14.0.6 for
`x86_64-apple-macosx10.6` and links them statically into every binary, which
then depends only on libSystem and the system frameworks.

## 32-bit Intel

The Core Duo and Core Solo Macs stop at 10.6.8. osxcross has no i386 for
SDKs newer than 10.13 and the 11.3 SDK's stubs have no i386 slice, so
`scripts/build/qt5-macos/build-i386-toolchain.sh` adds compiler drivers that
compile against a copy of the 11.3 SDK and link against the i386 libraries of
the 10.7 SDK (pinned), with its own libc++ for i386, a startup object and
compiler-rt's helpers. Two things differ on the 32-bit Objective-C runtime:

- it is the fragile runtime: a subclass's instance variables sit at offsets
  fixed by its superclass's declared ones, and AppKit's 11.3 headers declare
  none, so `i386/fragile-ivars.py` gives each class a placeholder of its 10.7
  size; and instance variables are allowed only in `@interface`, which
  patches 43-47 arrange for about 40 Qt classes;
- a message to a weak-linked class that is missing crashes instead of going
  to nil, so every such message sits behind `@available`.

Metal and gamepads are off on i386 (their frameworks have no 32-bit slice).
The binaries run on every Intel Mac up to 10.14.

## Results

amd64 and i386: 8/8 on Mac OS X 10.6.3, OS X 10.7.5 and macOS 10.13.6 in
VMware, 494, 496 and 496 checks, none failed; a 10.11 build earlier on real
OS X 10.11.6. arm64 is built and audited, not run
([platforms](../platforms.md#qt-51519)).

## Limits

- Real 10.6 hardware, a 32-bit-only Mac and Apple silicon have not run the
  builds.
- Separate native Qt Quick popup windows are disabled in the gallery (they
  render as grey native surfaces in a static build); their API checks run.
