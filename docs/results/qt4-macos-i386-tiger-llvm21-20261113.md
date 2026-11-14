# Qt 4 Tiger i386 LLVM 21.1.8 runtime probe

The standalone C++23 probe ran on Mac OS X 10.4.10 (8R3032) in QEMU
with the Core Duo CPU model. It reported Clang 21.1.8, libc++ 210108
and `__cplusplus=202302`. All 25 required checks passed, with zero
failures or skips and exit code 0. These include `std::jthread`,
`std::stop_token`, thread-local destruction, exception unwinding,
Unicode filesystem paths and Unicode print output.

The trial built static libc++ and libc++abi against the Mac OS X 10.4u
SDK. It reused the legacy Darwin clocks and emulated TLS from the Snow
Leopard build. The Tiger SDK has no `posix_memalign` or `copyfile.h`.
The trial used an aligned allocation backed by `malloc` and libc++'s
existing stream-based file copy path. The Mach-O probe links the system
`libSystem.B.dylib` and `libgcc_s.1.dylib` for the OS and unwinder.

Probe SHA-256 is
`83a7ba719ee849fce8587534e0e3b93461412b1d664ccd80cd854c35932d6835`.
The executable on the VM's mounted FAT volume also matched the host
SHA-1, `10458b3f5f3ef7156702ceb66fffa79386f782dd`.

## Qt SDK trial

The full Carbon Qt 4.8.7 SDK built with Clang 21.1.8 and the Tiger
runtime. Its host qmake reports version 2.01a and Qt 4.8.7. All 36 static
archive paths match the existing Tiger SDK. The trial uses the legacy
Darwin linker and the existing OpenSSL 1.0.2u archives.

For Clang 21, the trial used ISO `math.h` in bundled libpng, defined the
QtXmlPatterns background mask with unsigned arithmetic and called
JavaScriptCore's Darwin `ceil` compatibility function explicitly.
The explicit calls retain its signed-zero workaround without defining
a macro that also rewrites libc++'s internal `ceil` calls.

The hashes below are from local trial recipes. The repository recipe
now carries these source changes in the Tiger LLVM Make targets. The clean
repository build is recorded below. Its guest rerun is pending.

Both example packages built successfully. The Mach-O audit accepted
all nine ordinary bundles, including the runner, and the separate
strict Qt selftest bundle. The minimum OS recorded in the strict
executable is 10.4.0. Both archives matched their host SHA-1 after
transfer to the VM.

| Archive | SHA-256 |
|---|---|
| Ordinary example suite | `dbdde03e79f6540e0311a774a647dbb92dc9f0fb0f557d7d4c233c2ae4204f72` |
| Strict C++23 Qt selftest | `cc74943eae7481620fbc20c8dc9dde6178d5c61d481119ffcd9fb3267f2b7df9` |

The strict Qt selftest exited 139 when launched in single-user mode.
It initializes a GUI QApplication before processing `--modern-cpp`.
A normal desktop run remains pending. QEMU first aborted in its virtual
FAT implementation while the guest was starting graphics. The
archives were already installed on the guest disk. Subsequent startup
attempts without the transfer files reached Tiger kernel panics
(`pmap_page_protect` and `pmap_remove: null pv_list!`) before a desktop
session or any ordinary example run.

## Repository probe build

`make qt4-macos-i386-llvm-probe PARALLEL_JOBS=3` rebuilt libc++ and
linked the same source both in a single compiler invocation and with
separate compile and link steps. Both executables link only
`libgcc_s.1.dylib` and `libSystem.B.dylib`. The exported separate-link
probe has SHA-256
`27fdaf4a09fa8a0df6443bb769a0527a8883a1c7ee127ec86d825b51f3908404`.
The exported binary passed all 25 required checks on Tiger 10.4.10
(8R3032), with exit code 0 and no skips. Its guest SHA-1 matched
the host value, `8049499883e20ab8c418779391c981e79d15d10c`.

## Repository SDK and examples

`make qt4-macos-i386-llvm-examples PARALLEL_JOBS=3` built the full
SDK from a fresh source cache and exported the ordinary and strict
example archives. All nine ordinary Mach-O bundles and the separate
strict selftest passed the i386 binary audit with deployment target
10.4.0. The clean-build archives have the following SHA-256 values.

| Archive | SHA-256 |
|---|---|
| `qt4-tiger-i386-examples.tar.gz` | `bfe6862a6f1c936fd6b86e4667b71eb1e2f96a25bce4e75eac85beb901bf0b0d` |
| `qt4-tiger-i386-strict.tar.gz` | `0f7d8ceb2f2e494beed435f92bcb5af9a1a3e5d8448492417372643a3e2122bd` |

The first desktop boot attempt with the repository builds reached
SystemStarter, which repeatedly waited for application services. The
graphics session did not start, so the ordinary suite and the strict
Qt-linked selftest still need a desktop run. The repository-built
standalone probe completed before the desktop startup attempt.


## Recovered Intel guest

The installed q35 disk from the earlier Tiger GUI run was recovered
from the read-only lab archive. The local copy includes the base disk,
writable overlay and EFI variables. The local overlay uses a relative
path to its backing file. QEMU booted Tiger 10.4.10 (8R3032) on a Core Duo
CPU to Finder after a filesystem check, loading the stock AppleSMC and
Dont Steal Mac OS X modules, and leaving single-user mode.

The guest verified both repository archives before extraction. The
SDK-linked selftest passed **25/25 required C++23 checks with zero
skips** and exit code 0. Six of the eight ordinary applications passed.
Both widgets-gallery and graphics-gallery crashed at the same
instruction in `QWidgetPrivate::setStyle_helper`, reached from
`QWidget::setStyleSheet`. The Tiger LLVM build now applies the
existing Clang optimization workaround for that function.

## Rebuilt SDK and final QEMU run

The next desktop boot aborted in QEMU's writable virtual FAT disk.
The retry used a temporary snapshot for the EFI FAT disk and reached
Finder. The installed Tiger 10.4.10 system ran on the same Core Duo
CPU model.

The rebuilt suite passed **8/8 applications**, including both
galleries that crashed on the first run. The ordinary suite recorded
366 passed checks, zero failed and 154
optional skips. The rebuilt SDK-linked Qt selftest passed
**25/25 required C++23 checks with zero skips** and exit code 0.
Both archives matched their guest transfer digests before extraction.

| Final archive | SHA-256 |
|---|---|
| `qt4-tiger-i386-examples.tar.gz` | `c2f45ae4099f2ebc0a9ef61a8022dd67a4b1113b2e4b39714d3195cb1d50e593` |
| `qt4-tiger-i386-strict.tar.gz` | `943ab9f4827f9aa5431625ebb5932d589be4a988c47536ad01456c369b78c45a` |

The Mach-O audit confirmed i386 and deployment target 10.4.0 for
all ten executables, including the runner and strict selftest. The
audit hashes match the archived binaries. See the
[JSON record](qt4-macos-i386-tiger-llvm21-20261113.json) for
per-application results and dynamic dependencies.
