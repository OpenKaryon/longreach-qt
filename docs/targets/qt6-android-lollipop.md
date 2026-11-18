# Qt 6.8.5 for Android API 21

This experimental SDK targets ARMv7 `armeabi-v7a` from Android 5/API21.
Qt and applications use upstream LLVM 21.1.8 and one shared libc++ built
from the matching LLVM sources. NDK r27 supplies platform headers, CRT,
link stubs and Android helper sources; its compiler and libc++ are not used.
Runtime verification uses the archived Android 5.0.2/LSY66K API21 image.

## Build and run

On Windows, install Docker Desktop, Python 3.11+, PowerShell, JDK17 or JDK21 with
`javac`/`keytool`, and Android SDK platform 35, Build Tools 36.0.0 and Platform
Tools. Select the Android SDK through `ANDROID_HOME` or `-AndroidSdk`.
First build the native host-tools SDK with `make qt6-linux-amd64`; it is a
separate sequential prerequisite, not an Android runtime dependency.

```powershell
./scripts/build/qt6-android.ps1 -AndroidSdk $env:ANDROID_HOME
./scripts/run/qt6-android-suite.ps1 -AndroidSdk $env:ANDROID_HOME -RunName sdk-suite-1
```

The build wrapper fetches and verifies the inputs in
`scripts/fetch/locks/qt6-android-api21-inputs.json`, builds
`docker/qt6/android/Dockerfile`, then compiles/deploys the same eight `tests/`
applications and packages APKs. No application source fork is required.
`-SdkOnly` stops after the SDK image. `-HostImage` selects another already
built Qt6.8.5 host image. The default is `qt6-linux-amd64-llvm21:latest`.

The image is `longreach-qt6-android-lollipop:llvm21`; its SDK prefix is
`/opt/qt6-android-armeabi-v7a-llvm`, and its external CMake toolchain is
`/opt/longreach-android-api21/toolchain.cmake`. The final image includes the
compiler, runtime, host tools, target SDK, OpenSSL and Android build inputs.
The runtime, OpenSSL and Qt compilation stages run without network access.
Only provisioning the shared tools stage and fetching pinned inputs need it.
Only Dockerfile lives in `docker/qt6/android/`; helpers are under `scripts/`.

Outputs default to `artifacts/qt6-android-lollipop/`; pass `-OutputDirectory`
to both wrappers to select another location. `deployment/` holds Qt-generated
dependency/QML staging; `sdk-packaging/` holds Java packaging files; `apk/`
contains locally signed v1 APKs and their SHA256 manifest. Packaging compiles
Java against API35 and uses minimum/target SDK21 for these legacy examples.
The certificates are development-only. Compiler/runtime provenance, module inventory, qmake
queries and API21 ELF-loader checks are exported alongside them.

The suite creates a fresh task-owned headless emulator, runs strict C++23
first, all eight ordinary examples, then Widgets and QML gallery rendering.
All 25 strict checks must pass with zero FAIL/SKIP. Ordinary hardware/platform
SKIPs remain explicit. The complete eleven-case report checks guest version,
native exit status, fatal cleanup errors and current APK hashes. Reports and
screenshots are pulled before successful APKs are uninstalled to free guest
space. A partial `-CaseNames` diagnostic never produces a complete-suite report.

Builds use two compiler jobs and one link job; example compilation is capped
at 2 CPUs / 3 GiB. Stop any existing Android emulator before compiling. Run only one
SDK build or emulator at a time. Run directories must have unique names;
the runner refuses to overwrite prior evidence. No keyboard/mouse capture is
used. Default rendering is real GLES, with no forced Qt Quick software backend.

## Boundaries

QtWebEngine, Wayland, Vulkan, DBus, glib and ICU are excluded. Native Android
multimedia, OpenSLES, TextToSpeech and WebView are built. The Qt6 Android API21
patches guard newer Java APIs at runtime and retain modern paths on newer
systems. Shared memory and system semaphores unavailable in this profile are
guarded in the common examples. C++17 builds the SDK; example clients require
C++23 plus `-fexperimental-library`, including jthread/stop_token behavior.
This is behavior coverage, not full standard-library conformance.

The pre-API24 stdio profile uses 32-bit file offsets. Large files above 2 GiB,
physical device cameras/audio/Bluetooth/NFC/XR and other Android ABIs were not
validated. This target uses QtActivity and shared Qt libraries; applications
must preserve applicable Qt/libc++/platform licences when distributed.

See the [build and emulator evidence](../results/qt6-android-lollipop-armeabi-v7a-llvm21-20261118.md).
