# Qt 4.8.7 for Windows

| Target | Image | Floor | Toolchain |
|--------|-------|-------|-----------|
| `make qt4-win-i386` | `qt4-win-i386` | Windows 95 OSR2 | MinGW-w64 GCC 5.3 (Ubuntu 16.04), win32 threads, OpenSSL 1.0.2u |
| `make qt4-win-amd64` | `qt4-win-amd64` | Windows XP x64 | MinGW-w64 GCC 5.3, OpenSSL 3.5.7 |

`make qt4-extract-tests QT4_IMAGE=qt4-win-i386` builds the test suite against
the SDK with qmake and puts the EXEs in `artifacts/tests-qt4-win-i386/`.

## Windows amd64 with LLVM 21.1.8

The opt-in SDK targets XP x64 and Server 2003 using upstream Clang, LLD
and libc++, with the pinned XP x64 MinGW-w64 sysroot and OpenSSL 3.5.7
from the Qt 5 toolchain stage. qmake builds Qt in its original C++98
dialect and builds the strict test application in C++23.

With the base Qt 5 Windows amd64 image and LLVM compiler image already built:

```sh
make qt5-win-amd64-llvm-toolchain PARALLEL_JOBS=3
make qt4-win-amd64-llvm-probe
```

Copy the AMD64 Visual C++ 2010 SP1 runtime file `msvcr100.dll` from a
licensed installation next to `cxx23-probe.exe` in
`artifacts/tests-qt4-win-amd64-llvm21/bin/`. Run the standalone probe on
XP x64 and check its log with
`python scripts/tests/require-modern-cpp.py <log>` from the repository root.

Build the full SDK and examples with:

```sh
make qt4-win-amd64-llvm-examples PARALLEL_JOBS=3
```

Copy the examples and the same AMD64 runtime DLL to the guest. Run
`qt-selftest-cxx23.exe --modern-cpp` and `smoke-runner.exe --timeout=90`
in sequence. Check the C++23 log with the same verifier.
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
- `gthr-win95.o`, libgcc's thread glue with `CreateSemaphoreA` in place of
  `CreateSemaphoreW`, which Windows 95 does not export;
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

## Results

See [platforms](../platforms.md#qt-487): i386 8/8 on Windows 95 OSR2
(QEMU), Windows 98 SE, NT 4.0 SP6a and Windows 2000 (VMware) and Windows 11;
amd64 8/8 on Windows 11, not yet on XP x64. Windows Me has not been run.

The [LLVM amd64 result](../results/qt4-win-amd64-llvm21-xp-20261113.md)
records the Windows XP x64 SP2, Windows 7 SP1 and Windows 11 runs.

## Limits

- Windows 95 in VMware: VMware Tools 7.7 are unstable on Windows 95 (large
  transfers hang), so its runs are in QEMU.
- Real audio output on Windows 9x is unverified.
- QtWebKit and Phonon are not built (as in every Longreach Qt SDK).
