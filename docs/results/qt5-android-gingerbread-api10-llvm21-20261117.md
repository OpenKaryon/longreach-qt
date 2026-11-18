# Qt 5.15.19 Android 2.3.3 ARMv7 probe

Validated on 2026-11-17 using LLVM 21.1.8. The selected Qt 5 Android floor
is Android 2.3.3, API 10, `armeabi-v7a`.

The subsequent [full SDK and QtActivity validation](qt5-android-gingerbread-sdk-llvm21-20261117.md)
records the completed integration; this page preserves the initial probe.

## Results

| Probe | Result |
| --- | --- |
| Shared modern C++ suite | 25 PASS, 0 FAIL, 0 SKIP |
| Classic C locale | PASS |
| QtCore 5.15.19 static build | PASS |
| Host qmake | QMake 3.1, Qt 5.15.19 |
| C++23 QtCore APK | PASS, native return code 0 |

The modern suite reported `__cplusplus=202302`. It ran the existing
`scripts/tests/qt6-llvm-probes/main.cpp` through the existing Android JNI
adapter. The host validated the complete guest report with
`scripts/tests/require-modern-cpp.py`.

The checks include jthread stop and join, stop-token cancellation and
callbacks, atomic wait/notify, thread-local destruction, exception
unwinding, Unicode filesystem operations, format/print and expected error
propagation.

The separate QtCore consumer also compiled with `-std=c++23` and a compile-time
assertion on `__cplusplus`. Its guest result was:

```text
core on Android 2.3.3, API 10, armeabi-v7a
QtCore 5.15.19 PASS: UTF-8 QString/QFile, JSON, QThread, event loop, timer and C++23 expected; __cplusplus=202302
Native probe returned 0
```

The QtCore checks write, read and remove a Unicode-named file in app-private
storage, round-trip a JSON object, start and join a QThread created from a
lambda, run a timer through QCoreApplication, check qVersion and use
std::expected with QString.

## Toolchain and runtime

The existing `longreach-qt4-android-donut:llvm21` tools image provided
upstream Clang, LLD and LLVM 21.1.8. A separate container rebuilt static
libc++, libc++abi, libunwind and compiler-rt from the pinned LLVM source.
Builds used two jobs, a two-CPU limit and a 3 GiB container memory limit.
The build container was stopped before each emulator run.

The target triple was `armv7a-linux-androideabi10`, with
`-march=armv7-a -mfpu=vfpv3-d16 -mfloat-abi=softfp -fPIC -femulated-tls`.
The NDK r7 API 9 ARM sysroot supplies native interfaces available below the
chosen API 10 floor. The APK manifests and dex files target API 10 and
package the native library under `lib/armeabi-v7a/`.

The existing Donut compatibility patches were adapted for the old Bionic
headers and the pre-21 runtime profile. They supply the classic locale,
missing declarations and filesystem fallbacks. LLVM's ARMv7 builtins are
used for this ABI.

Both APKs were signed with the disposable local probe key using v1 JAR
signing. The native library uses the SysV ELF hash. ELF inspection
identified 32-bit ARM v7 and VFPv3-D16. The QtCore library's dynamic
dependencies are `liblog.so`, `libdl.so`, `libm.so` and `libc.so`;
the C++ runtime and QtCore are linked statically.

## Exact Android guest

The system image, original ramdisk and android.jar came from Google's
`android-2.3.3_r02-linux.zip`. That SDK's default kernel targets older ARM
hardware. The successful ARMv7 run used `kernel-qemu-armv7` from AOSP's
`android-2.3.3_r1` tag.

The ramdisk's default properties declare `armeabi-v7a` as the primary ABI
and `armeabi` as the secondary ABI for the emulated Cortex-A8. The SDK's
system.img was kept intact. The guest reported Android 2.3.3 and API 10,
and the kernel reported an ARMv7 processor. The APK was installed through
Package Manager and loaded from its armeabi-v7a library directory.

The newer Google ARMv7 API 10 archive, `armeabi-v7a-10_r05.zip`, contains
Android 2.3.7. Its system image was excluded from the successful runs.
Its newer kernel also failed to boot the older 2.3.3 userspace reliably.
The successful kernel is from the matching AOSP 2.3.3 tag.

## QtCore configuration and compatibility changes

