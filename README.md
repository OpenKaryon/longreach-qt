# Longreach Qt

Static Qt SDKs that reach old operating systems. Longreach Qt builds Qt 4.8.7,
Qt 5.15.19 and Qt 6.8.5 in Docker for Windows, Linux and macOS, and backports
each one to older operating systems. The same application binary can
serve older and newer systems within a target architecture.

The SDK build pipeline is based on LLVM. Clang builds the target Qt
libraries and applications. Seventeen desktop targets default to upstream LLVM
21.1.8 and static libc++. The four Windows and macOS ARM64 profiles use
their existing Clang toolchains. Bootstrap stages, host tools and legacy
platform inputs can use other compilers and linkers. See the
[toolchain matrix](docs/toolchains.md).

| Qt | Windows | Linux | macOS |
|----|---------|-------|-------|
| 4.8.7 | Windows 95 OSR2 (i386); XP x64 (amd64) | Debian 3.1 Sarge, glibc 2.3.2 (i386; amd64) | Mac OS X 10.2 Jaguar (PowerPC); 10.4 Tiger (Intel) |
| 5.15.19 | Windows XP SP3 (i386); XP x64 (amd64); Windows 10* (arm64) | Ubuntu 10.04 Lucid, glibc 2.11 (amd64, i386); Ubuntu 14.04, glibc 2.19 (arm64) | Mac OS X 10.6 Snow Leopard (x86_64, i386); 11.0* (arm64) |
| 6.8.5 | Windows 7 SP1 (amd64); Windows 10* (arm64) | RHEL/CentOS 7, glibc 2.17 (amd64, arm64) | macOS 10.13 High Sierra (x86_64); 11.0* (arm64) |

\* Build and binary-audit evidence is available. Runtime validation is pending.

The floors, how each was reached and what has been run where are in
[docs/platforms.md](docs/platforms.md). Upstream Qt starts at Windows XP SP3 /
Ubuntu 10.04 / Mac OS X 10.4 for Qt 4.8, Windows 7 / Ubuntu 18.04 / macOS
10.13 for Qt 5.15, and Windows 10 / Ubuntu 22.04 / macOS 12 for Qt 6.8.

## Experimental Android profiles

The Android recipes use LLVM 21.1.8 and the same eight application sources.
Qt 4 has a static embedded profile; Qt 5 and Qt 6 use shared libraries with
QtActivity. Android SDK, example, package and emulator phases are documented
in the target guides; packaging currently runs on Windows with PowerShell 7.
The [make and build-all interface](docs/android-build.md) exposes the twelve
installed-SDK profiles as `qt<N>-android-<arch>` SDK targets and `-examples`
targets producing ready APKs. Run APKs through the Android runners.
The Qt 4 API4 ARM SDK uses its configured static/raster profile. Its original
combined build remains available through the explicit legacy target.

| Qt | Original floor | Additional qualified ABIs |
| --- | --- | --- |
| [4.8.7](docs/targets/qt4-android-donut.md) | Android 1.6/API4, armeabi | [Android 2.3/API10 x86](docs/targets/qt4-android-gingerbread.md), [Android 5/API21 x86_64 and ARM64](docs/targets/qt4-android-lollipop.md) |
| [5.15.19](docs/targets/qt5-android-gingerbread.md) | Android 2.3.3/API10, armeabi-v7a | [API10 x86](docs/targets/qt5-android-gingerbread.md); [API21 ARM64 and x86_64](docs/targets/qt5-android-lollipop.md) |
| [6.8.5](docs/targets/qt6-android-lollipop.md) | Android 5/API21, armeabi-v7a | API21 ARM64, x86 and x86_64 |

Each ABI has its own runtime evidence and limitations in the linked guides.
Strict C++23 requires 25 PASS, 0 FAIL and 0 SKIP; ordinary device/module
limitations remain explicit. Further ABI experiments are not qualified by
these results.

## Quick start

You need Docker, GNU make and Python 3.11 or newer
([details](docs/getting-started.md)).

```sh
make qt5-win-amd64            # the SDK: toolchain and static Qt
make qt5-win-amd64-examples   # the SDK if needed, then the test applications
```

