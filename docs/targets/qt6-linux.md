# Qt 6.8.4 for Linux

| Target | Image | Floor |
|--------|-------|-------|
| `make qt6-linux-amd64` | `qt6-linux-amd64-<profile>` | RHEL/CentOS 7.6: glibc 2.17 |
| `make qt6-linux-arm64` | `qt6-linux-arm64-<profile>` | Debian 12 arm64 |

One build per architecture. The amd64 build reaches Qt 5.15's floor (RHEL 7);
Qt's own Linux binaries need glibc 2.28.

It is built on CentOS 7 with devtoolset-11's GCC 11, CentOS 7's glibc and a
static libstdc++; OpenSSL 3 is linked statically; FreeType is bundled and
`patches/qt6/all` makes Qt find system fonts without fontconfig, survive a
missing D-Bus session bus, and link the legacy `libGL.so.1` rather than
GLVND's `libOpenGL.so.0`, which old distributions lack.

`make qt6-linux-amd64-smoke` builds the test suite against the SDK and runs it
under Xvfb in the build image; `scripts/run/run.py --host docker:<distro>`
runs the extracted suite on stock distributions.

## Results

8/8 (508 checks) on stock CentOS 7.6 and 8/8 on Linux Mint 22.3 in VMware
([platforms](../platforms.md#qt-684)). arm64 is built, not run.

## Limits

- QtWayland, QtWebEngine and QtWebView are not built.
- The arm64 floor is to move to CentOS 7 aarch64 like amd64.
