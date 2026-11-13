# Qt 4.8.7 Linux i386 with LLVM 21.1.8 on Debian Sarge

The static SDK uses Clang 21.1.8 and the upstream LLVM C++ runtime built
against the pinned Sarge i386 sysroot. The profile keeps QtGui, QtNetwork,
QtSql with SQLite, QtXml, QtXmlPatterns, QtScript, QtScriptTools,
QtDeclarative, QtMultimedia, QtOpenGL, QtSvg, Qt3Support and QtUiTools.
It uses the existing Sarge OpenSSL 1.0.2u archives. Host qmake 2.01a
builds i386 applications against the installed SDK. All 35 static library,
plugin and import archive paths matched the existing Sarge SDK.

The repository build used the local Debian 12 tools image via
`QT4_SARGE_LLVM_HOST=qt5-linux-i386:llvm21-lucid-probe-inputs`.
The [JSON record](qt4-linux-i386-sarge-llvm21-20261113.json) contains the
image ID, binary hashes, ELF requirements and individual results.

## Runtime and ELF checks

The guest uses Debian 3.1 Sarge userland, glibc 2.3.2 and the Debian
`2.6.8-4-386` kernel in QEMU TCG. It emulates a Pentium III and uses
Sarge's Xvfb for the GUI checks. The standalone compiler probe also passed
all 25 checks on the same CPU and kernel before QtCore and the full SDK
were built.

| Run | Result |
|---|---|
| Ordinary suite | 8/8 applications, including all seven GUI examples |
| Strict C++23 qt-selftest | 25 PASS, 0 FAIL, 0 SKIP |
| ELF audit | 10 ELF32 i386 binaries, maximum `GLIBC_2.3.2`, dependencies resolved by Sarge's loader |

The strict selftest reported `__cplusplus=202302` and libc++ 21.1.8.
The ordinary suite retains skips for checks that need unavailable
backends or features. The ELF audit covers the nine ordinary executables,
including the runner, plus the strict selftest.

## Compatibility limits

- The verified CPU floor is Pentium III. An earlier build with Clang's
  default i686 code generation hit an illegal instruction in atomic
  wait/notify on that CPU. The profile selects `-march=pentium3` and
  omits compiler-rt conversions for unsupported half-precision types.
- libc++ uses its timed-backoff implementation for atomic wait on the
  2.6.8 kernel and its directory-iterator implementation of
  `std::filesystem::remove_all` on glibc 2.3.2. GNU ld supports the old
  glibc archive's linkonce sections.
- The Qt 4 painting SIMD paths are disabled for this CPU. The build
  disables optimization for `QWidgetPrivate::setStyle_helper` after
  reproducing crashes in the optimized function. QtScript and QML use
  the JavaScriptCore interpreter after the JIT crashed in the first
  floating-point script check.
- The runtime evidence covers Sarge under QEMU with Xvfb. It does not
  establish behavior on a physical machine or with hardware acceleration.

See the [build instructions](../targets/qt4-linux.md#i386-with-llvm-2118).
