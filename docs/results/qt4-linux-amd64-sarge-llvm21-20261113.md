# Qt 4.8.7 Linux amd64 with LLVM 21.1.8 on Debian Sarge

The static SDK uses Clang 21.1.8 and the upstream LLVM C++ runtime with
the pinned Debian Sarge amd64 port sysroot and OpenSSL 1.0.2u. All 35
static library, plugin and import archive paths match the existing SDK.

QEMU booted the pinned `2.6.8-12-amd64-generic` kernel with the Sarge
amd64 glibc 2.3.2 userland. An explicit low-memory map and 32-bit physical
address width let the original kernel set up its page tables under QEMU.
The GUI suite used Sarge's Xvfb.

The repository's standalone probe target rebuilt the executable and
passed all 25 cases in QEMU. The rebuilt probe has its own SHA-256,
a `GLIBC_2.3.2` ceiling and dependencies resolved by Sarge's loader.
A subsequent run of the existing SDK package passed all eight
ordinary apps and all 25 strict C++23 cases again.

| Run | Result |
|---|---|
| Standalone C++23 probe | 25 PASS, 0 FAIL, 0 SKIP |
| Ordinary Qt suite | 8/8 applications, including seven GUI examples |
| Qt strict C++23 selftest | 25 PASS, 0 FAIL, 0 SKIP |
| ELF audit | 10 ELF64 amd64 binaries, maximum `GLIBC_2.3.2`, dependencies resolved by Sarge's loader |

The locale-aware integer conversions use the glibc aliases exported
at `GLIBC_2.2.5`. The public names in this sysroot require
`GLIBC_2.3.3`. As on i386, QtScript runs through the interpreter, Qt
painting SIMD paths are disabled and the widget style helper is
compiled without optimization. GNU ld links the Sarge archives.

The repository build used a local Debian 12 host tools image. The
results cover the emulated Sarge kernel and Xvfb, with hardware
acceleration outside the test scope. The [JSON record](qt4-linux-amd64-sarge-llvm21-20261113.json)
includes executable hashes and individual test counts. See the
[build instructions](../targets/qt4-linux.md#amd64-with-llvm-2118).
