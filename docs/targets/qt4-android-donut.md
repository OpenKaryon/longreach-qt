# Experimental Qt 4.8.7 for Android 1.6

The Android profile builds diagnostic and example APKs for Android 1.6 (API 4,
`armeabi`). The native build runs in a Linux amd64 Docker container with
Clang and LLD 21.1.8. It builds static libc++, libc++abi, libunwind and
compiler-rt against the old Bionic sysroot. Qt uses separate QtCore and
Qt Quick 1 configurations. The latter displays Qt's raster output through
JNI and Android Canvas using the Qt minimal QPA plugin.

The additional [Android 5/API 21 x86_64 profile](qt4-android-lollipop.md)
has separate SDK, examples, packaging and test modes. API 4/armeabi remains
the default of the original build entry point.

## Inputs

On Windows, use Docker Desktop with Linux containers, PowerShell 7, a JDK
with `javac` and `keytool`, and the Android SDK with Build Tools 36.0.0 and
Platform Tools. The emulator runner also needs Python 3 for the shared
C++23 result validator.

Stage the Qt and LLVM source archives in `downloads/` using their existing
fetch rules:

```sh
make download-qt4 downloads/llvm-project-21.1.8.src.tar.xz
```

Stage these three archived Android inputs in `downloads/android-donut/`
or pass their directory as `-InputDirectory`.

| Input | Source |
| --- | --- |
| `aosp-ndk-r7-api4-arm.tar.gz` | [AOSP NDK r7 ARM API 4 sysroot archive](https://android.googlesource.com/platform/prebuilt/+archive/968372cd8fffab51ff89c6b3cb40bc74ede24cb9/ndk/android-ndk-r7/platforms/android-4/arch-arm.tar.gz) |
| `android-1.6_r03-linux.zip` | Android 1.6 revision 3 SDK archive containing `android.jar` and the ARM system image |
| `tools_r24.4.1-windows.zip` | Android SDK Tools 24.4.1 for Windows containing `emulator-arm.exe` |

The scripts check the archive hashes against the
[result report](../results/qt4-android-donut-armeabi-llvm21-20261116.md).
The Android SDK used for packaging can be selected with `ANDROID_HOME`
or `-AndroidSdk`.

## Build and run

From the repository root, run the build and emulator in order:

```powershell
./scripts/build/qt4-android.ps1
./scripts/run/qt4-android-donut.ps1
```

Both commands accept `-OutputDirectory`. The default is
`artifacts/qt4-android-donut/`. The build uses two jobs and a 3 GiB memory
limit. The Docker image installs the build tools, and the clean native
build then runs offline from the archives. Packaging uses a disposable
local signing key and v1 APK signing for API 4.

| APK | Check |
| --- | --- |
| `bootstrap.apk` | JNI library loads and returns 42 |
| `strict.apk` | The classic C locale and all 25 shared C++23 checks pass |
| `core.apk` | QtCore 4.8.7 UTF-8 strings and file I/O, application event loop and timer |
| `selftest.apk` | Shared Qt application checks, including files, threads, raster/fonts, XML, TCP/UDP loopback, SQLite and QtScript |
| `quick.apk` | Switch and lifecycle smoke checks, plus Qt Quick Gallery navigation and Widgets Gallery checkbox and tab input |
| `graphics.apk` | Graphics Gallery `--selftest`, including raster effects, widgets and animation |
| `network.apk` | Network GUI `--selftest`, including TCP listen and UDP bind |
| `painting.apk` | Painting Lab `--selftest`, including raster, fonts, SVG and print preview |

The runner boots one emulator per APK, verifies the guest's release, API
and ABI, and saves the guest reports and logcat under `run/<profile>/`.
Use `-Profiles quick` to rerun both gallery checks. Native libraries,
QtCore's static archive and ELF reports are under `native/`. Qt Quick
Gallery and Widgets Gallery each appear in the Android launcher after
installing `quick.apk`.
See the [example validation report](../results/qt4-android-donut-examples-20261117.md)
for platform limits and guest results.


## Shared compiler inputs

Android host tools build from the digest-pinned Ubuntu 22.04 image and the
project's dated apt snapshot. Clang/LLD 21.1.8 come from the SHA256-pinned
upstream LLVM source archive, with X86, ARM and AArch64 backends. The host
compiler builds with two jobs and one link job. The shared image is refreshed
through Docker's cache whenever SDK mode is requested; a pre-existing tag is
not a freshness check. Build its Dockerfile with the repository root as context.

These producer inputs describe the current recipe. Earlier result reports
identify the SDKs actually tested; changing the compiler recipe does not
retroactively qualify an older image as a fresh build from the new producer.
