# Changelog

## Unreleased

- `scripts/audit/stop_words.py` checks the tree, the staged changes, commit
  messages and identities, the history or a push against a list of private
  words kept outside the repository (`.stopwords`); `scripts/audit/git_hooks.py
  install` runs it from pre-commit, commit-msg and pre-push hooks.
- A bare `make` prints `make help` instead of downloading the Qt 5 sources.
- `make qt6-linux-amd64` and `qt6-linux-arm64` download ninja and
  xcb-util-cursor themselves; a fresh clone had no rule for them.
- The Qt 6 cross targets and `make build-all` build qt6-host only when its
  inputs changed (`make build-qt6-host`), not again whenever Docker has
  dropped its cache. `make build-all` starts the next target at once after
  one whose image was current, without the five-minute gap.
- `DOCKER_BUILD_FLAGS` with a single flag (`DOCKER_BUILD_FLAGS=--progress=plain`)
  no longer stops `make build-<target>`.
- An SDK image is rebuilt only when what its own `docker build` uses changed:
  its Dockerfile, build arguments, the files it copies and (Qt 6 cross
  targets) qt6-host. Before, any change under `scripts/build/`, the
  Makefile or a generation's `mk/*.mk`, `docker/`, `patches/` or `cmake/`
  marked every image of that generation, or all of them, out of date.
  `PARALLEL_JOBS` is not part of it.
- The Qt 4 Linux and macOS images copy only `patches/qt4/all` and their own
  system's patches, and the Qt 6 images only the Qt and LLVM-MinGW archives
  from the build context instead of bind-mounting all of it, which gave the
  Docker cache a new key for any change in the repository.
- `make qt4-macos-ppc-examples` (and `qt4-macos-i386-examples`) no longer
  fails on Windows when an earlier run left its `imports/` folder.

- What the build downloads has a copy in the OpenKaryonLab organisation,
  and the build takes it from there first, upstream only when the copy lacks
  it, if upstream is not on GitHub as well (docs/sources.md,
  scripts/fetch/sources.json): source archives as the
  release `sources` of longreach-qt-sources (`fetch.py`,
  `qt6-fetch-source.py`, `cmake.sh`); osxcross and the projects its build.sh
  clones by branch (cctools-port, apple-libtapi, xar), now fetched by commit
  for every macOS image, from the copies only, since upstream is on GitHub
  too (`git-fetch-pinned.sh`); the base images, now pinned
  by digest and pulled through `BASE_REGISTRY` (ghcr.io/openkaryonlab, or
  docker.io/library). `LONGREACH_UPSTREAM_FIRST=1` reverses the order for a
  pin not copied yet. Where an input comes from is not part of an image's
  fingerprint, so switching sources rebuilds nothing.
  `scripts/fetch/mirror.py` checks the list against the pins (`check
  --online`: and against the copies) and fills the copies.
- The Qt 6 macOS images take the macOS SDK from `downloads/`, fetched by make
  with its SHA256 like every other input, instead of downloading it inside
  Docker; a kept copy of the SDK now works by putting it there.
- `LICENSE_PROFILE=lgpl-friendly` is refused by the Windows and macOS Qt 5/6
  targets, which do not leave the GPL-only modules out yet; before, they built
  an image under that name with the modules in it.
- The Qt 6 images stop at a patch that does not apply; the loop used to go on
  with the next one.
- `manifest.json` named the kit's licence MIT; it is GPL-3.0-or-later.
- `make qt5-linux-arm64` fetches the X sources it copies
  (`qt5-lucid-fetch.py --sources-only`); a fresh clone failed there.
- `qt6-linux-arm64` builds the OpenSSL version make fetched; `QT6_SOURCE`
  replaces an archive already in `downloads/`; the Qt 6 `-examples` targets
  no longer need CMake on the host.
- `LONGREACH_MIRROR` reaches the CMake downloads inside the images, and the
  Qt 6 source fetch goes on to the Qt sites when the copy fails in any way, not
  only with a 404.
- `make verify-downloads` checks every pinned file in `downloads/`, and the
  Sarge and Lucid packages against their locks (`--verify-only`), and says how
  many it checked.
- The Qt 5 macOS SDK is packed in the digest-pinned Ubuntu 22.04 image, and the
  run.py QEMU helper is built from it; `fetch-macos-sdk.sh` fails instead of
  keeping a short archive, and `qt5-extract-tests` fails when a binary could
  not be copied.
- `mirror.py`: `repos` can run again (existing `longreach/` tags are kept, a
  refused push is reported); `archives` checks a download before keeping it
  and reports a release file GitHub gives no SHA256 for; `check` matches each
  image's tag and digest together, looks at every Dockerfile and the scripts
  in subfolders, and finds images named by tag only in make.
