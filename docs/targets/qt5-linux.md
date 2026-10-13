# Qt 5.15.19 for Linux

| Target | Image | Floor |
|--------|-------|-------|
| `make qt5-linux-amd64` | `qt5-linux-amd64-<profile>` | Ubuntu 10.04 Lucid amd64: glibc 2.11, libxcb 1.5, libX11 1.3 |
| `make qt5-linux-i386` | `qt5-linux-i386-<profile>` | Ubuntu 10.04 Lucid i386 |
| `make qt5-linux-arm64` | `qt5-linux-arm64-<profile>` | Ubuntu 16.04 arm64 |

One build per architecture, from Qt 4.8's Linux floor.

## How the Lucid build works

amd64 and i386 are the same build, `docker/qt5/linux/amd64` and `i386`. The compiler is
Ubuntu 16.04's GCC 5.4 (the amd64 or the i386 image); headers and libraries
come from the pinned Lucid packages
(`scripts/fetch/locks/qt5-lucid-<arch>-packages.json`). On top of that:

- libstdc++ is rebuilt from GCC 5.5 against glibc 2.11 and linked statically;
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

## Results

amd64: 8/8 (498 checks) on Ubuntu 10.04.4 in VMware; 8/8 (511) on CentOS 7 and
Debian 13 in containers, 513 on Debian 13 with GStreamer, PulseAudio,
speech-dispatcher and BlueZ installed (the media player then gets its
GStreamer backend); earlier also on Ubuntu 16.04 and 24.04, Fedora and Arch.
i386: 8/8 (494, 509 and 510) on Ubuntu 10.04 i386 itself, Ubuntu 16.04 i386
and Debian 12 i386 in containers. arm64: 8/8 (510 checks) on Ubuntu
16.04 arm64 in an emulated container. See
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
- The Wayland platform needs libwayland 1.11 or newer at run time. The stubs
  load an older one too and leave its missing functions returning 0, so
  `QT_QPA_PLATFORM=wayland` crashes there (14.04's 1.4, say); the default,
  xcb, is not affected, and systems that old have X11 sessions anyway.
- The arm64 build is native under emulation (several hours) and links the
  Wayland client libraries dynamically; its floor is to move to Ubuntu 14.04
  the way Lucid did for amd64.
