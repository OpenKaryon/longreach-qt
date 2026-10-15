# Changelog

## Unreleased

- `make <target>-examples` for every target: the SDK when one of its inputs
  changed (`FORCE=1` rebuilds it anyway), then the test applications into
  `artifacts/tests-<image>/`; Qt 6's move there from `artifacts/qt6-*/`.
- `make build-all` (every SDK) and `make build-all-examples` (every SDK and
  its test applications) ask before they start, build up to `BUILD_ALL_JOBS`
  targets at a time - no more than Docker's memory holds, started a few
  minutes apart while enough memory is free - build the failed ones again
  one at a time, and write logs and a summary to `build/build-all-<time>/`
  (`scripts/build/build-all.py`).
- The default licence profile no longer adds itself to image and artifact
  names (`qt5-win-amd64`, not `qt5-win-amd64-gpl-enabled`).
- The README's quick start lists every target; `make help` prints each SDK
  target next to its `-examples` form.
- `quick-qml-gallery` is classified GPL-enabled where it links Qt Quick 3D.
- Results: Qt 4 macOS i386 8/8 on Mac OS X Tiger 10.4.10 (QEMU, emulated
  Core Duo), 364 checks, none failed.

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
- Results: Qt 4 Linux amd64 8/8 on CentOS 5.11 and Debian 4.0; Qt 5 and
  Qt 6 macOS 8/8 on a clean macOS 10.13.6; Qt 4 Windows i386 8/8 on Windows
  95 OSR2 (QEMU). See [docs/platforms.md](docs/platforms.md).
