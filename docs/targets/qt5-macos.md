# Qt 5.15.19 for macOS

| Target | Image | Floor | |
|--------|-------|-------|---|
| `make qt5-macos-amd64` | `qt5-macos-amd64` | Mac OS X 10.6 Snow Leopard, x86_64 | osxcross, SDK 11.3, static libc++ 14 |
| `make qt5-macos-i386` | `qt5-macos-i386` | Mac OS X 10.6, 32-bit Intel | the same, plus the i386 drivers |
| `make qt5-macos-arm64` | `qt5-macos-arm64` | macOS 11.0, Apple silicon | osxcross, SDK 11.3 |

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

### LLVM 21.1.8 on i386

Clang 21.1.8 compiled a C++23 language probe for Snow Leopard. The
existing cctools linker produced a 32-bit Mach-O with a 10.6 deployment
target. The LLVM Mach-O linker rejects `-arch i386`, so this build still
needs cctools.

The static libc++ and libc++abi 21.1.8 probe builds against the 10.7 SDK
with the 10.6 deployment target. It uses the older Darwin clock APIs
and libc++'s directory-iterator fallback for `std::filesystem::remove_all`
([libc++ patch](../../patches/llvm/macos-snow-leopard/01-legacy-darwin-filesystem-and-clocks.patch)).
The stock compiler rejects `thread_local` below macOS 10.7 even with
`-femulated-tls`. On a 10.7 diagnostic target it emitted emulated storage
access but called `_tlv_atexit` for destructors. The LLVM profile enables
emulated TLS for x86 at the 10.6 deployment target and uses a pthread-based
runtime to register destructors. The standalone probe and all nine strict
C++23 examples compiled and linked. The Snow Leopard 10.6.3 guest passed
all 25 C++23 checks and seven GUI examples.
([Clang patch](../../patches/llvm/macos-snow-leopard/02-clang-emulated-tls.patch),
[TLS runtime patch](../../patches/llvm/macos-snow-leopard/03-runtime-emulated-tls.patch))

The initial full build reached Qt Declarative. Clang 21 rejected the
QML JIT's `NoRegister` initializer because it converted `-1` to a register
enum outside its representable range. The successful Qt Declarative retry
made that value representable. The current build reuses the signed enum
patch already used by the other LLVM x86 profiles.
([QML patch](../../patches/qt5/linux-lucid-llvm/01-qml-x86-register-enum.patch))

The next build reached QtScript, where JavaScriptCore's Darwin `ceil`
macro renamed symbols in libc++ 21 headers. The current retry uses an
explicit JavaScriptCore helper and retains the signed-zero workaround.
([QtScript patch](../../patches/qt5/macos-llvm/01-qtscript-use-ceil-helper.patch))

The QtScript retry passed that error and reached Qt Location. The bundled
Mapbox GL failed in its RapidJSON and Boost headers under Clang 21. The
next build reuses the Clang 21 patch from the Linux arm64 profile with
Mapbox GL enabled.
([Mapbox GL patch](../../patches/qt5/linux-arm64-llvm/02-mapbox-clang21.patch))

Build the SDK and strict C++23 examples from the repository with the local
`qt5-macos-i386:latest` platform image and the shared upstream LLVM
21.1.8 compiler image.

```sh
make qt5-macos-i386-llvm-examples PARALLEL_JOBS=3
```

The repository command rebuilt the SDK and strict examples. The exported binaries passed the artifact audit.

The resulting SDK and nine ordinary examples passed the artifact audit.
([build result](../results/qt5-macos-i386-llvm21-snowleopard-20261112.md))

### LLVM 21.1.8 on amd64

The standalone set of 25 C++23 checks compiled and linked as x86_64
Mach-O with the 10.6 deployment target. The static libc++ and libc++abi
build uses the 10.7 SDK headers and the same emulated TLS patches as
i386. The Qt profile uses the existing 11.3 SDK for application
headers and linking. Qt configuration retains QML JIT, Mapbox GL and
static OpenSSL 3.5.7.

```sh
make qt5-macos-amd64-llvm-examples PARALLEL_JOBS=3
```

The repository build and all nine strict C++23 examples passed the artifact audit. The archive paths, qmake modules and qmake features match the baseline. The Snow Leopard 10.6.3 guest passed all 25 C++23 checks and seven GUI examples. ([build result](../results/qt5-macos-amd64-llvm21-snowleopard-20261112.md))

The first full prototype reached the Qt Declarative tools and failed to
link `__isPlatformVersionAtLeast`. The repository profile builds that
compiler-rt helper against the 10.7 SDK for the 10.6 target. A standalone
`@available` probe linked with the helper. Explicitly loading the static TLS archive resolved destructor registration in the audited examples.

## Limits

- Real 10.6 hardware, a 32-bit-only Mac and Apple silicon have not run the
  builds.
- Separate native Qt Quick popup windows are disabled in the gallery (they
  render as grey native surfaces in a static build); their API checks run.
