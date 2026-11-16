# Qt 5.15.19 for Linux

| Target | Image | Floor |
|--------|-------|-------|
| `make qt5-linux-amd64` | `qt5-linux-amd64-llvm21` | Ubuntu 10.04 Lucid amd64: glibc 2.11, libxcb 1.5, libX11 1.3 |
| `make qt5-linux-i386` | `qt5-linux-i386-llvm21` | Ubuntu 10.04 Lucid i386 |
| `make qt5-linux-arm64` | `qt5-linux-arm64-llvm21` | Ubuntu 14.04 arm64: glibc 2.19 |

One build per architecture, from Qt 4.8's Linux floor.

## How the Lucid build works

amd64 and i386 share [one Dockerfile](../../docker/qt5/linux/Dockerfile).
It reconstructs both sysroots from the pinned Lucid package lists in
`scripts/fetch/locks`. The Xenial stages build the X libraries, optional
stubs and OpenSSL with the legacy compiler. Qt and the examples use
Clang, LLD and the static LLVM runtimes built against each sysroot.

- the xcb libraries Qt's xcb plugin needs beyond Lucid's (the xcb-util
  family and xkbcommon 0.7.2; XInput is Qt's bundled copy) are built
  statically over Lucid's own libxcb 1.5, with a small compatibility layer
  for the five libxcb functions newer than 1.5 (`scripts/build/qt5-lucid`);
- `patches/qt5/linux` adds run-time fallbacks in the xcb plugin:
  `xcb_poll_for_queued_event` is looked up with `dlsym` (libxcb 1.8), and
  without libX11-xcb (not on a stock Lucid) the plugin opens a plain xcb
  connection and reports OpenGL unavailable, so Qt Quick uses its software
  renderer; with `libx11-xcb1` installed Xlib and GLX are used as usual;
- OpenSSL 3.5.7 is linked statically; D-Bus is loaded at run time;
- Wayland, ALSA, PulseAudio, GStreamer 1.0, speech-dispatcher and BlueZ are
  compiled against Ubuntu 16.04's headers and linked to stub archives
  (`scripts/build/dlopen`) that load the libraries on first use, so the
  binaries need none of them. Where one is missing, Qt finds no Wayland
  display (and uses xcb), no audio device, no media backend, no speech engine
  or no Bluetooth adapter; `patches/qt5/linux/04` keeps the GStreamer
  services from starting when GStreamer cannot be initialized.

## amd64 with LLVM 21.1.8

The amd64 build uses the static compiler-rt, libunwind, libc++abi and
libc++ built against the Ubuntu 10.04 sysroot. Its examples compile
in required C++23 mode.

Make stages the pinned archives under `downloads/` and prepares the
shared LLVM compiler. From the repository root, run:

```sh
make qt5-linux-amd64-examples PARALLEL_JOBS=4
```

Use `make qt5-linux-amd64` for the SDK alone. The local image is
`qt5-linux-amd64-llvm21`, with the SDK at `/opt/qt5-linux-amd64-llvm`
and its CMake toolchain at `/opt/llvm-runtime-lucid/toolchain.cmake`.
The examples target extracts the binaries to
`artifacts/tests-qt5-linux-amd64-llvm21/`.

The local staged SDK build passed all 25 required C++23 checks and all
seven GUI examples under Ubuntu's 2.6.32 kernel and Lucid userland in QEMU.
The [run record](../results/qt5-linux-amd64-llvm21-lucid-20261111.md) describes the display setup
and the scope of the run.

## i386 with LLVM 21.1.8

The i386 profile shares the [Lucid build recipe](#amd64-with-llvm-2118).
It builds the i386 sysroot and OpenSSL in separate stages.
The host uses the amd64 compiler and Wayland scanner. The LLVM
runtimes and all target Qt libraries are built for i686 against glibc 2.11.
The i386 FreeType header keeps its original assembly constraints and
omits the obsolete `register` specifier on the output variable.

With the same pinned sources and compiler staged, run:

```sh
make qt5-linux-i386-examples PARALLEL_JOBS=4
```

The SDK alone is `make qt5-linux-i386`. It installs to
`/opt/qt5-linux-i386-llvm` in `qt5-linux-i386-llvm21`. The examples go to
`artifacts/tests-qt5-linux-i386-llvm21/`. The staged and clean repository
builds both passed all 25 required C++23 checks and all seven GUI examples
under Ubuntu's 32-bit 2.6.32 kernel and Lucid userland in QEMU.
The [run record](../results/qt5-linux-i386-llvm21-lucid-20261111.md) describes the display setup
and the scope of the run.

## arm64 with LLVM 21.1.8

The [Trusty Dockerfile](../../docker/qt5/linux/arm64/Dockerfile)
prepares the Ubuntu 14.04 sysroot, X libraries and OpenSSL in separate
stages. The common ARM64 runtime is built at the CentOS 7 glibc 2.17
floor. Debian 12 builds the native qmake and moc. Target Qt libraries
build with upstream Clang in C++14 mode, and the examples use C++23.

```sh
make qt5-linux-arm64-examples PARALLEL_JOBS=4
```

Use `make qt5-linux-arm64` for the SDK alone. It installs to
`/opt/qt5-linux-arm64-llvm` in `qt5-linux-arm64-llvm21`. The
CMake toolchain is `/opt/qt5-llvm/toolchain.cmake`; the examples
go to `artifacts/tests-qt5-linux-arm64-llvm21/`. The
[previous run record](../results/qt5-linux-arm64-llvm21-sdk-20261111.md)
includes the Ubuntu 14.04 runtime commands.

The [Trusty migration record](../results/qt5-linux-arm64-llvm-migration-20261115.json)
records all eight ordinary applications and the 25 required C++23
checks with zero skips. The ordinary QtScript function call passes
with the same tagged call frame fix used by the Windows XP profiles.

## Lucid migration validation

Both SDKs built through the standard Make targets and ran on Ubuntu
10.04 with the 2.6.32-38 kernel in QEMU. Each passed all eight ordinary
applications and 25/25 required C++23 checks with zero skips. All nine
executables on each architecture matched the build manifest in the
guest. The ELF audit found glibc symbol requirements through 2.10.

The GUI examples use XCB against Debian 12 Xvfb with GLX disabled.
The ordinary console runs on the offscreen platform with GLX disabled,
a tmpfs root and local hostname resolution. Those fixture settings let
the console exercise QStorageInfo and loopback networking. See the
[Lucid migration record](../results/qt5-linux-lucid-llvm-migration-20261115.json).

## Results

amd64: 8/8 (498 checks) on Ubuntu 10.04.4 in VMware; 8/8 (511) on CentOS 7 and
Debian 13 in containers, 513 on Debian 13 with GStreamer, PulseAudio,
speech-dispatcher and BlueZ installed (the media player then gets its
GStreamer backend); earlier also on Ubuntu 16.04 and 24.04, Fedora and Arch.
i386: 8/8 (494, 509 and 510) on Ubuntu 10.04 i386 itself, Ubuntu 16.04 i386
and Debian 12 i386 in containers. arm64: 8/8 (510 and 511 checks) on Ubuntu
14.04 and Debian 12 arm64 in emulated containers. See
[platforms](../platforms.md#qt-51519).

## Limits

- OpenGL on Lucid needs an X server with GLX 1.3. In VMware, Lucid's server
  reports GLX 1.2 (software rendering through the non-DRI `vmware` driver),
  so the suite's GL checks skip there; Lucid on hardware with DRI2 drivers
  reports GLX 1.4 but has not been measured.
- The 64-bit Lucid binaries cannot run in Docker Desktop's WSL2 kernel
  (glibc 2.11 needs the vsyscall page); newer distributions run them fine.
- Not built: the unreleased QtHttpServer and QtMqtt. GStreamer's GL and
  photography interfaces (gst-plugins-bad) are left out.
- Wayland needs libwayland 1.12 or newer, the version the stubs are made
  from. An older one (14.04's 1.4, say) counts as missing: Qt uses xcb, and
  `QT_QPA_PLATFORM=wayland` reports that no Wayland display is available.
- arm64 has run only in emulated containers, not on hardware.
