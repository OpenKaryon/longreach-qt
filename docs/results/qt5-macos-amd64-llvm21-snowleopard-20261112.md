# Qt 5.15.19 with LLVM 21.1.8 on macOS amd64

The local build kept the 10.6 deployment target, QML JIT, Mapbox GL and
static OpenSSL 3.5.7. The resumed build reused the original Qt objects
after adding the LLVM compiler-rt availability helper for 10.6.

All 238 archive paths and 155 qmake module files matched the existing
amd64 SDK. All nine examples compiled in strict C++23 mode and passed
the x86_64 Mach-O audit at 10.6. Explicitly loading the static TLS archive
resolved the destructor registration in `qt-selftest`. The [JSON record](qt5-macos-amd64-llvm21-snowleopard-20261112.json)
contains the build references and SHA-256 hashes.

The strong libSystem imports of all nine examples were present in the
Mac OS X 10.6.3 installer libraries for the matching architecture.
The audit includes the math symbols re-exported by libSystem.
All 24 required dylib paths had the matching architecture and sufficient
compatibility versions in the installer or its Essentials package.

The required non-libSystem binding pairs are a subset of the previous
suite's pairs for every application. The baseline executable hashes
match the suite recorded as running on Snow Leopard in October.

The repository command `make qt5-macos-amd64-llvm-examples PARALLEL_JOBS=3`
rebuilt the SDK and nine strict C++23 examples in 41 minutes 59 seconds.
The archive paths, qmake module files and enabled and disabled features
match the baseline. The exported binaries matched the image and manifest,
and passed the Snow Leopard libSystem and dylib path audits.

The repository binaries ran in the Mac OS X 10.6.3 (10D2235) VMware guest.
All nine SHA-256 hashes matched the build manifest. The strict C++23
selftest reported 25 PASS, 0 FAIL and 0 SKIP. All seven GUI examples
passed with 228 checks passed, 0 failed and 23 optional skips.