Desktop `<target>-examples` builds the eight test applications against the
SDK and copies them to `artifacts/tests-<image>/` on this machine; copy that
directory to the target system and run `smoke-runner`, or let
`scripts/run/run.py` do it ([testing](docs/testing.md)).

Desktop targets, one per Qt version, OS and architecture, each from its floor:

| Qt | Windows | Linux | macOS |
|----|---------|-------|-------|
| 4.8.7 | `qt4-win-i386`, `qt4-win-amd64` | `qt4-linux-i386`, `qt4-linux-amd64` | `qt4-macos-i386`, `qt4-macos-ppc` |
| 5.15.19 | `qt5-win-i386`, `qt5-win-amd64`, `qt5-win-arm64` | `qt5-linux-i386`, `qt5-linux-amd64`, `qt5-linux-arm64` | `qt5-macos-i386`, `qt5-macos-amd64`, `qt5-macos-arm64` |
| 6.8.5 | `qt6-win-amd64`, `qt6-win-arm64` | `qt6-linux-amd64`, `qt6-linux-arm64` | `qt6-macos-amd64`, `qt6-macos-arm64` |

Each name works with `make <target>` and `make <target>-examples` (`make help`
lists them in pairs); the floors
and details are on the [target pages](docs/targets/). Make variables tune a
build (compiler jobs, Qt version, licence profile, deployment target): see
[getting started](docs/getting-started.md).

Android adds `qt4-android-{arm,i386,amd64,arm64}`,
`qt5-android-{armv7,i386,amd64,arm64}` and
`qt6-android-{armv7,i386,amd64,arm64}`. Each has only the SDK target and
`-examples`, which consumes a ready SDK and produces APKs. Android ABI names
remain `-Abi` values in the scripts rather than additional make aliases.
Use the [Android runners](docs/android-build.md#reusing-native-outputs-and-running-apks)
to run saved APKs; individual script phases remain available for reusing outputs.

All of them in one run - hours to a day or more, so it asks before it
starts:

```sh
make build-all                # every SDK
make build-all-examples       # every SDK and its test applications
```

`BUILD_ALL_JOBS=2` builds two targets at once; logs and a summary go to
`build/build-all-<time>/`. `scripts/build/build-all.py --help` has the other
options (`--only`, `--skip`, `--no-cache`, ...).
Android runs alone and currently requires a Windows host. Its batch examples
route explicitly prepares the SDK, then builds and packages applications;
it never runs APKs. `--list` is read-only on every host.

## How it works

- Each Qt generation has one patch series per operating system under
  `patches/qt<N>/<os>/`, applied whole by every build of that OS. The patches
  select every API newer than the floor at run time (or from the deployment
  target), so the newest system still takes the modern path
  ([backports](docs/backports.md)).
- Dockerfiles live under `docker/qt<N>/<os>/`. Architectures share a
  recipe where their build steps match. The final SDK image holds the
  toolchain and the installed Qt libraries.
- Every input is pinned: archives by SHA256 (`scripts/fetch/`), Git projects by
  commit, base images by digest, distribution packages by lock or snapshot date
  (the older releases, frozen, from their own archive); copied to
  OpenKaryonLab where its licence allows ([docs/sources.md](docs/sources.md)).
- The same eight test applications build against Qt 4, 5 and 6 and cover the
  public API of each (100% of the classes the kit ships, by
  `scripts/tests/check_coverage.py`).

## Licence

Longreach Qt is GPL-3.0-or-later, Copyright (C) 2026 OpenKaryon. What becomes
part of Qt - the patches, mkspecs and runtime objects - keeps Qt's own terms,
so applications can still be built under the LGPL
([licensing](docs/licensing.md)). Qt itself, OpenSSL and the other components
keep theirs. Apple's SDKs are fetched for you and never redistributed.

## Status

Version 0.3.0 is being prepared as a source-only pre-release with the
LLVM 21.1.8 migration. The latest tag is `v0.2.2`, which preserves the
previous default GCC and MinGW recipes. See the
[0.3.0 release notes](docs/releases/0.3.0.md),
[changelog](CHANGELOG.md) and [release process](docs/releasing.md).
Contributions: [CONTRIBUTING.md](CONTRIBUTING.md).
