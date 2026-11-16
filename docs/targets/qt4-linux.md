# Qt 4.8.7 for Linux

| SDK target | Image | Minimum guest |
|---|---|---|
| `make qt4-linux-i386` | `qt4-linux-i386-llvm21` | Debian 3.1 Sarge i386, Pentium III, glibc 2.3.2 |
| `make qt4-linux-amd64` | `qt4-linux-amd64-llvm21` | Debian 3.1 Sarge amd64 port, glibc 2.3.2 |

Both targets use [one Dockerfile](../../docker/qt4/linux/Dockerfile)
and build with upstream Clang 21.1.8 and static libc++, libc++abi, libunwind
and compiler-rt. The build host is Linux amd64 for both targets.

## Build and test

Make prepares the shared LLVM compiler as a prerequisite.
The Sarge recipes assemble their sysroots from the architecture's locked
Sarge packages. They use two startup objects from a pinned Ubuntu
`libgcc-5-dev` package, construct static OpenSSL 1.0.2u with Clang, and
use GNU ld for the Sarge archive's linkonce sections and SysV ELF hashes.
The standalone `qt4-sarge-<arch>-inputs` image contains the sysroot and
host utilities for the ELF audit and QEMU initramfs.

```sh
make -j2 qt4-linux-i386-examples qt4-linux-amd64-examples PARALLEL_JOBS=3
make qt4-linux-i386-qemu
make qt4-linux-amd64-qemu
```

The examples targets build the SDKs and export each suite into
`artifacts/tests-qt4-linux-<arch>-llvm21/`. Use the SDK commands in the
table to build just Qt. The audit checks every exported ELF against
`GLIBC_2.3.2` and resolves its libraries with the Sarge loader. The
QEMU targets run the eight ordinary applications and a separate
strict C++23 selftest with 25 required checks and zero skips.

Set `QT4_SARGE_QEMU` to select a local Linux image with Python 3 and
`qemu-system-i386` or `qemu-system-x86_64`. The runner stages the pinned
kernel and utilities in the matching Sarge download directory and
writes `qemu.log` and `cxx23.log` alongside the binaries. The Sarge
amd64 kernel boots with an explicit low-memory map. The i386 guest
uses a Pentium III CPU.

The `qt4-linux-<arch>-llvm*` target names remain aliases for the same
LLVM recipes. GCC build instructions and recipes are available under
the `v0.2.2` tag.

## Sarge migration validation

The shared Dockerfile built both SDKs and their examples with the new
CentOS 7 LLVM 21.1.8 bootstrap. Both sysroots came from the package locks.
Their `crtbegin.o` and `crtend.o` matched the earlier SDK objects byte
for byte. The Qt target libraries and static OpenSSL were rebuilt with
Clang. The example builds ran concurrently, three compile jobs per target.
The QEMU guests ran in sequence.

| Target | Ordinary applications | Ordinary checks | Strict C++23 | ELF ABI ceiling |
|---|---|---|---|---|
| Sarge i386 | 8/8 | 363 passed, 0 failed, 157 skipped | 25/25, 0 skips | `GLIBC_2.3.2` |
| Sarge amd64 | 8/8 | 363 passed, 0 failed, 157 skipped | 25/25, 0 skips | `GLIBC_2.3.2` |

The ELF audit covered 10 binaries per target, including the runner and
the strict Qt selftest. The [JSON record](../results/qt4-linux-sarge-llvm-migration-20261115.json)
contains the image IDs, per-application counts, and binary and log hashes.

## Earlier results

- [i386 LLVM build and QEMU run](../results/qt4-linux-i386-sarge-llvm21-20261113.md)
- [amd64 LLVM build and QEMU run](../results/qt4-linux-amd64-sarge-llvm21-20261113.md)
- [Platform matrix](../platforms.md#qt-487)
