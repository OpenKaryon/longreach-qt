# Qt 6.8.5 for Linux

| Target | Image | Floor |
|--------|-------|-------|
| `make qt6-linux-amd64` | `qt6-linux-amd64` | RHEL/CentOS 7.6: glibc 2.17 |
| `make qt6-linux-arm64` | `qt6-linux-arm64` | RHEL/CentOS 7 aarch64: glibc 2.17 |

One build per architecture. Both reach Qt 5.15's floor (RHEL 7); Qt's own
Linux binaries need glibc 2.28.

It is built on CentOS 7 with devtoolset-11's GCC 11, CentOS 7's glibc and a
static libstdc++; OpenSSL 3 is linked statically; FreeType is bundled and
`patches/qt6/all` makes Qt find system fonts without fontconfig, survive a
missing D-Bus session bus, and link the legacy `libGL.so.1` rather than
GLVND's `libOpenGL.so.0`, which old distributions lack. QtWayland links
libwayland through stubs that load it at run time (`scripts/build/dlopen`), so
the binaries also start where it is not installed, as on a RHEL 7 server;
a libwayland older than RHEL 7's 1.15 counts as missing, and Qt uses xcb.

The arm64 build is cross-built on Debian 12 with its aarch64 GCC 11 against a
sysroot of CentOS 7.9 aarch64 packages (`scripts/build/rpm-sysroot.py`) and
Developer Toolset 10's C++ library, linked the way Developer Toolset links
it: RHEL 7's `libstdc++.so.6` plus the newer parts statically. CentOS 7's own
wayland-scanner runs under QEMU, so the generated code calls only what
libwayland 1.15 has. The host tools come from the qt6-host image.

`make qt6-linux-amd64-examples` builds the test suite against the SDK and runs it
under Xvfb in the build image; `scripts/run/run.py --host docker:<distro>`
runs the extracted suite on stock distributions.

## Results

8/8 (508 checks) on stock CentOS 7.6 and 8/8 on Linux Mint 22.3 in VMware;
with QtWayland, 8/8 (528) on CentOS 7 and Debian 13 in containers, the live
Wayland client check included
([platforms](../platforms.md#qt-684)). arm64: 8/8 (528 checks, QtWayland
included) on stock CentOS 7 and Debian 12 arm64 in emulated containers.

## Limits

- QtWebEngine and QtWebView are not built.
- arm64 has run only in emulated containers, not on hardware.
