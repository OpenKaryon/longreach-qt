# Compiler toolchains

The default target names below describe the compiler used for target Qt
libraries and applications. Tools that run during a cross-build can use
a separate host compiler.

| Qt | Targets | Compiler |
|---|---|---|
| 4 | All six targets | LLVM 21.1.8 and static libc++ |
| 5 | Linux, Windows XP and Intel macOS | LLVM 21.1.8 and static libc++ |
| 5 | `qt5-win-arm64` | Clang / LLVM-MinGW |
| 5 | `qt5-macos-arm64` | Clang via osxcross |
| 6 | Linux amd64/arm64, Windows amd64, macOS amd64 | LLVM 21.1.8 and static libc++ |
| 6 | `qt6-win-arm64` | Clang / LLVM-MinGW |
| 6 | `qt6-macos-arm64` | Clang via osxcross |

The [migration plan](releases/0.3.0-migration.md) tracks runtime validation.
The [target pages](targets/) document the OS floors, supported module
sets and build commands. The older compiler recipes are preserved at
`v0.2.2`.

The [Qt 6 Linux amd64 guide](targets/qt6-linux-llvm.md) covers the
standard LLVM recipe and the sequential coordinator. The shared
compiler is bootstrapped from the locked CentOS 7 inputs. Cross
targets can use separately built host tools and the target system's
headers and CRT.

The experimental Qt 4/5/6 Android SDK recipes also use upstream LLVM 21.1.8.
Their shared libc++ carries one exception/TLS state across all Qt/plugin
libraries. NDK platform inputs do not select the compiler or C++ runtime;
see the [Qt6 API21 guide](targets/qt6-android-lollipop.md).
