# Changelog

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

- `scripts/build/dlopen`: static archives of stubs that load a shared library
  on first use (x86_64, i386, aarch64; position-independent), with failure
  values for APIs where 0 means success and mirrored data for libraries that
  export it. The binaries link them in place of the libraries and start where
  those are missing. libwayland older than the one the stubs are made from
  counts as missing, so Qt uses xcb there instead of calling what it lacks.
- Qt 5 Linux (Lucid): QtWayland is built, and QtMultimedia has PulseAudio,
  ALSA and GStreamer 1.0 backends, QtSpeech speech-dispatcher, QtBluetooth
  BlueZ, all through those stubs; `patches/qt5/linux/04` starts the GStreamer
  services only when GStreamer initializes, and `05` keeps QtBluetooth from
  crashing where there is no D-Bus system bus.
- Qt 6 Linux amd64: QtWayland is built, through the same stubs.
- Qt 5 Linux arm64 is cross-built for Ubuntu 14.04 (was a native Ubuntu 16.04
  build under emulation), with the Lucid build's static X libraries and
  module set.
- Qt 6 Linux arm64 is cross-built for RHEL/CentOS 7 aarch64 (was Debian 12),
  with OpenSSL, D-Bus and QtWayland; `scripts/build/rpm-sysroot.py` makes the
  sysroot from the CentOS vault. The qt6-host image builds qtwayland and
  QtDBus for their host tools.
- Tests: on macOS, qt-selftest's TLS loopback check gives the server a
  temporary keychain (`QT_SSL_USE_TEMPORARY_KEYCHAIN`). SecureTransport
  otherwise imports the server identity into the user's keychain, which an
  SSH session cannot unlock, and the handshake failed there.
- Results: Qt 5 (amd64, i386) and Qt 6 macOS 8/8 on a clean macOS 10.13.6
  install in VMware, 496 and 504 checks, none failed; Qt 4 Windows i386 8/8
  on Windows 95 OSR2 in QEMU, 367 checks, none failed.
- Qt 6 macOS: `patches/qt6/macos/19` lets projects that use the SDK find
  QtNfc (its PC/SC lookup relied on variables only Qt's own build defines),
  so the suite's qt-selftest builds for Qt 6 macOS too.
- Qt 6 macOS: `patches/qt6/macos/18` guards the newer Metal, save dialog and
  text-to-speech APIs that the availability audit found unguarded and that
  would fail below their macOS version (Qt Quick's pipeline cache needs
  macOS 11's `MTLBinaryArchive`). The other uses of the 144 are compile-time
  only or behind a guarded call.
- Qt 4 Linux: `patches/qt4/linux/03` binds a GLX context only when it is not
  already current on the drawable; Debian 4.0's X server lost a large GL
  window's frame on the repeated bind, so `grabFrameBuffer()` read black.
- `scripts/run/run.py --host qemu:<distro>` boots an old distribution's
  userland in QEMU under a current kernel, for 64-bit systems with glibc
  before 2.14 that a container host cannot run: `centos-5-x86_64`,
  `debian-4-amd64`.
- Qt 4 Linux amd64 has run on its era's 64-bit systems: 8/8 on CentOS 5.11
  and Debian 4.0 etch.
- `docs/results` keeps the latest run of each target on each system, without
  the commit field; run.py no longer writes it.
- The Qt 5 macOS i386 startup object is built from one C file.
- The project is called Longreach Qt throughout.
