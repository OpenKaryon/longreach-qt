# Qt 5.15.19 with LLVM 21.1.8 on macOS arm64

The repository command built the static SDK and all nine strict C++23
examples in 39 minutes 11 seconds. It used Clang and static LLVM
runtimes from the existing arm64 toolchain, with Qt 5's osxcross and
macOS 11.3 SDK. The deployment target is macOS 11.0.

The audit matched all 238 static archive paths and 155 qmake module files
against the previous arm64 SDK. The enabled and disabled qmake features
also matched, including SecureTransport, Mapbox GL and disabled QML JIT.
All nine executables were thin arm64 Mach-O for macOS 11.0. Their hashes
matched the Make manifest and the extracted Docker image.
([JSON record](qt5-macos-arm64-llvm21-20261112.json))

Runtime verification is deferred. Running the examples and the 25 required
C++23 checks needs an Apple
silicon system or an arm64 macOS guest. Neither was available in this
run.

```sh
make qt5-macos-arm64-llvm-examples PARALLEL_JOBS=3
```
