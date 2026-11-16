# Qt 5.15.19 for Windows

| Target | Image | Floor | Toolchain |
|--------|-------|-------|-----------|
| `make qt5-win-i386` | `qt5-win-i386-llvm21` | Windows XP SP3 | Clang 21.1.8, MinGW-w64 v5 CRT |
| `make qt5-win-amd64` | `qt5-win-amd64-llvm21` | Windows XP x64 SP2 | same |
| `make qt5-win-arm64` | `qt5-win-arm64` | Windows 10 on ARM | LLVM-MinGW 20241217 (UCRT, clang 19) |

`make qt5-win-i386-examples` copies the test suite
built in the image to `artifacts/tests-<image>/`.

## Windows XP

`patches/qt5/windows` 05-17 lower Qt to the XP API level and resolve every
Vista and Windows 7 API Qt calls at run time: the file dialog (IFileDialog on
Vista and later, the legacy dialog on XP), touch (WM_TOUCH from Windows 7),
the tray icon (NOTIFYICON v4 or the v3 callbacks), DPI, DWM, the Vista style,
`GetTickCount64`, `CancelIoEx`, interface enumeration without the LUID APIs,
QProcess pipes, QCollator's numeric mode. One binary runs on XP through
Windows 11 and takes the modern path on the newer systems.

The toolchain is chosen for XP too: MinGW-w64 runtime v5 (newer runtimes
import Vista-only CRT functions), OpenSSL 3.5.7 built with `no-async` and
`_WIN32_WINNT=0x0501` (no fiber APIs), desktop OpenGL (`-opengl desktop`;
ANGLE's D3D11 path does not exist on XP), and `-static-runtime`, so
applications need no MinGW DLLs.

The arm64 target applies the same patches; on Windows 10 every runtime check
finds the newer API. It uses Schannel instead of OpenSSL and disables Qt
Quick's D3D12 backend (its shaders need Microsoft's `fxc`) and the MapboxGL
geoservices plugin (clang 19 rejects the boost and rapidjson it vendors).

## i386 with LLVM 21.1.8

The [shared XP Dockerfile](../../docker/qt5/windows/Dockerfile) uses
upstream Clang, LLD, compiler-rt and libc++. It takes
the MinGW-w64 v5 XP sysroot from pinned Ubuntu 18.04 packages and builds
static OpenSSL from the pinned source archive. Prepare
`longreach-llvm:21.1.8-compiler` using the
[LLVM compiler instructions](qt5-linux.md#amd64-with-llvm-2118), then run
one build at a time.

```sh
make qt5-win-i386-examples PARALLEL_JOBS=4
```

`make qt5-win-i386` builds the SDK alone. The SDK installs to
`/opt/qt5-win-i386-llvm` in `qt5-win-i386-llvm21`. The examples go to
`artifacts/tests-qt5-win-i386-llvm21/`. The validated deployment on XP SP3
places the 32-bit Visual C++ 2010 CRT (`msvcr100.dll`) alongside the
executables. The build image and extracted suite contain the import
library and the executables, respectively. Supply the runtime on the
guest when running the tests.

The [build and run record](../results/qt5-win-i386-llvm21-xp-probe-20261112.md)
describes the C++23 and GUI results and the experimental filesystem limits.


## amd64 with LLVM 21.1.8

The amd64 profile shares the XP recipe and uses the 64-bit MinGW-w64 v5
sysroot and static OpenSSL build for AMD64. The example binaries
target subsystem 5.2 and use the 64-bit Visual C++ 2010 CRT beside the
executable.

```sh
make qt5-win-amd64-examples PARALLEL_JOBS=3
```

Use `make qt5-win-amd64` for the SDK alone. Both targets use
`qt5-win-amd64-llvm21`, with the SDK in `/opt/qt5-win-amd64-llvm`.
The [build and run record](../results/qt5-win-amd64-llvm21-xp-20261112.md)
documents the runtime results on Windows 7, Windows 11 and Windows XP x64 SP2.
XP x64 SP2 passed all 25 required C++23 checks without skips and all eight
ordinary applications. The guest's OpenGL 1.1 driver skipped the Qt 5 scene
graph renderer check because it lacks the required graphics features.

The [AMD64 migration record](../results/qt5-win-amd64-llvm-migration-20261115.json)
records the fresh SDK and repeat guest run, including the PE 5.2
audit, both QtScript regressions and the strict C++23 results.

## arm64 with LLVM 21.1.8

Stage `qt6-win-arm64:llvm21-toolchain` as described in the
[Windows ARM64 toolchain build](../results/qt6-windows-arm64-llvm21-sdk-20261111.md#reproduce).

```sh
make qt5-win-arm64-llvm-examples PARALLEL_JOBS=3
```

`make qt5-win-arm64-llvm` builds the SDK alone. Both targets use `qt5-win-arm64:llvm21`
and install Qt to `/opt/qt5-win-arm64-llvm`. The Qt 5 ARM64 build retains Schannel
and its existing module set. The
[build record](../results/qt5-win-arm64-llvm21-20261112.md) lists the
compiled examples and the deferred Windows on ARM runtime checks.

## Results

The rebuilt i386 LLVM SDK passed all eight ordinary applications on Windows
XP SP3 in VMware, with 503 checks passed and 97 optional checks skipped.
The separate C++23 run passed all 25 required checks with zero skips. The
[migration record](../results/qt5-win-i386-llvm-migration-20261115.json)
includes executable hashes and per-application results. Windows ARM64
runtime validation remains deferred.

## Limits

- On XP, QtDataVisualization's Surface view stays a placeholder when the
  OpenGL driver lacks the features it needs (Bars and Scatter work), and
  separate native Qt Quick windows are disabled in the gallery where they
  destabilise the old WGL path; their API checks still run.
- No QtWebEngine on any target.
