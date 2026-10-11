# Changelog

## Unreleased

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

## 0.1.0 - 2026-10-11

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
