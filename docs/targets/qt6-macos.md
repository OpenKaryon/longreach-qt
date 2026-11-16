# Qt 6.8.5 for macOS

| Target | Image | Floor |
|--------|-------|-------|
| `make qt6-macos-amd64` | `qt6-macos-amd64-llvm21` | macOS 10.13 High Sierra, x86_64 |
| `make qt6-macos-arm64` | `qt6-macos-arm64` | macOS 11.0, Apple silicon |

Both cross-build with osxcross and the pinned 14.0 Apple SDK. The
Intel target builds Qt with upstream LLVM 21.1.8 and uses native Qt
tools from the amd64 Linux LLVM SDK. ARM64 continues to use
`qt6-host`. Qt 6.8 itself starts at macOS 12.

For a sequential Intel build, prepare the host with `make qt6-llvm-cross-host`
and prepare osxcross with `make qt6-macos-amd64-osxcross`. The
coordinator reads both local images with its network disabled.
`QT6_MACOS_DEPLOYMENT_TARGET` and `QT6_MACOS_ARM64_DEPLOYMENT_TARGET` select
other targets; the patches guard on the target themselves.

10.13 rather than 10.14 because some Macs that run 10.13 (the mid-2010
MacBook Pro, for one) cannot get 10.14.

## Down to 10.13 and 11.0

`patches/qt6/macos`:

| Below | What changes |
|-------|--------------|
| 12 | IOKit's main port is `MACH_PORT_NULL`; no safe-area insets; CoreVideo attachments the older way |
| 11 | Metal pipelines without the binary archive; the save dialog's Replace button is not marked destructive |
| 10.15 | OpenXR uses its POSIX file system code; camera without Metal-backed formats; Metal reports no GPU time and takes the device type from `isRemovable`/`isLowPower`; text-to-speech cannot synthesize to audio |
| 10.14 | text-to-speech reports an error (no `AVSpeechSynthesizer`); QtCore provides the C++17 aligned new/delete libc++ lacks (built with `-faligned-allocation`); file system, icon, key map, UTI, drag and capture-permission fallbacks; the QML JIT retries `mmap` without an address hint and then without `MAP_JIT`, both of which 10.13 rejects with EINVAL |
| 10.12 | no os_activity scopes or unified logging |

## LLVM migration results

The rebuilt amd64 SDK passed the Mach-O audit for macOS 10.13 on all
nine executables. In the clean High Sierra 10.13.6 VMware guest, all
eight ordinary applications passed (529 checks, 57 optional skips).
The strict C++23 run passed all 25 checks without skips. See the
[migration report](../results/qt6-macos-amd64-llvm-migration-20261116.json)
for the build references and artifact hashes.

## Previous runtime results

macOS 10.13.6 in VMware, installed clean from the 10.13.6 installer, with
Qt 6.8.5 with the security patches: 8/8, 505 checks, none failed
([platforms](../platforms.md#qt-685)). arm64 builds
all 8 applications and is audited (`make qt6-macos-arm64-audit`: every
binary declares 11.0), not run.

## Limits

- Real High Sierra hardware and Apple silicon have not run the builds.
- The availability audit (`scripts/audit/qt6-macos-availability-report.py`)
  of Qt 6.8.4 reported 144 uses of APIs newer than 10.13 without an `@available` check.
  All were reviewed: the ones that would fail at run time (Metal, the save
  dialog, text-to-speech) are guarded by `patches/qt6/macos/18`, which leaves
  123; those are enum values and types, calls reached only through an object
  a guarded call creates, or checks Clang does not recognize
  (`respondsToSelector:`, Qt's Apple-GPU capability). The VMware guest has no
  Metal device, so the Metal guards are built and reviewed, not run.
