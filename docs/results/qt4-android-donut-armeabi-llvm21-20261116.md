# Qt 4 Android 1.6 armeabi probe with LLVM 21.1.8

## Repository build

The [Android build guide](../targets/qt4-android-donut.md) describes the
checked-in workflow. The build script rebuilt LLVM's ARM runtimes and
both Qt 4.8.7 configurations from the verified source archives in a
fresh container with two jobs, a 3 GiB limit and no network. It generated
four APKs and verified their v1 signatures for API 4. The runner
installed each APK on a fresh Android 1.6 userdata image and shut down
the emulator before starting the next check.

## JNI bootstrap result

The JNI bootstrap APK installed and launched on the Android 1.6 revision 3
SDK image. The ARM emulator came from Android SDK Tools 24.4.1 and ran
headless, with its own userdata image. The guest reported Android 1.6, API 4,
and `armeabi`. PackageManager reported `Success` and logcat recorded
`I/LongreachDonut: Native probe returned 42`. The emulator stopped after the
run.

Clang 21.1.8 built the JNI library with
`--target=armv5te-linux-androideabi4 -march=armv5te -mfloat-abi=soft -std=c++23`.
LLD generated a SysV hash table for the legacy Android loader. The ELF audit
reported 32-bit little-endian ARM and the ARMv5TE build attribute. The
bootstrap used `-nostdlib` and had no ELF shared-library dependencies.
The APK advertised `minSdkVersion=4`, `targetSdkVersion=4`, and `armeabi`.
The bootstrap APK SHA-256 is
`3a1f2d83386a3c0ebbfd2edf6496abb810eaaf13cdd106015226baa24cc6b466`.

## Strict C++23 result

The original Longreach strict suite passed on the Android 1.6 ARM emulator.
The guest reported Clang 21.1.8, libc++ 210108 and `__cplusplus=202302`.
The repository validator confirmed **25 PASS, 0 FAIL, 0 SKIP**.
A separate check of `std::locale("C")` and decimal parsing passed.
The [shared modern C++ checks](../../tests/common/moderncpp_checks.h)
were used without changes.

The runtime build used LLVM 21.1.8 sources and the
[AOSP NDK r7 ARM sysroot for API 4](https://android.googlesource.com/platform/prebuilt/+/968372cd8fffab51ff89c6b3cb40bc74ede24cb9/ndk/android-ndk-r7/platforms/android-4/arch-arm/).
The Bionic compatibility patch adds the C locale operations missing from the
Donut Bionic headers, locale data for `lconv` and libc++'s default character
classification table. This runtime supports the classic locale and its
POSIX alias. Wide-character libc++ facets were disabled for this experiment.
The narrow UTF-8 formatting and filesystem checks passed.

The runtime also adapts `posix_memalign`, legacy `stat` and `statfs`
interfaces, ARM EHABI unwinding, and the Linux futex definitions. ARMv5
read-modify-write operations use the kernel's ARM user helpers. The API 4
loader required bypassing weak-symbol detection for
`__cxa_thread_atexit_impl` and using the existing pthread destructor
fallback. The APK supplies a position-independent DSO initializer/finalizer
and creates temporary files in the app's private directory.

The JNI library linked with `--no-undefined` against the API 4 sysroot.
The ELF references only `liblog.so`, `libm.so`, `libdl.so` and `libc.so`.
The strict APK SHA-256 is
`296a92ab9ba6fddf268790a6861d8cedb5c5dbb9a592d48936e86fb3ea1532ee`.

## QtCore 4.8.7

After the strict run passed, the Qt 4.8.7 source archive was cross-built
as static QtCore with Clang 21.1.8 for ARMv5TE soft-float and API 4.
The Linux host qmake reported 2.01a and Qt 4.8.7. The QtCore build used
a minimal no-GUI profile with large-file and STL integration disabled.
The Android adaptations disable SysV shared memory and system semaphores,
use Bionic's available pthread interfaces without cancellation, and
select UTF-8 as Qt's locale codec.

A separate JNI APK statically links `libQtCore.a`. The ELF linked with
`--no-undefined` against the API 4 sysroot and depends only on
`liblog.so`, `libdl.so`, `libm.so` and `libc.so`. It installed and ran
on the same Android 1.6 revision 3 ARM emulator. The guest reported
`QtCore 4.8.7 PASS: QString, QFile, QCoreApplication and QTimer` and
`Native probe returned 0`. The smoke test checked UTF-8 text and the file
name, a write/read round trip in app-private storage, and a timer that
stopped the Qt event loop. The emulator stopped after the run.

The QtCore archive SHA-256 is
`1c67817bd99837078a5b7d16c974df1c4c26bf9ff95c77ad2ce1e567c659a951`.
The QtCore APK SHA-256 is
`f0c6e020c0e8fdebaca4be4237710cea16c1481d617656e3a43cb5b6612ffad6`.

## Qt Quick 1

A second Qt 4.8.7 configuration built static QtCore, QtGui, QtNetwork,
QtScript, QtDeclarative and QtSql with Clang 21.1.8 for ARMv5TE soft-float
and API 4. The APK uses Qt's minimal QPA plugin and a JNI raster bridge.
Qt renders the scene into a QImage, and the Android Activity draws it to
a Canvas. This configuration exercises Qt Quick 1 in a small Android app.
It uses the repository's JavaScriptCore tagged-frame-pointer fix.

The [mobile scene](../../tests/quick-qml-gallery/qml_qt4/MobileSmoke.qml)
uses the same switch as the Controls page in the gallery. The APK
installed on the same Android 1.6 revision 3 ARM emulator. Android
instrumentation and the app-private report confirmed all three checks:

| Check | Result |
| --- | --- |
| Load the scene from `qrc:` and render the first frame with the switch off | PASS |
| Deliver a tap through the Android window and observe both the QML state and the rendered color change | PASS |
| Pause and resume the Activity, observe a new frame with the switch still on, and tap it off again | PASS |

Android instrumentation returned `Activity.RESULT_OK`. The emulator
stopped after the run. The APK's JNI library linked with
`--no-undefined` and depends only on `liblog.so`, `libdl.so`, `libm.so`
and `libc.so`. The mobile APK SHA-256 is
`cb8d25afe6b225e73a24f5385a746f36176d9f7f7d9847ed4fa169922b529488`.
The [APK launcher and test harness](../../tests/android-donut) live beside
the shared gallery scene in the repository. All four ELF reports identify
32-bit ARMv5TE and a SysV hash table. They contain no `TEXTREL` entries.

## Input hashes

| File | SHA-256 |
| --- | --- |
| `android-1.6_r03-linux.zip` | `a8c4e3b32269c6b04c2adeabd112fce42f292dab1a40ef3b08ea7d4212be0df4` |
| `tools_r24.4.1-windows.zip` | `74fe511d80d28678f2250f89b63d0d8e5ba80428cb2345279fa019183fa0476f` |
| `llvm-project-21.1.8.src.tar.xz` | `4633a23617fa31a3ea51242586ea7fb1da7140e426bd62fc164261fe036aa142` |
| `qt-everywhere-opensource-src-4.8.7.tar.gz` | `e2882295097e47fe089f8ac741a95fef47e0a73a3f3cdf21b56990638f626ea0` |
| NDK r7 ARM API 4 Gitiles archive | `7049f4b170edc3415d48ff4fb36fe9b110ee7122f65051a727edb75600ad0057` |
