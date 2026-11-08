# Compiler toolchains

The default target names below describe the compiler used for target Qt
libraries and applications. Tools that run during a cross-build can use
a separate host compiler.

| Qt | Targets | Compiler |
|---|---|---|
| 4 | `qt4-win-i386`, `qt4-win-amd64` | GCC / MinGW-w64 |
| 4 | `qt4-linux-i386`, `qt4-linux-amd64` | GCC |
| 4 | `qt4-macos-i386` | Clang via osxcross, GNU libstdc++ |
| 4 | `qt4-macos-ppc` | GCC |
| 5 | `qt5-win-i386`, `qt5-win-amd64` | GCC / MinGW-w64 |
| 5 | `qt5-win-arm64` | Clang / LLVM-MinGW |
| 5 | `qt5-linux-i386`, `qt5-linux-amd64`, `qt5-linux-arm64` | GCC |
| 5 | `qt5-macos-i386`, `qt5-macos-amd64`, `qt5-macos-arm64` | Clang via osxcross |
| 6 | `qt6-win-amd64`, `qt6-win-arm64` | Clang / LLVM-MinGW |
| 6 | `qt6-linux-amd64`, `qt6-linux-arm64` | GCC |
| 6 | `qt6-macos-amd64`, `qt6-macos-arm64` | Clang via osxcross |

Nine of the 21 target builds use Clang and twelve use GCC. The separate
`qt6-host` image uses GCC on Debian 12.

Clang's presence alone does not specify the C++ library or its language
coverage. For example, Qt 4 macOS i386 uses Clang with GNU libstdc++,
while Qt 5 macOS Intel carries its own static libc++ for Snow Leopard.
See the individual [target pages](targets/) for runtime and OS limits.

## Linux amd64 LLVM experiment

An [experimental Qt 6 recipe](../docker/qt6/linux/amd64/Dockerfile-llvm)
rebuilds Qt with Clang/LLD 19.1.6 and static libc++ runtimes on CentOS 7.
The [pilot instructions](targets/qt6-linux-llvm.md) describe the build and tests.
It uses a separate SDK prefix and local image tag. It is not included in
the default target counts above and does not replace their GCC builds.

The [pilot results](results/qt6-linux-amd64-llvm-20261108.md) record the
C++23 suite and runtime-only CentOS 7 / Debian 13 checks.
