# Platforms

Every target, the oldest system it is built for (its floor), and what has
been run where. Each target's page in [targets/](targets/) says how the floor
is reached and what is switched off below the systems Qt itself supports.

The rule behind the floors: each Qt generation runs where the previous one
did. Qt 4.8 reaches Qt 3.3's systems (Windows 95, Mac OS X 10.2, Linux of
2005), Qt 5.15 reaches Qt 4.8's (Windows XP, Mac OS X 10.6, Ubuntu 10.04),
Qt 6.8 reaches Qt 5.15's (Windows 7, macOS 10.13 and 11.0 on arm64, RHEL 7).
For macOS a floor counts as reached when every Mac supported there can be
upgraded to it: Qt 5's x86_64 build stops at 10.6 because 64-bit Cocoa starts
at 10.5 and every Mac that runs 10.5 runs 10.6.

## Results

All runs below used the kit's test suite (`tests/`, see
[testing.md](testing.md)): the applications are run with `--selftest` by
`smoke-runner`, and "8/8, 497 passed" means every application passed and 497
individual checks passed, none failed. Runs before 2026-10-10 used the
earlier layout of the suite, which built 24 applications on Qt 4 (the same
checks, split differently); the Qt 4 numbers below count those. Each result
links its record in [results/](results/); a system is listed with its latest
run.

### Qt 4.8.7

| Target | Floor | Run on | Result |
|--------|-------|--------|--------|
| `qt4-win-i386` | Windows 95 OSR2 | Windows 95 OSR2 (QEMU) | 24/24, 528 passed, 0 failed ([json](results/qt4-win95-openssl102u-qemu-20261002.json)) |
| | | Windows 98 SE, NT 4.0 SP6a, 2000 (VMware) | 8/8 each, 364, 362 and 365 passed, 0 failed ([98 SE](results/qt4-win98se-vmware-20261010.json), [NT 4](results/qt4-nt4-sp6a-vmware-20261010.json), [2000](results/qt4-win2000-vmware-20261010.json)) |
| | | Windows 11 (the build host) | 8/8, 373 passed, 0 failed ([json](results/qt4-win-i386-win11-host-20261010.json)); the two native print dialog checks skip there |
| `qt4-win-amd64` | Windows XP x64 | Windows 11 (the build host) | 8/8, 371 passed, 0 failed ([json](results/qt4-win-amd64-win11-host-20261011.json)); not yet on XP x64 |
| `qt4-linux-i386` | Debian 3.1 Sarge (glibc 2.3.2) | Sarge, kernel 2.6.8 (QEMU) | 8/8, 361 passed, 0 failed ([json](results/qt4-linux-i386-sarge-qemu-20261013.json)); earlier 24/24 on a Sarge Xfce desktop ([json](results/qt4-sarge-desktop-20261002.json)) |
| | | Ubuntu 16.04 i386, Debian 12 i386 (containers) | 8/8, 366 passed, 0 failed ([Ubuntu](results/qt4-linux-i386-ubuntu-16.04-i386-docker-20261011.json), [Debian](results/qt4-linux-i386-debian-12-i386-docker-20261011.json)) |
| `qt4-linux-amd64` | Debian 3.1 Sarge amd64 | Debian 13 (container) | 8/8, 366 passed, 0 failed ([json](results/qt4-linux-amd64-debian-13-docker-20261011.json)); CentOS 7 and Ubuntu 24.04 before the GLX patch ([json](results/linux-forward-20261010.json)); not yet on Sarge amd64 itself |
| | | CentOS 5.11 x86_64, glibc 2.5 (QEMU) | 8/8, 362 passed, 0 failed ([json](results/qt4-linux-amd64-centos-5-qemu-20261011.json)) |
| | | Debian 4.0 etch amd64, glibc 2.3.6 (QEMU) | 8/8, 362 passed, 0 failed ([json](results/qt4-linux-amd64-debian-4-qemu-20261011.json)) |
| `qt4-macos-i386` | Mac OS X 10.4 Tiger (Intel) | Tiger 10.4.10 (QEMU) | 24/24, 524 passed, 0 failed ([json](results/qt4-tiger-i386-suite-20261003.json)) |
| `qt4-macos-ppc` | Mac OS X 10.2 Jaguar (PowerPC) | Jaguar 10.2 and 10.2.8 (QEMU, G4) | 8/8 each, 361 passed, 0 failed ([10.2](results/qt4-macos-ppc-jaguar-10.2-qemu-20261014.json), [10.2.8](results/qt4-macos-ppc-jaguar-10.2.8-qemu-20261014.json)); earlier 24/24 also on an emulated G3 ([json](results/qt4-jaguar-suite-20261005.json)) |
| | | Tiger 10.4.10 (QEMU, G4) | 8/8, 363 passed, 0 failed ([json](results/qt4-macos-ppc-tiger-qemu-20261014.json)) |

Windows Me is expected to behave like Windows 98 SE and has not been run.

### Qt 5.15.19

