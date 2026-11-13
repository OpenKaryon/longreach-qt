# Qt 5.15.19 with LLVM 21.1.8 on Windows XP i386

## Standalone runtime probe

The standalone probe ran on Windows XP SP3 (5.1.2600) in VMware Workstation.
It used upstream Clang, LLD, compiler-rt, libunwind and libc++ 21.1.8 with
the MinGW-w64 v5 XP sysroot and static winpthreads. It passed all 25 required
C++23 behaviors with zero failures or skips. The PE32 subsystem version was 5.1.

The probe used the 32-bit Visual C++ 2010 runtime (msvcr100.dll 10.0.30319.1)
beside the executable. The first build linked against the system msvcrt.dll
and failed at load time. The import audit found 26 missing locale and
multibyte functions. The final probe imported only kernel32.dll,
msvcr100.dll, psapi.dll and user32.dll.

The experimental runtime reused winpthreads for synchronization and used
XP file APIs for the Unicode filesystem round trip. A PE TLS section change
made Clang's native TLS offsets match the MinGW-w64 v5 startup object.
The i386 C++ TLS destructor had to use Clang's member-function calling
convention. The previous build passed 24 checks and failed the thread-local
destructor check.

The experimental filesystem code still has limitations for canonical
paths, symlink creation and handle-based permission changes.

## Staged Qt SDK

The SDK was built with desktop OpenGL and linked OpenSSL 3.5.7. All 235
static archive paths matched the existing Windows i386 SDK, including
Mapbox GL. CMake built nine executables in strict C++23 mode. All nine
were audited as PE32 with subsystem version 5.1 and verified by SHA256
after transfer into the guest. The CRT was deployed beside the executables.

| Run | PASS | FAIL | SKIP |
|---|---:|---:|---:|
| Required C++23 | 25 | 0 | 0 |
| Seven GUI examples | 216 | 0 | 29 |

The checks ran sequentially through VMware guest operations with the
native Qt Windows plugin. The first console attempt selected the
offscreen plugin, which this SDK does not include. The console was rerun
with the native Windows plugin and passed. The SDK build used a local
staging recipe.

## Clean repository build

`make qt5-win-i386-llvm-examples PARALLEL_JOBS=4` rebuilt the SDK and all nine executables. The archive paths
again matched the existing SDK.
All 157 qmake module files and 314 qmake feature entries matched the existing SDK.
The nine extracted binaries were verified
by SHA256 and reran on XP SP3, with 25 of 25 required C++23 checks and all
seven GUI examples passing. The JSON records the new hashes.

The November 13 rerun used the same nine SHA-256-verified binaries and
the app-local CRT on the 32-bit XP SP3 guest. All 25 required C++23 checks
and all seven GUI examples passed again.

[Machine-readable results](qt5-win-i386-llvm21-xp-probe-20261112.json)
