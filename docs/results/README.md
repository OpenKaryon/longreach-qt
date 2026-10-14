# Results

One record per run: what was run, where, and with what result. A runtime
record (schema 1) has the date, target, image, guest system, a summary,
per-application counts and the SHA256 of every executable it ran; a Linux
forward check (`linux-forward-*`) lists one such run per container.
[platforms.md](../platforms.md) summarises them and links each one.

Only the latest run of a target on a system is kept. The Qt 4 records dated
before 2026-10-10 predate the change of the suite from 24 applications to
eight; they count the same checks split over more executables. Files they
name are local evidence of the run: only the file name is kept, next to its
checksum.

| File | Target | System |
|------|--------|--------|
| `qt4-win95-openssl102u-qemu-20261002.json` | Qt 4 Windows i386 | Windows 95 OSR2 (QEMU) |
| `qt4-win98se-vmware-20261010.json`, `qt4-nt4-sp6a-vmware-20261010.json`, `qt4-win2000-vmware-20261010.json` | Qt 4 Windows i386 | Windows 98 SE, NT 4.0 SP6a, 2000 (VMware) |
| `qt4-win-i386-win11-host-20261010.json`, `qt4-win-amd64-win11-host-20261011.json` | Qt 4 Windows i386, amd64 | Windows 11 |
| `qt4-linux-i386-sarge-qemu-20261013.json` | Qt 4 Linux i386 | Debian 3.1 Sarge (QEMU) |
| `qt4-sarge-public-sdk-qemu-20261002.json`, `qt4-sarge-desktop-20261002.json` | Qt 4 Linux i386 | Debian 3.1 Sarge (QEMU, desktop) |
| `qt4-tiger-i386-suite-20261003.json` | Qt 4 macOS i386 | Mac OS X 10.4.10 (QEMU) |
| `qt4-macos-ppc-jaguar-10.2-qemu-20261014.json`, `qt4-macos-ppc-jaguar-10.2.8-qemu-20261014.json`, `qt4-macos-ppc-tiger-qemu-20261014.json` | Qt 4 macOS PowerPC | Mac OS X 10.2, 10.2.8 and 10.4.10 (QEMU, G4) |
| `qt4-jaguar-suite-20261005.json` | Qt 4 macOS PowerPC | Mac OS X 10.2 and 10.2.8 (QEMU, G3) |
| `qt4-linux-amd64-centos-5-qemu-20261011.json` | Qt 4 Linux amd64 | CentOS 5.11 x86_64 (QEMU) |
| `qt4-linux-amd64-debian-4-qemu-20261011.json` | Qt 4 Linux amd64 | Debian 4.0 etch amd64 (QEMU) |
| `qt4-linux-amd64-debian-13-docker-20261011.json` | Qt 4 Linux amd64 | Debian 13 (container) |
| `qt4-linux-i386-{ubuntu-16.04-i386,debian-12-i386}-docker-20261011.json` | Qt 4 Linux i386 | Ubuntu 16.04 i386, Debian 12 i386 (containers) |
| `linux-forward-20261010.json` | Qt 4 and Qt 5 Linux amd64 and i386 | CentOS 7, current distributions, 32-bit Ubuntu 16.04 and Debian 12 (containers) |
| `qt5-win-i386-xp-sp3-vmware-20261010.json` | Qt 5 Windows i386 | Windows XP SP3 (VMware) |
| `qt5-win-amd64-win11-host-20261010.json` | Qt 5 Windows amd64 | Windows 11 |
| `qt5-linux-amd64-lucid-vmware-20261014.json` | Qt 5 Linux amd64 | Ubuntu 10.04.4 (VMware) |
| `qt5-linux-amd64-{centos-7,debian-13,debian-13-media}-docker-20261014.json` | Qt 5 Linux amd64 | CentOS 7, Debian 13, Debian 13 with the media libraries (containers) |
| `qt5-linux-i386-{ubuntu-10.04-i386,ubuntu-16.04-i386,debian-12-i386}-docker-20261014.json` | Qt 5 Linux i386 | Ubuntu 10.04 i386, Ubuntu 16.04 i386, Debian 12 i386 (containers) |
| `qt5-linux-arm64-{ubuntu-14.04-arm64,debian-12-arm64}-docker-20261014.json` | Qt 5 Linux arm64 | Ubuntu 14.04 arm64, Debian 12 arm64 (containers, emulated) |
| `qt5-macos-amd64-snowleopard-vmware-20261010.json`, `qt5-macos-amd64-patches34-38-lion-vmware-20261009.json`, `qt5-macos-amd64-highsierra-vmware-20261014.json` | Qt 5 macOS x86_64 | 10.6.3, 10.7.5, 10.13.6 (VMware) |
| `qt5-macos-i386-snowleopard-vmware-20261010.json`, `qt5-macos-i386-lion-vmware-20261009.json`, `qt5-macos-i386-highsierra-vmware-20261014.json` | Qt 5 macOS i386 | 10.6.3, 10.7.5, 10.13.6 (VMware) |
| `qt6-win7-vmware-20261010.json`, `qt6-win-amd64-win11-host-20261010.json` | Qt 6 Windows amd64 | Windows 7 SP1 (VMware); Windows 11 |
| `qt6-linux-amd64-{centos-7,debian-13}-docker-20261014.json` | Qt 6 Linux amd64 | CentOS 7, Debian 13 (containers) |
| `qt6-linux-centos7-mint223-vmware-20261006.json` | Qt 6 Linux amd64 | Linux Mint 22.3 (VMware) |
| `qt6-linux-arm64-{centos-7-arm64,debian-12-arm64}-docker-20261014.json` | Qt 6 Linux arm64 | CentOS 7 aarch64, Debian 12 arm64 (containers, emulated) |
| `qt6-macos-amd64-highsierra-vmware-20261014.json` | Qt 6 macOS x86_64 | macOS 10.13.6 (VMware) |
