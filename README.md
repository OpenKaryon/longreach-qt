# Longreach Qt

Static Qt SDKs that reach old operating systems. Longreach Qt builds Qt 4.8.7,
Qt 5.15.19 and Qt 6.8.4 in Docker for Windows, Linux and macOS, and backports
each one far enough that an application built with it runs on the systems the
previous Qt generation supported - and on every newer one, from the same
binary.

| Qt | Windows | Linux | macOS |
|----|---------|-------|-------|
| 4.8.7 | Windows 95 OSR2 (i386); XP x64* (amd64) | Debian 3.1 Sarge, glibc 2.3.2 (i386; amd64*) | Mac OS X 10.2 Jaguar (PowerPC); 10.4 Tiger (Intel) |
| 5.15.19 | Windows XP SP3 (i386, amd64); Windows 10* (arm64) | Ubuntu 10.04 Lucid, glibc 2.11 (amd64; i386*); Ubuntu 16.04 (arm64) | Mac OS X 10.6 Snow Leopard (x86_64, i386); 11.0* (arm64) |
| 6.8.4 | Windows 7 SP1 (amd64); Windows 10* (arm64) | RHEL/CentOS 7, glibc 2.17 (amd64); Debian 12 (arm64) | macOS 10.13 High Sierra (x86_64); 11.0* (arm64) |

\* built and audited, not yet run on that system.

The floors, how each was reached and what has been run where are in
[docs/platforms.md](docs/platforms.md). Upstream Qt starts at Windows XP SP3 /
Ubuntu 10.04 / Mac OS X 10.4 for Qt 4.8, Windows 7 / Ubuntu 18.04 / macOS
10.13 for Qt 5.15, and Windows 10 / Ubuntu 22.04 / macOS 12 for Qt 6.8.

## Quick start

You need Docker, GNU make and Python 3.11 or newer
([details](docs/getting-started.md)).

```sh
make qt5-win-amd64            # the SDK: toolchain and static Qt
make qt5-win-amd64-examples   # the SDK if needed, then the test applications
```

`<target>-examples` builds the eight test applications against the SDK and
copies them to `artifacts/tests-<image>/` on this machine; copy that
directory to the target system and run `smoke-runner`, or let
`scripts/run/run.py` do it ([testing](docs/testing.md)).

Every target, one per Qt version, OS and architecture, each from its floor:

| Qt | Windows | Linux | macOS |
|----|---------|-------|-------|
| 4.8.7 | `qt4-win-i386`, `qt4-win-amd64` | `qt4-linux-i386`, `qt4-linux-amd64` | `qt4-macos-i386`, `qt4-macos-ppc` |
| 5.15.19 | `qt5-win-i386`, `qt5-win-amd64`, `qt5-win-arm64` | `qt5-linux-i386`, `qt5-linux-amd64`, `qt5-linux-arm64` | `qt5-macos-i386`, `qt5-macos-amd64`, `qt5-macos-arm64` |
| 6.8.4 | `qt6-win-amd64`, `qt6-win-arm64` | `qt6-linux-amd64`, `qt6-linux-arm64` | `qt6-macos-amd64`, `qt6-macos-arm64` |

Each name works with `make <target>` and `make <target>-examples`; the floors
and details are on the [target pages](docs/targets/).

All of them, SDKs and test applications, in one run (hours; not a make
target):

```sh
python scripts/build/build-all.py --jobs 2
```

`--jobs` is how many targets build at once, `--make-jobs` the compiler jobs
inside each; `--only`/`--skip` pick targets, `--no-cache` rebuilds from
nothing. Logs and a summary go to `build/build-all-<time>/`.

## How it works

- Each Qt generation has one patch series per operating system under
  `patches/qt<N>/<os>/`, applied whole by every build of that OS. The patches
  select every API newer than the floor at run time (or from the deployment
  target), so the newest system still takes the modern path
  ([backports](docs/backports.md)).
- One Dockerfile per target under `docker/qt<N>/<os>/`, three or more stages:
  toolchain, builder, and a final image holding the toolchain plus the
  installed SDK.
- Every input is pinned by SHA256 (`scripts/fetch/`).
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

Version 0.1.0 is a source-only pre-release: no prebuilt SDK images are
published yet. See [CHANGELOG.md](CHANGELOG.md) and
[docs/releasing.md](docs/releasing.md). Contributions: [CONTRIBUTING.md](CONTRIBUTING.md).
