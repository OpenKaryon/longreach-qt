# Qt 4.8.7 for Windows

| Target | Image | Floor |
|--------|-------|-------|
| `make qt4-win-i386` | `qt4-win-i386-llvm21` | Windows 95 OSR2, OpenSSL 1.0.2u |
| `make qt4-win-amd64` | `qt4-win-amd64-llvm21` | Windows XP x64 SP2, OpenSSL 3.5.7 |

Both targets use upstream Clang, LLD and static libc++ 21.1.8.
Make prepares the compiler and the pinned Bionic MinGW-w64 v5 input
layers before building the SDKs and examples.

```sh
make -j2 qt4-win-i386-examples qt4-win-amd64-examples PARALLEL_JOBS=3
```

The toolchain commands assemble the MinGW-w64 headers, CRT and runtime
inputs without a Qt 5 SDK. The two Qt 4 Dockerfiles target different
Windows versions and use different CRTs. Installed Qt uses its
original C++ dialect. The strict selftest compiles separately as C++23.

## Windows XP x64 SP2

Copy the AMD64 Visual C++ 2010 SP1 runtime `msvcr100.dll` from a
licensed installation beside the executables in
`artifacts/tests-qt4-win-amd64-llvm21/bin/`. Run
`qt-selftest-cxx23.exe --modern-cpp` and `smoke-runner.exe --timeout=120`
in sequence. Check the strict log with
`python scripts/tests/require-modern-cpp.py <log>`.
QtScript and QtDeclarative use the JavaScript interpreter.

## Windows 95, 98, ME and NT 4.0

Qt removed Windows 9x support in 4.6. `patches/qt4/windows` puts it back:
every Win32 call that has an ANSI and a Unicode form is chosen at run time,
ANSI on Windows 9x and Unicode on NT, and the APIs newer than Windows 95 are
resolved with `GetProcAddress` and given a fallback. The same EXE therefore
runs on Windows 95 through Windows 11 and takes the Unicode path on every NT.
Each patch in `patches/qt4/windows` says in its header what it changes.

The i386 image adds what Windows 95 needs from the toolchain:

- no SIMD in Qt (the oldest CPUs have none, and Windows 95 saves no SSE
  state);
- the PE subsystem version 4.0 (Windows 95 refuses higher);
- `exe-exit.o`, routing `atexit` through MSVCRT's own `_onexit`, since the
  MinGW-w64 table needs CRT locks the Windows 95 MSVCRT lacks;
- a static Win95-compatible winpthreads runtime;
- OpenSSL 1.0.2u, the last series that runs there. It is end of life; the
  TLS 1.2 support it provides (with patch `all/06`) is a compatibility
  choice, not a claim of current security.

`scripts/audit/qt4_win95_imports.py` checks every import of every EXE against
a snapshot of the Windows 95 OSR2 system DLLs.

The Windows 95 runs used OSR2 with TCP/IP and Winsock 2, and 128 MB of
memory (at 64 MB, VMware Tools stopped during long sequential runs; whether
that was memory pressure is not proven). Printing, the native print dialogs,
the system tray and accessibility are built in and select their Win9x paths
at run time (patches 21-25). The TLS checks use the suite's own CA; the
Windows 95 certificate store is not consulted.

### Windows 95 OSR2 with LLVM 21.1.8

The standalone C++23 probe uses upstream Clang, LLD, libc++ and the
OSR2 MSVCRT from the Winsock 2 update. OpenSSL 1.0.2u uses the portable
software path. The VIA PadLock engine is disabled in this Clang build
because its old inline assembly conflicts with Clang's frame pointer.

```sh
make qt5-win-i386-llvm-toolchain PARALLEL_JOBS=3
make qt4-win-i386-llvm-probe PARALLEL_JOBS=3
make qt4-win-i386-examples PARALLEL_JOBS=3
```

The probe target exports `cxx23-probe.exe` to
`artifacts/tests-qt4-win-i386-llvm21/`. The examples target exports all
eleven executables to the same directory, including the probe and the
strict Qt selftest. The
[Windows 95 LLVM trial](../results/qt4-win-i386-llvm21-win95-20261113.md)
records both locales. The original mixed-script filename passes on
Simplified Chinese OSR2 with CP936. The Russian OSR2 code pages cannot
represent that filename.

## Results

The [platform matrix](../platforms.md#qt-487) lists the coverage by SDK.
The [earlier LLVM amd64 result](../results/qt4-win-amd64-llvm21-xp-20261113.md)
records Windows XP x64 SP2, Windows 7 SP1 and Windows 11 runs.
The `v0.2.2` tag preserves the GCC/MinGW SDKs and their build instructions.

## Limits

- Windows 95 in VMware: VMware Tools 7.7 are unstable on Windows 95 (large
  transfers hang), so its runs are in QEMU.
- Real audio output on Windows 9x is unverified.
- QtWebKit and Phonon are not built (as in every Longreach Qt SDK).

### Migration validation

| Guest | Applications | Ordinary checks | Strict C++23 |
|---|---|---|---|
| Windows 95 OSR2, Simplified Chinese, QEMU | 8/8 | 369 passed, 0 failed, 155 skipped | 25/25, 0 skips |
| Windows XP x64 SP2, VMware | 8/8 | 362 passed, 0 failed, 160 skipped | 25/25, 0 skips |

The standalone C++23 probe also passed 25/25 without skips in each
guest. The i386 executable copy matched all 11 original hashes.
On XP x64, 11 executables and the app-local CRT matched the verified
ISO copies. The [JSON record](../results/qt4-windows-llvm-migration-20261115.json)
includes the build references, counts, and file hashes.

### Build-path recheck

A fresh XP x64 SDK was built with `NO_CACHE=1` and a separate tag for
the XP toolchain. Make built the missing toolchain automatically. The
examples stage used the installed SDK and exported eleven executables
with verified manifest hashes. The second `build-qt4-win-amd64` call
reported the same SDK image as current and skipped Docker build.
