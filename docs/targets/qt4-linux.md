# Qt 4.8.7 for Linux

| Target | Image | Floor |
|--------|-------|-------|
| `make qt4-linux-i386` | `qt4-linux-i386` | Debian 3.1 Sarge i386 (2005): glibc 2.3.2, XFree86 4.3 |
| `make qt4-linux-amd64` | `qt4-linux-amd64` | Debian 3.1 Sarge amd64 (the unofficial port): glibc 2.3.2 |

Both are the same build, `docker/qt4/linux/i386` and `amd64`.
`make qt4-extract-tests QT4_IMAGE=qt4-linux-i386` builds the test suite with
qmake, checks every ELF file (class and machine, no symbol newer than
`GLIBC_2.3.2`, every dependency resolved through Sarge's own loader inside
the Sarge root) and publishes it in `artifacts/tests-qt4-linux-i386/`.

## How it is built

The compiler is Ubuntu 16.04's GCC 5 (i386 or amd64 image); every header and
library it links against comes from the pinned Sarge packages
(`scripts/fetch/locks/qt4-sarge-<arch>-packages.json`, fetched by
`scripts/fetch/qt4-sarge-fetch.py`). The amd64 packages come from the
archived unofficial port (`archive.debian.org/debian-amd64`); its index lists
MD5 sums only, so `scripts/fetch/qt4-sarge-lock.py` checks each package
against it and records its SHA256. The build then:

- rebuilds libstdc++ from GCC 5.5 against Sarge's glibc and links it
  statically, with libgcc (no newer C++ runtime is needed on the target);
- builds OpenSSL 1.0.2u statically;
- builds Qt with a mkspec (`linux-sarge-<arch>-g++`) whose compiler wrappers
  point at the sysroot, with `-std=gnu89` for glibc 2.3's inline semantics,
  SysV hashes, no stack protector and no `STB_GNU_UNIQUE` symbols, and
  `QT_NO_LINUX_FUTEX` for Sarge's kernels.

Applications built with the image get the same mkspec through `QMAKESPEC`.
The X11 client is Xlib (Qt 4 has no xcb backend); OpenGL, fontconfig,
FreeType, Xrender, Xrandr, Xinerama and the X input extension are used when
the target has them.

## Results

The i386 build passes the current suite 8/8 (361 checks) with Sarge's own
libraries and kernel 2.6.8 in QEMU; with the earlier 24-application layout it
also passed on a Sarge Xfce desktop, and on Ubuntu 16.04 to 24.04, Debian 13
and Fedora 44 in containers ([platforms](../platforms.md#qt-487)).
The amd64 build passed 8/8 (362 checks) on CentOS 5.11 x86_64, glibc 2.5, and
on Debian 4.0 etch amd64, glibc 2.3.6, both in QEMU, and 8/8 on Debian 13 in a
container. On etch it needed `patches/qt4/linux/03`: that X server loses a
large GL window's frame when the current context is bound to it again, as
`grabFrameBuffer()` did.

## Limits

- Current distributions ship fewer i386 libraries each year; Arch has none by
  default.
- Sarge amd64 was never an official Debian release; its X.Org is the
  `4.3.0.dfsg.1-14sarge3` of the port (the i386 build uses `-14sarge7`).
