# Qt 4.8.7 for Android API 10 x86

The [make and build-all interface](../android-build.md) provides SDK and ready-APK
`-examples` targets. The individual PowerShell phases below remain available;
use the Android runners to launch saved APKs.

This additional profile uses upstream LLVM 21.1.8 and libc++ for Android
2.3/API 10, x86. The original [Android 1.6/armeabi](qt4-android-donut.md)
profile remains the default. The shared [API 21 guide](qt4-android-lollipop.md)
describes the same installed SDK, twelve JNI clients and phase contracts.

## Build and run

Use Docker Desktop Linux containers, PowerShell 7, Python 3.11+, JDK 17/21,
Android SDK platform 35, Build Tools 36.0.0 and Platform Tools. Set ANDROID_HOME.
Run these commands sequentially:

```powershell
./scripts/build/qt4-android.ps1 -Abi x86 -Mode sdk
./scripts/build/qt4-android.ps1 -Abi x86 -Mode examples
./scripts/build/qt4-android.ps1 -Abi x86 -Mode package
./scripts/build/qt4-android.ps1 -Abi x86 -Mode test -RunName sdk-suite
```

Only explicit SDK mode builds Qt. Examples consume a validated immutable image;
package and test modes use the saved outputs. Default image is
`longreach-qt4-android-gingerbread-x86:llvm21`, prefix
`/opt/qt4-android-x86-llvm`, output
`artifacts/qt4-android-gingerbread-x86/`. The installed toolchain supports
qmake and externally managed CMake clients. A new run name preserves old evidence.

## Platform and limitations

The Dockerfile selects the shared API 10 LLVM runtime producer and a pinned
NDK r7 API 9 x86 sysroot. Headers, CRT and link stubs come from the NDK; its
compiler and C++ runtime are not used. No Qt 5 framework is required by the
Qt 4 recipe. The input fetcher downloads only the selected platform inputs,
Qt 4 and LLVM source archives. Qt sources retain GNU++98; JNI clients use
GNU++23 with `-fexperimental-library`.

The selected static SDK has fourteen modules, the minimal/SVG plugins and
four Qt Quick 1 labs imports. Every target archive member must be ELF32/machine 3.
Final images contain installed libraries, headers, host tools, licenses and
producer metadata, with source/object trees excluded.

The pinned Google x86 r05 guest reports Android 2.3.7/API 10. The runner uses
Tools 24.4.1's legacy emulator, software CPU emulation, host GLES translation,
256 MiB RAM and no
visible window or host input capture. Run builds and guests sequentially.
The strict C++23 case requires all canonical 25 checks with zero failures and
zero skips. Ordinary example skips describe their platform/Qt API limits.

Widgets and Qt Quick 1 reuse the existing raster/Android Canvas bridge and
shared application sources; there is no QtActivity backend. WebKit, Phonon,
OpenSSL, D-Bus and ICU are disabled. The SDK includes QtMultimedia value types
and offscreen OpenGL support, but does not claim Android audio-device or
native onscreen GL integration. The API 10 runtime retains the qualified
x86 wait4 adapter; the stock generic Bionic syscall defect is not globally
wrapped for arbitrary consumer code.

See the [measured results](../results/qt4-android-gingerbread-x86-llvm21-20261121.md)
for the exact guest cases and further limits.


See [Android artifact generations and coverage](android-artifacts.md) for phase
ownership, packaging receipts, ABI preflight, per-target coverage limits and
the private ADB environment used in local reproduction.

The shared Qt 4 SDK/client cache rules are described in the
[API21 guide](qt4-android-lollipop.md#runtime-and-modules). API10 uses its own
ABI-specific BuildKit cache and per-output client volume; archive-only changes
relink without recompiling unchanged client objects.