- `scripts/build/qt6-build-project.py` prepares the Qt image of every platform
  with `make build-qt6-<platform>`; for Linux and macOS it used to run its own
  `docker build` without the inputs make fetches, and `--download` (gone)
  fetched a wrongly named archive without a SHA256.
- `make download-qt-mobility` and `scripts/fetch/fetch-git-archive.py` are
  gone: no target used Qt Mobility.

## 0.1.0 - 2026-10-15

First public pre-release, source only.

- Static Qt 4.8.7, 5.15.19 and 6.8.4 SDKs built in Docker for Windows, Linux
  and macOS.
- Floors: Qt 4 from Windows 95 OSR2, Debian 3.1 Sarge and Mac OS X 10.2
  Jaguar (PowerPC) / 10.4 Tiger (Intel); Qt 5 from Windows XP SP3, Ubuntu
  10.04 and Mac OS X 10.6 (x86_64 and i386); Qt 6 from Windows 7 SP1,
  RHEL/CentOS 7 and macOS 10.13 (11.0 on Apple silicon). See
  [docs/platforms.md](docs/platforms.md) for what has run where.
- One build per Qt version, OS and architecture (`make qt<N>-<os>-<arch>`),
  each from that combination's floor; the Makefile's shared settings plus
  `mk/qt4.mk`, `mk/qt5.mk` and `mk/qt6.mk`.
- One patch series per Qt generation and OS; every input pinned by SHA256.
- The same eight test applications on all three generations, covering every
  public class each one ships; `scripts/run/run.py` runs them on Docker
  (including 32-bit images), SSH, VMware (including Windows 9x and NT 4),
  VirtualBox targets and the local machine.
- GPL-3.0-or-later; patches and mkspecs keep Qt's licences, so applications
  can still be built under the LGPL.

Also in this release:

- `make <target>-examples` for every target: the SDK when one of its inputs
  changed (`FORCE=1` rebuilds it anyway), then the test applications into
  `artifacts/tests-<image>/`. `make help` lists every target next to its
  `-examples` form.
- `make build-all` (every SDK) and `make build-all-examples` (every SDK and
  its test applications) ask before they start, build up to `BUILD_ALL_JOBS`
  targets at a time - no more than Docker's memory holds, started a few
  minutes apart while enough memory is free - build the failed ones again
  one at a time, and write logs and a summary to `build/build-all-<time>/`
  (`scripts/build/build-all.py`).
- Images and test artifacts take the target's name (`qt5-win-amd64`); a
  `LICENSE_PROFILE` other than the default adds itself
  (`qt5-win-amd64-lgpl-friendly`).
- Optional Linux libraries at run time: `scripts/build/dlopen` makes static
  stub archives that load a shared library on first use, so a binary starts
  where the library is missing and uses it where it is installed. A
  libwayland older than the one the stubs are made from counts as missing,
  and Qt uses xcb there.
- Qt 5 Linux: QtWayland; QtMultimedia with PulseAudio, ALSA and GStreamer
  1.0; QtSpeech with speech-dispatcher; QtBluetooth with BlueZ - all through
  those stubs (`patches/qt5/linux/04` and `05`).
- Qt 6 Linux amd64: QtWayland, through the same stubs.
- Qt 5 Linux arm64 is cross-built for Ubuntu 14.04 (glibc 2.19), with the
  Lucid build's static X libraries and modules.
- Qt 6 Linux arm64 is cross-built for RHEL/CentOS 7 aarch64 (glibc 2.17),
  with OpenSSL, D-Bus and QtWayland; `scripts/build/rpm-sysroot.py` makes its
  sysroot from the CentOS vault.
- Qt 6 macOS: `patches/qt6/macos/18` guards the Metal, save dialog and
  text-to-speech APIs newer than 10.13 that the availability audit found
  unguarded; `19` lets projects that use the SDK find QtNfc.
- Qt 4 Linux: `patches/qt4/linux/03` binds a GLX context only when it is not
  already current, which Debian 4.0's X server needs to keep a GL window's
  frame.
- `scripts/run/run.py --host qemu:<distro>` runs a suite on 64-bit
  distributions with glibc before 2.14, which a container host cannot run
  (`centos-5-x86_64`, `debian-4-amd64`).
- qt-selftest's macOS TLS check uses a temporary keychain, so it passes over
  SSH as well.
- Results: Qt 4 Linux amd64 8/8 on CentOS 5.11 and Debian 4.0; Qt 4 macOS
  i386 8/8 on Tiger 10.4.10 (QEMU, emulated Core Duo); Qt 5 and Qt 6 macOS
  8/8 on a clean macOS 10.13.6; Qt 4 Windows i386 8/8 on Windows 95 OSR2
  (QEMU). See [docs/platforms.md](docs/platforms.md).
