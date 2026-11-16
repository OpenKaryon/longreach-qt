# Qt 6.8.5 for Linux

| Target | Image | Floor |
|--------|-------|-------|
| `make qt6-linux-amd64` | `qt6-linux-amd64-llvm21` | RHEL/CentOS 7.6: glibc 2.17 |
| `make qt6-linux-arm64` | `qt6-linux-arm64-llvm21` | RHEL/CentOS 7 aarch64: glibc 2.17 |

One build per architecture. Both reach Qt 5.15's floor (RHEL 7); Qt's own
Linux binaries need glibc 2.28.

Both targets use upstream Clang/LLD 21.1.8 and static LLVM C++ runtimes.
The amd64 [build guide](qt6-linux-llvm.md) covers the locked CentOS inputs
and the native compiler. ARM64 cross-builds on Debian 12 against a
CentOS 7.9 aarch64 sysroot built from pinned RPMs. Its host Qt tools come
from the amd64 LLVM SDK. CentOS 7's Wayland scanner runs under QEMU so
the generated code works with Wayland 1.15.

OpenSSL 3 is linked statically. QtWayland uses the kit's dlopen stubs
and can start on a system without libwayland. The common patches cover
fonts, the D-Bus session bus and the older OpenGL library names.

For the ARM64 coordinator, first run `make qt6-linux-arm64-cross-deps`
and build the amd64 LLVM SDK. The coordinator's `inputs` phase assembles
the local images with its network disabled.

`make qt6-linux-amd64-examples` builds the test suite against the SDK and runs it
under Xvfb in the build image; `scripts/run/run.py --host docker:<distro>`
runs the extracted suite on stock distributions.

## LLVM migration validation

The rebuilt AMD64 suite passed all eight applications and the separate
strict C++23 gate on Debian 13 and CentOS 7. All nine binaries stayed
within GLIBC 2.17. See the
[AMD64 migration record](../results/qt6-linux-amd64-llvm-migration-20261115.json).

The rebuilt ARM64 suite also passed all eight applications and strict
C++23 25/25 on CentOS 7 and Debian 12 under QEMU. Its nine binaries
stay within GLIBC 2.17. See the
[ARM64 migration record](../results/qt6-linux-arm64-llvm-migration-20261115.json).

## Previous runtime results

8/8 (508 checks) on stock CentOS 7.6 and 8/8 on Linux Mint 22.3 in VMware;
with QtWayland, 8/8 (528) on CentOS 7 and Debian 13 in containers, the live
Wayland client check included
([platforms](../platforms.md#qt-685)). arm64: 8/8 (528 checks, QtWayland
included) on stock CentOS 7 and Debian 12 arm64 in emulated containers.

## Limits

- QtWebEngine and QtWebView are not built.
- arm64 has run only in emulated containers, not on hardware.
