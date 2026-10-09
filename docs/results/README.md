# Results

The final run of each target on each system it was checked on. Each file is
a runtime result (schema 1: date, target, image, commit, guest, summary,
per-application counts and the SHA256 of every executable) or, for the Linux
forward checks, a list of container runs. [platforms.md](../platforms.md)
summarises them.

| File | Target | System |
|------|--------|--------|
| `qt4-win95-openssl102u-qemu-20261002.json` | Qt 4 Windows i386 | Windows 95 OSR2 (QEMU) |
| `qt4-win98se-vmware-20261007.json` | Qt 4 Windows i386 | Windows 98 SE (VMware) |
| `qt4-nt4-sp6a-vmware-20261006.json` | Qt 4 Windows i386 | Windows NT 4.0 SP6a (VMware) |
| `qt4-win2000-vmware-20261007.json` | Qt 4 Windows i386 | Windows 2000 (VMware) |
| `qt4-sarge-public-sdk-qemu-20261002.json`, `qt4-sarge-desktop-20261002.json` | Qt 4 Linux i386 | Debian 3.1 Sarge (QEMU, desktop) |
| `linux-forward-20261004.json` | Qt 4 Linux i386 | current distributions (containers) |
| `linux-forward-20261005.json` | Qt 4 Linux amd64 (Ubuntu 16.04 build), Qt 6 Linux (Ubuntu 18.04 build) | current distributions (containers) |
| `qt4-tiger-i386-suite-20261003.json` | Qt 4 macOS i386 | Mac OS X 10.4.10 (QEMU) |
| `qt4-jaguar-suite-20261005.json` | Qt 4 macOS PowerPC | Mac OS X 10.2, 10.2.8, 10.4.10 (QEMU) |
| `qt4-tiger-ppc-suite-20261005.json`, `qt4-tiger-ppc-g3-suite-20261004.json` | Qt 4 macOS PowerPC (Tiger compiler) | Mac OS X 10.4.10 (QEMU, G4 and G3) |
| `qt5-win-i386-xp-sp3-vmware-20261007.json` | Qt 5 Windows i386 | Windows XP SP3 (VMware) |
| `qt5-linux-lucid-stock-vmware-20261007.json`, `qt5-linux-lucid-x11xcb-vmware-20261007.json` | Qt 5 Linux amd64 (Lucid) | Ubuntu 10.04.4 (VMware) |
| `qt5-linux-lucid-amd64-lucid-vmware-20261010.json` | Qt 5 Linux amd64 (Lucid), rebuilt after the restructure | Ubuntu 10.04.4 (VMware) |
| `linux-forward-20261009.json` | Qt 5 Linux amd64 (Lucid) | CentOS 7 and current distributions (containers) |
| `linux-forward-20261010.json` | Qt 5 Linux amd64 and i386 (Lucid), Qt 4 Linux amd64 and i386 (Sarge), rebuilt after the restructure | CentOS 7, current distributions, 32-bit Ubuntu 16.04 and Debian 12 (containers) |
| `qt5-linux-centos76-gpl-20261006.json`, `qt5-linux-centos76-20261006.json` | Qt 5 Linux amd64 (CentOS 7) | CentOS 7.6 (both licence profiles) |
| `qt5-linux-gpl-mint223-vmware-20261006.json` | Qt 5 Linux amd64 (Ubuntu 16.04 build) | Linux Mint 22.3 (VMware) |
| `qt5-linux-i386-ubuntu1604-vmware-20261007.json` | Qt 5 Linux i386 (Ubuntu 16.04 build) | Ubuntu 16.04 i686 (VMware) |
| `qt5-macos-amd64-patches34-38-{snowleopard,lion,highsierra}-vmware-20261009.json` | Qt 5 macOS x86_64 | 10.6.3, 10.7.5, 10.13.6 (VMware) |
| `qt5-macos-i386-{snowleopard,lion,highsierra}-vmware-20261009.json` | Qt 5 macOS i386 | 10.6.3, 10.7.5, 10.13.6 (VMware) |
| `qt6-win7-vmware-20261006.json` | Qt 6 Windows amd64 | Windows 7 SP1 (VMware) |
| `qt4-win98se-vmware-20261010.json`, `qt4-nt4-sp6a-vmware-20261010.json`, `qt4-win2000-vmware-20261010.json` | Qt 4 Windows i386, rebuilt after the restructure | Windows 98 SE, NT 4.0 SP6a, 2000 (VMware) |
| `qt5-win-i386-xp-sp3-vmware-20261010.json` | Qt 5 Windows i386, rebuilt | Windows XP SP3 (VMware) |
| `qt5-win-amd64-win11-host-20261010.json` | Qt 5 Windows amd64, rebuilt | Windows 11 |
| `qt6-win7-vmware-20261010.json`, `qt6-win-amd64-win11-host-20261010.json` | Qt 6 Windows amd64, rebuilt | Windows 7 SP1 (VMware); Windows 11 |
| `qt4-win-i386-win11-host-20261010.json` | Qt 4 Windows i386, rebuilt | Windows 11 |
| `qt4-win-amd64-win11-host-20261010.json` | Qt 4 Windows amd64, rebuilt | Windows 11 |
| `qt5-macos-amd64-snowleopard-vmware-20261010.json`, `qt5-macos-i386-snowleopard-vmware-20261010.json` | Qt 5 macOS x86_64 and i386, rebuilt | Mac OS X 10.6.3 (VMware) |
| `qt6-linux-centos76-20261006.json`, `qt6-linux-centos7-mint223-vmware-20261006.json` | Qt 6 Linux amd64 (CentOS 7) | CentOS 7.6; Linux Mint 22.3 (VMware) |
| `qt6-linux-ubuntu18-mint223-vmware-20261006.json` | Qt 6 Linux amd64 (Ubuntu 18.04 build) | Linux Mint 22.3 (VMware) |
| `qt6-macos-1013-jit-highsierra-vmware-20261007.json` | Qt 6 macOS x86_64 | macOS 10.13.6 (VMware) |

The Qt 4 results predate the 2026-10-10 change of the suite from 24 to eight
applications; they count the same checks split over more executables. Paths
inside older files may name directories that have since moved.
