# Qt 5.15.19 for Windows

| Target | Image | Floor | Toolchain |
|--------|-------|-------|-----------|
| `make qt5-win-i386` | `qt5-win-i386-<profile>` | Windows XP SP3 | MinGW-w64 GCC 7.3, runtime v5 (Ubuntu 18.04) |
| `make qt5-win-amd64` | `qt5-win-amd64-<profile>` | Windows XP x64 SP2 | same |
| `make qt5-win-arm64` | `qt5-win-arm64-<profile>` | Windows 10 on ARM | LLVM-MinGW 20241217 (UCRT, clang 19) |

`make qt5-extract-tests QT5_IMAGE=qt5-win-i386-gpl-enabled` copies the test suite
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

## Results

8/8 (478 checks) on Windows XP SP3 in VMware with the i386 build; the XP
backport was first validated on real XP hardware. The arm64 build is checked
by building only ([platforms](../platforms.md#qt-51519)).

## Limits

- On XP, QtDataVisualization's Surface view stays a placeholder when the
  OpenGL driver lacks the features it needs (Bars and Scatter work), and
  separate native Qt Quick windows are disabled in the gallery where they
  destabilise the old WGL path; their API checks still run.
- No QtWebEngine on any target.
