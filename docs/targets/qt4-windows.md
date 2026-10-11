# Qt 4.8.7 for Windows

| Target | Image | Floor | Toolchain |
|--------|-------|-------|-----------|
| `make qt4-win-i386` | `qt4-win-i386` | Windows 95 OSR2 | MinGW-w64 GCC 5.3 (Ubuntu 16.04), win32 threads, OpenSSL 1.0.2u |
| `make qt4-win-amd64` | `qt4-win-amd64` | Windows XP x64 | MinGW-w64 GCC 5.3, OpenSSL 3.5.7 |

`make qt4-extract-tests QT4_IMAGE=qt4-win-i386` builds the test suite against
the SDK with qmake and puts the EXEs in `artifacts/tests-qt4-win-i386/`.

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

See [platforms](../platforms.md#qt-487): 24/24 on Windows 95 OSR2 (QEMU),
Windows 98 SE, NT 4.0 SP6a and Windows 2000 (VMware) with the earlier
24-application layout of the suite. Windows Me has not been run. The amd64
build has not been run on Windows yet.

## Limits

- Windows 95 in VMware: VMware Tools 7.7 are unstable on Windows 95 (large
  transfers hang), so its runs are in QEMU.
- Real audio output on Windows 9x is unverified.
- QtWebKit and Phonon are not built (as in every Longreach Qt SDK).
