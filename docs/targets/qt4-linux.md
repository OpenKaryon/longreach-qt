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

## i386 with LLVM 21.1.8

The opt-in LLVM build uses upstream Clang and static libc++, libc++abi,
libunwind and compiler-rt. Build tools run on Linux amd64. The existing
Sarge SDK image supplies the pinned i386 sysroot, OpenSSL 1.0.2u and two
GCC startup objects. GNU ld handles the old glibc archive's linkonce
sections and emits a SysV ELF hash for the Sarge loader.

Stage the LLVM 21.1.8 source archive and compiler image using the
[LLVM compiler instructions](qt6-llvm-probes.md), and have
`qt4-linux-i386:latest` available. Then run these commands in order:

```sh
make qt4-linux-i386-llvm-examples PARALLEL_JOBS=3
make qt4-linux-i386-llvm-qemu
```

The first command builds the SDK in `qt4-linux-i386:llvm21`, exports the
ordinary examples and strict C++23 selftest to
`artifacts/tests-qt4-linux-i386-llvm21/bin/`, and audits them with the
Sarge loader. Use `make qt4-linux-i386-llvm` for the SDK alone.
The QEMU target uses the Sarge kernel packages staged under
`downloads/debian-sarge-kernel/` and a Linux image with Python 3 and
`qemu-system-i386`. Set `QT4_SARGE_LLVM_QEMU` to use a different local
QEMU image. The serial log and strict C++23 log are written next to the
binaries.

See the [LLVM build and QEMU result](../results/qt4-linux-i386-sarge-llvm21-20261113.md)
for the CPU floor, runtime changes and test scope.

## amd64 with LLVM 21.1.8

Both architectures use `docker/qt4/linux/Dockerfile-llvm`. The amd64
build uses the unofficial Sarge amd64 sysroot. The two locale-aware
integer conversions in libc++ use the older symbols that the sysroot
exports at `GLIBC_2.2.5`. This keeps the final ABI ceiling at
`GLIBC_2.3.2`.

With the compiler inputs above, `qt4-linux-amd64:latest`, and a local
QEMU runner image available, run the commands in order:

```sh
python scripts/fetch/qt4-sarge-fetch.py --arch amd64 --vm
make qt4-linux-amd64-llvm-probe PARALLEL_JOBS=3
make qt4-linux-amd64-llvm-examples PARALLEL_JOBS=3
make qt4-linux-amd64-llvm-qemu
```

The probe target builds only the LLVM runtime and standalone test, then
runs all 25 required checks in QEMU. To reuse the Debian 12 tools image
from the Lucid probe, set
`QT4_SARGE_LLVM_HOST=qt5-linux-i386:llvm21-lucid-probe-inputs`.
The probe writes its logs under
`artifacts/tests-qt4-linux-amd64-llvm21/probe/`.

The runner boots the pinned Sarge amd64 kernel in QEMU with an explicit
low-memory map. The original kernel fails during page-table setup with
the default modern QEMU memory map. The output directory is
`artifacts/tests-qt4-linux-amd64-llvm21/`.

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
