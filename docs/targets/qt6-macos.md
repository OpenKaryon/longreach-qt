# Qt 6.8.4 for macOS

| Target | Image | Floor |
|--------|-------|-------|
| `make qt6-macos-amd64` | `qt6-macos-amd64-<profile>` | macOS 10.13 High Sierra, x86_64 |
| `make qt6-macos-arm64` | `qt6-macos-arm64-<profile>` | macOS 11.0, Apple silicon |

Both cross-build with osxcross and the 14.0 SDK (pinned) and need the
host-tools image (`make qt6-host`). Qt 6.8 itself starts at macOS 12.
`QT6_MACOS_DEPLOYMENT_TARGET` and `QT6_MACOS_ARM64_DEPLOYMENT_TARGET` select
other targets; the patches guard on the target themselves.

10.13 rather than 10.14 because some Macs that run 10.13 (the mid-2010
MacBook Pro, for one) cannot get 10.14.

## Down to 10.13 and 11.0

`patches/qt6/macos`:

| Below | What changes |
|-------|--------------|
| 12 | IOKit's main port is `MACH_PORT_NULL`; no safe-area insets; CoreVideo attachments the older way |
| 10.15 | OpenXR uses its POSIX file system code; camera without Metal-backed formats |
| 10.14 | QtCore provides the C++17 aligned new/delete libc++ lacks (built with `-faligned-allocation`); file system, icon, key map, UTI, drag and capture-permission fallbacks; the QML JIT retries `mmap` without an address hint and then without `MAP_JIT`, both of which 10.13 rejects with EINVAL |
| 10.12 | no os_activity scopes or unified logging |

## Results

macOS 10.13.6 in VMware: 7/7 built applications, 240 checks, none failed,
with the QML JIT fix ([platforms](../platforms.md#qt-684)); `qt-selftest`
was not built for that image (it lacked QtTextToSpeech). arm64 is built and
audited (`make qt6-macos-arm64-audit`: every binary declares 11.0), not run.

## Limits

- Real High Sierra hardware and Apple silicon have not run the builds.
- 144 uses of newer APIs reported by the availability audit
  (`scripts/audit/qt6-macos-availability-report.py`) remain to be reviewed;
  the suite exercises the ones it reaches.
