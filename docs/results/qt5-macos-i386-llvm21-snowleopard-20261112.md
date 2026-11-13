# Qt 5.15.19 with LLVM 21.1.8 on macOS i386

The local build produced the static Qt SDK and all nine ordinary examples.
It used Clang 21.1.8, static libc++ and libc++abi 21.1.8, the existing
osxcross cctools linker and the 10.7 i386 link SDK. Qt retained the
Mac OS X 10.6 deployment target, QML JIT, Mapbox GL and static OpenSSL 3.5.7.

All 238 installed static archive paths and all 155 qmake module files
matched the existing macOS i386 SDK. The audit confirmed nine thin i386
Mach-O executables with a 10.6 load command and system dynamic libraries.
The [JSON record](qt5-macos-i386-llvm21-snowleopard-20261112.json) contains
the BuildKit reference and executable hashes.

The patched Clang and pthread-based TLS runtime compiled and linked the
standalone set of 25 checks for i386 with a 10.6 deployment target. All
nine examples then compiled in strict C++23 mode against the local Qt SDK.
The Mach-O audit confirmed the same 10.6 target and resolved TLS runtime
symbols in `qt-selftest`. The JSON record includes both sets of hashes.

The repository command `make qt5-macos-i386-llvm-examples PARALLEL_JOBS=3`
rebuilt the SDK and strict examples using the shared macOS build script in
54 minutes 37 seconds. The audit matched all 238 baseline archives,
155 qmake module files and 310 qmake feature entries. It checked all
nine Mach-O headers and verified every exported binary against the
manifest and the Docker image.

The strong libSystem imports of all nine examples were present in the
Mac OS X 10.6.3 installer libraries for the matching architecture.
The audit includes the math symbols re-exported by libSystem.
All 24 required dylib paths had the matching architecture and sufficient
compatibility versions in the installer or its Essentials package.

The required non-libSystem binding pairs are a subset of the previous
suite's pairs for every application. The baseline executable hashes
match the suite recorded as running on Snow Leopard in October.

The repository binaries ran in the Mac OS X 10.6.3 (10D2235) VMware guest.
All nine SHA-256 hashes matched the build manifest. The strict C++23
selftest reported 25 PASS, 0 FAIL and 0 SKIP. All seven GUI examples
passed with 228 checks passed, 0 failed and 23 optional skips.
