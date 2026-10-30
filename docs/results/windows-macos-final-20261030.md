# Final Windows and macOS suite validation, 2026-10-30

Windows is tested before macOS. Only one test VM runs at a time;
the user keeps Linux Mint running alongside it. Test VMs are suspended
with their state saved before the next test VM starts.

The suites are the final local build artifacts: Qt 4.8.7 at `db747c3`
and Qt 5.15.19 / Qt 6.8.5 at `ea9b0aa`. The intervening source change
affects only Qt 5/6 QDom patches; subsequent commits record documentation.
No SDK rebuild is part of these runs.

Completed **22/22** planned suite/system runs. The planned VM matrix is complete.

| Suite | System | Status | Applications passed / failed | Checks passed / failed / skipped | Record |
|-------|--------|--------|------------------------------|----------------------------------|--------|
| `qt4-win-i386` | Windows 11 x64 | PASS | 8 / 0 | 373 / 0 / 126 | [json](qt4-win-i386-win11-vmware-20261030.json) |
| `qt4-win-amd64` | Windows 11 x64 | PASS | 8 / 0 | 371 / 0 / 126 | [json](qt4-win-amd64-win11-vmware-20261030.json) |
| `qt5-win-i386` | Windows 11 x64 | PASS | 8 / 0 | 498 / 0 / 90 | [json](qt5-win-i386-win11-vmware-20261030.json) |
| `qt5-win-amd64` | Windows 11 x64 | PASS | 8 / 0 | 498 / 0 / 90 | [json](qt5-win-amd64-win11-vmware-20261030.json) |
| `qt6-win-amd64` | Windows 11 x64 | PASS | 8 / 0 | 510 / 0 / 54 | [json](qt6-win-amd64-win11-vmware-20261030.json) |
| `qt4-win-i386` | Windows XP SP3 | PASS | 8 / 0 | 370 / 0 / 129 | [json](qt4-win-i386-xp-sp3-vmware-20261030.json) |
| `qt5-win-i386` | Windows XP SP3 | PASS | 8 / 0 | 478 / 0 / 97 | [json](qt5-win-i386-xp-sp3-vmware-20261030.json) |
| `qt6-win-amd64` | Windows 7 SP1 x64 | PASS | 8 / 0 | 508 / 0 / 56 | [json](qt6-win-amd64-win7-vmware-20261030.json) |
| `qt5-win-amd64` | Windows 7 SP1 x64 | PASS | 8 / 0 | 500 / 0 / 88 | [json](qt5-win-amd64-win7-vmware-20261030.json) |
| `qt5-win-i386` | Windows 7 SP1 x64 | PASS | 8 / 0 | 500 / 0 / 88 | [json](qt5-win-i386-win7-vmware-20261030.json) |
| `qt4-win-amd64` | Windows 7 SP1 x64 | PASS | 8 / 0 | 373 / 0 / 124 | [json](qt4-win-amd64-win7-vmware-20261030.json) |
| `qt4-win-i386` | Windows 7 SP1 x64 | PASS | 8 / 0 | 375 / 0 / 124 | [json](qt4-win-i386-win7-vmware-20261030.json) |
| `qt5-macos-amd64` | Mac OS X 10.6.3 | PASS | 8 / 0 | 494 / 0 / 87 | [json](qt5-macos-amd64-snowleopard-vmware-20261030.json) |
| `qt5-macos-i386` | Mac OS X 10.6.3 | PASS | 8 / 0 | 494 / 0 / 87 | [json](qt5-macos-i386-snowleopard-vmware-20261030.json) |
| `qt4-macos-i386` | Mac OS X 10.6.3 | PASS | 8 / 0 | 366 / 0 / 129 | [json](qt4-macos-i386-snowleopard-vmware-20261030.json) |
| `qt5-macos-amd64` | OS X 10.7.5 | PASS | 8 / 0 | 496 / 0 / 85 | [json](qt5-macos-amd64-lion-vmware-20261030.json) |
| `qt5-macos-i386` | OS X 10.7.5 | PASS | 8 / 0 | 496 / 0 / 85 | [json](qt5-macos-i386-lion-vmware-20261030.json) |
| `qt4-macos-i386` | OS X 10.7.5 | PASS | 8 / 0 | 366 / 0 / 129 | [json](qt4-macos-i386-lion-vmware-20261030.json) |
| `qt6-macos-amd64` | macOS 10.13.6 | PASS | 8 / 0 | 505 / 0 / 56 | [json](qt6-macos-amd64-highsierra-vmware-20261030.json) |
| `qt5-macos-amd64` | macOS 10.13.6 | PASS | 8 / 0 | 497 / 0 / 84 | [json](qt5-macos-amd64-highsierra-vmware-20261030.json) |
| `qt5-macos-i386` | macOS 10.13.6 | PASS | 8 / 0 | 497 / 0 / 84 | [json](qt5-macos-i386-highsierra-vmware-20261030.json) |
| `qt4-macos-i386` | macOS 10.13.6 | PASS | 8 / 0 | 369 / 0 / 126 | [json](qt4-macos-i386-highsierra-vmware-20261030.json) |

## Evidence

Each run uses a new guest directory so previous reports cannot be mistaken
for the new result. Windows executables are checked against the current
manifest before copying, then all nine are read back from the guest and
checked by SHA256. macOS suites are transferred over SSH and verified
by SHA256 inside the guest before execution. Qt 4 macOS bundles retain
their original binaries and resources; their source archive is checked
against `build-inputs.json`.

High Sierra uses the lab's two-stage OpenCore startup: single-user mode
(`-s`), then `exit` to start the graphical session after device setup.
The VM system disk remained the same.

Local logs, per-application output, system information and runtime JSON
are in the following directories under `build/runs/`:

- `release-20261030-qt4-win-i386-windows-11/`
- `release-20261030-qt4-win-amd64-windows-11/`
- `release-20261030-qt5-win-i386-windows-11/`
- `release-20261030-qt5-win-amd64-windows-11/`
- `release-20261030-qt6-win-amd64-windows-11/`
- `release-20261030-qt4-win-i386-windows-xp/`
- `release-20261030-qt5-win-i386-windows-xp/`
- `release-20261030-qt6-win-amd64-windows-7/`
- `release-20261030-qt5-win-amd64-windows-7/`
- `release-20261030-qt5-win-i386-windows-7/`
- `release-20261030-qt4-win-amd64-windows-7/`
- `release-20261030-qt4-win-i386-windows-7/`
- `release-20261030-qt5-macos-amd64-snow-leopard/`
- `release-20261030-qt5-macos-i386-snow-leopard/`
- `release-20261030-qt4-macos-i386-snow-leopard/`
- `release-20261030-qt5-macos-amd64-lion/`
- `release-20261030-qt5-macos-i386-lion/`
- `release-20261030-qt4-macos-i386-lion/`
- `release-20261030-qt6-macos-amd64-highsierra/`
- `release-20261030-qt5-macos-amd64-highsierra/`
- `release-20261030-qt5-macos-i386-highsierra/`
- `release-20261030-qt4-macos-i386-highsierra/`

## Scope

This report records only completed runs. Windows ARM64 and Apple
silicon require matching guests or hardware and are not represented
by x86 VM runs. Qt 4 PowerPC was not rerun: Snow Leopard has no
Rosetta translator installed; its older QEMU records remain.
The Qt 4 NT4 investigation is separate from this
Windows XP/7/11 and macOS validation.