QtCore was built statically from QtBase 5.15.19 in C++17 mode. The consumer
APK uses C++23. The minimal cross mkspec uses the source tree's
`android-embedded` code paths and defines `Q_OS_ANDROID_EMBEDDED`.

The probe configuration disables GUI, Widgets, OpenGL, D-Bus, GLib, ICU,
iconv, OpenSSL, shared memory, system semaphores, inotify, getentropy and
largefile, and uses Qt's bundled zlib. Qt's PCRE2 static dependency is
linked into the consumer APK.

Additional compatibility adjustments were needed:

- QString's std::wstring conversion adapters are conditional on libc++'s
  wide-character support. This runtime is built without that support.
- The timezone backend uses its existing fixed symlink limit when Bionic
  lacks `_SC_SYMLOOP_MAX`.
- The old kernel header's offsetof macro uses the compiler builtin so that
  Qt's static metatype initializers remain constant expressions.
- The std::future configuration test omits a separate libpthread for the
  Android embedded profile. Bionic provides pthread functions through libc.
  The resulting configuration enables QThread::create.
- The cross mkspec supplies the Android library-name suffix and links the
  rebuilt runtime archives explicitly with LLD.

The C++ locale adapter supports C/POSIX. Wider locale coverage,
std::wstring adapters and large-file behavior need separate work.

## Validation scope and next stage

This proves the rebuilt C++ runtime and the selected QtCore functionality
on API 10. The host qmake version was checked. qmake and CMake consumer
builds, the standard QtActivity Java integration, the Android GUI platform
plugin, keyboard integration and Qt Quick 2 remain to be validated.

The native core library uses the embedded bootstrap configuration.
A complete Qt 5 Android SDK and the shared GUI examples are the next
backport stage. Qt 5's common patch series and all example modules also
need integration and validation during that stage.

## Inputs

- [Google Android 2.3.3 SDK revision 2](https://dl.google.com/android/repository/android-2.3.3_r02-linux.zip)
- [AOSP NDK r7 API 9 ARM sysroot](https://android.googlesource.com/platform/prebuilt/+archive/968372cd8fffab51ff89c6b3cb40bc74ede24cb9/ndk/android-ndk-r7/platforms/android-9/arch-arm.tar.gz)
- [AOSP Android 2.3.3 ARMv7 kernel](https://android.googlesource.com/platform/prebuilt/+/android-2.3.3_r1/android-arm/kernel/kernel-qemu-armv7)
- LLVM 21.1.8 and Qt 5.15.19 from the repository's existing source archives.
- Android SDK Tools 24.4.1 emulator and Build Tools 36.0.0 from the Qt 4 probe.

SHA256 values recorded from the input files:

```text
54bdb0f1ca06ba5747061ddeea20f431af72c448334fd4d3d7f84ea2ccd29fea  android-2.3.3_r02-linux.zip
6f7ec1a9b177ccd1da48c2045d14c5f62fc7db32581919535269cc2738a35f8d  aosp-ndk-r7-api9-arm.tar.gz
6dcf3553f233825cdb83ae8c62b7af23f72ddf753d828e2343c0a482bb23b5ce  kernel-qemu-armv7
4633a23617fa31a3ea51242586ea7fb1da7140e426bd62fc164261fe036aa142  llvm-project-21.1.8.src.tar.xz
173c2326dae138bbb0d98921e9d911e55c00163d93a6db29f294b5e19ff306ae  qt-everywhere-opensource-src-5.15.19.tar.xz
```

The kernel's Git blob SHA1 was also verified as
`3193300384229f1b0e95399228ed2087df22cd24`.

## Local artifacts

The output directory is `artifacts/qt5-android-gingerbread-probe/`.

- `strict.apk` and `core.apk`.
- `libQt5Core.a`, `strict.so`, `core.so` and ELF inspection reports.
- `run/strict/strict-cxx23-guest.stdout` and the guest logcat.
- `run/core/logcat.log` with the QtCore result.
- `qmake-version.txt`.
- `experiment/` with the local build/packaging/run scripts, compatibility
  changes, consumer source, matching ARMv7 kernel, adjusted ramdisk and logs.

The experiment files retain their local staging paths. They provide the
record for continuing this probe. The maintained Qt 5 Android build recipe
will be added during integration.