| Target | Floor | Run on | Result |
|--------|-------|--------|--------|
| `qt5-win-i386`, `qt5-win-amd64` | Windows XP SP3 | Windows XP SP3 (VMware, i386) | 8/8, 478 passed, 0 failed ([json](results/qt5-win-i386-xp-sp3-vmware-20261010.json)); earlier also on real XP hardware |
| | | Windows 11 (the build host), amd64 | 8/8, 498 passed, 0 failed ([json](results/qt5-win-amd64-win11-host-20261010.json)); the two native print dialog checks skip there |
| `qt5-win-arm64` | Windows 10 on ARM | - | built, not run |
| `qt5-linux-amd64` | Ubuntu 10.04 (glibc 2.11, libxcb 1.5) | Ubuntu 10.04.4 (VMware) | 8/8, 498 passed, 0 failed ([json](results/qt5-linux-amd64-lucid-vmware-20261013.json)) |
| | | CentOS 7, Debian 13 (containers) | 8/8, 511 passed, 0 failed ([CentOS 7](results/qt5-linux-amd64-centos-7-docker-20261013.json), [Debian 13](results/qt5-linux-amd64-debian-13-docker-20261013.json)); with GStreamer, PulseAudio, speech-dispatcher and BlueZ installed, 513 ([json](results/qt5-linux-amd64-debian-13-media-docker-20261013.json)) |
| | | Ubuntu 16.04/24.04, Fedora 44, Arch (containers) | 8/8 on each, 474-490 passed, 0 failed ([json](results/linux-forward-20261010.json)) |
| `qt5-linux-i386` | Ubuntu 10.04 i386 | Ubuntu 10.04 i386, 16.04 i386, Debian 12 i386 (containers) | 8/8, 494, 509 and 510 passed, 0 failed ([10.04](results/qt5-linux-i386-ubuntu-10.04-i386-docker-20261013.json), [16.04](results/qt5-linux-i386-ubuntu-16.04-i386-docker-20261013.json), [Debian 12](results/qt5-linux-i386-debian-12-i386-docker-20261013.json)) |
| `qt5-linux-arm64` | Ubuntu 14.04 arm64 (glibc 2.19) | stock Ubuntu 14.04 and Debian 12 arm64 (containers, emulated) | 8/8, 510 and 511 passed, 0 failed ([14.04](results/qt5-linux-arm64-ubuntu-14.04-arm64-docker-20261013.json), [Debian 12](results/qt5-linux-arm64-debian-12-arm64-docker-20261013.json)) |
| `qt5-macos-amd64` | Mac OS X 10.6 | 10.6.3, 10.7.5, 10.13.6 (VMware) | 8/8 each, 494, 496 and 497 passed, 0 failed ([10.6](results/qt5-macos-amd64-snowleopard-vmware-20261010.json), [10.7](results/qt5-macos-amd64-patches34-38-lion-vmware-20261009.json), [10.13](results/qt5-macos-amd64-patches34-38-highsierra-vmware-20261009.json)); a 10.11 build earlier on real OS X 10.11.6 |
| `qt5-macos-i386` | Mac OS X 10.6 (32-bit Intel) | 10.6.3, 10.7.5, 10.13.6 (VMware) | 8/8 each, 494, 496 and 497 passed, 0 failed ([10.6](results/qt5-macos-i386-snowleopard-vmware-20261010.json), [10.7](results/qt5-macos-i386-lion-vmware-20261009.json), [10.13](results/qt5-macos-i386-highsierra-vmware-20261009.json)) |
| `qt5-macos-arm64` | macOS 11.0 | - | built and audited, not run |

### Qt 6.8.4

| Target | Floor | Run on | Result |
|--------|-------|--------|--------|
| `qt6-win-amd64` | Windows 7 SP1 | Windows 7 SP1 (VMware) | 8/8, 508 passed, 0 failed ([json](results/qt6-win7-vmware-20261010.json)) |
| | | Windows 11 (the build host) | 8/8, 510 passed, 0 failed ([json](results/qt6-win-amd64-win11-host-20261010.json)) |
| `qt6-win-arm64` | Windows 10 on ARM | - | built, not run |
| `qt6-linux-amd64` | RHEL/CentOS 7.6 (glibc 2.17) | CentOS 7, Debian 13 (containers) | 8/8, 528 passed, 0 failed, QtWayland included ([CentOS 7](results/qt6-linux-amd64-centos-7-docker-20261012.json), [Debian 13](results/qt6-linux-amd64-debian-13-docker-20261012.json)) |
| | | Linux Mint 22.3 (VMware) | 8/8, 510 passed, 0 failed ([json](results/qt6-linux-centos7-mint223-vmware-20261006.json)) |
| `qt6-linux-arm64` | RHEL/CentOS 7 aarch64 (glibc 2.17) | stock CentOS 7 and Debian 12 arm64 (containers, emulated) | 8/8, 528 passed, 0 failed, QtWayland included ([CentOS 7](results/qt6-linux-arm64-centos-7-arm64-docker-20261012.json), [Debian 12](results/qt6-linux-arm64-debian-12-arm64-docker-20261012.json)) |
| `qt6-macos-amd64` | macOS 10.13 | macOS 10.13.6 (VMware) | 7/7 built applications, 240 passed, 0 failed ([json](results/qt6-macos-1013-jit-highsierra-vmware-20261007.json)) |
| `qt6-macos-arm64` | macOS 11.0 | - | built and audited, not run |

## Current systems

Windows and Linux keep old ABIs, so every Windows and Linux target is
expected to run on current releases too; the Linux suites are run on current
distributions in containers (above). macOS dropped PowerPC (10.7), 32-bit
applications (10.15) and, after macOS 27, Rosetta 2 for x86_64 applications
on Apple silicon: the Qt 4 Mac builds stop at 10.6 (PowerPC under Rosetta) and
10.14, the Qt 5 i386 build at 10.14.

The 32-bit libraries the i386 Linux builds need are still packaged by Ubuntu,
Debian and Fedora; distributions shrinking their i386 sets are the main
long-term risk there.

## Not covered yet

- Real hardware for the newest floors: Windows on ARM, Apple silicon, a
  32-bit-only Core Duo Mac, Lucid on hardware with DRI2 drivers (in VMware
  Lucid's X server reports GLX 1.2 and Qt draws in software).
- Windows Me; Windows 95 in VMware (its Tools are unstable there; Windows 95
  runs are in QEMU).
- Real audio and video output on the oldest systems.
