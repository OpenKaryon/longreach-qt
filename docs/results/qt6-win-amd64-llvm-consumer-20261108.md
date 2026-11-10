# Windows amd64 LLVM consumer validation

On 2026-11-08 UTC, the [Windows LLVM consumer profile](../targets/qt6-windows-llvm.md)
built successfully from the existing Qt 6.8.5 / LLVM-MinGW 19.1.6 MSVCRT
SDK. It adds pinned CMake 3.28.6 and native build tools; Qt and LLVM were
not rebuilt. The [JSON record](qt6-win-amd64-llvm-consumer-20261108.json)
contains image IDs, current input hashes and all twelve executable hashes.

## Qt SDK checks

All eight applications and smoke-runner cross-compiled in C++23 mode.
A separate experimental console and two language binaries also built.
All twelve files passed the existing PE subsystem/import audit, reporting
subsystem 6.0 and no screened Windows 8+ loader dependencies.

Native checks ran sequentially on Windows 11, build 10.0.26200:

| Check | PASS | FAIL | SKIP |
|---|---:|---:|---:|
| Ordinary console self-test | 279 | 0 | 45 |
| Experimental console self-test | 281 | 0 | 43 |
| Ordinary C++23 language checks | 14 | 0 | 2 |
| Experimental C++23 language checks | 16 | 0 | 0 |

Both experimental thread checks (jthread and stop-token/callbacks) ran and
passed. The initial GUI startup attempt used offscreen although only the
Windows plugin was imported. A trial offscreen import then hit an OpenGL
check that requires the Windows backend. The shared test configuration was
restored, final binaries were rebuilt, and the console checks above ran
with the native Windows backend. Initial failure logs were retained.

The runner now selects `windows` explicitly, writes Qt diagnostics to
files, and stops on the first failed executable/check. Its process-local
error-mode settings apply to its own descendants; system-wide Windows
Error Reporting settings are unchanged. The seven GUI galleries were not
rerun after the reported popup failures. Windows 7 runtime execution was
not repeated; the static PE audit is not a Windows 7 runtime certification.

The runner refactor was rechecked on 2026-11-10 UTC after rebuilding the
same twelve executables. All four console counts remained unchanged.
Runner checks also confirmed mandatory experimental results, restoration
of the process error mode and stopping after the first failure.

## C++20 consumer

A local Qt Widgets/Svg consumer built its desktop application, worker and
CLI in 16.28 minutes using the new image, unchanged dependency pins and a
new build volume seeded from a read-only dependency cache. Its own code
retained warnings-as-errors. No application C++ changes were required;
the build script was changed only to honor `PARALLEL_JOBS`.

The CLI reports OR-Tools 9.15.9999 from the pinned 9.15 sources. Both the
public tiny example and the public historical example solved optimally
with one worker. The historical solve took 1,196 ms; independent validation
confirmed all 952 meetings with zero errors and warnings. Legacy migration
printed its legacy-setting warnings; input data and scheduling rules were
not modified. All three EXEs and 99 dependency DLLs passed the static
loader/subsystem screen. Consumer source hashes and detailed receipts stay
in that checkout's ignored build directory.

The consumer desktop GUI and full application test suite were not run.
There was no VM launch, security regression test, push or release
publication during validation. Builds used at most four jobs and one container at a time,
limited to four CPUs and 8 GiB; runtime CLI solving used one worker.

## Local evidence

- `build/llvm-pilot/windows-image-build.log`.
- `build/llvm-pilot/windows-suite-final-build.log` (native-backend compile/import audit).
- `build/llvm-pilot/windows-refactor-build.log` (rebuild after runner refactoring).
- `build/llvm-pilot/windows-first-run/` and the earlier Windows diagnostics.
- `artifacts/tests-qt6-win-amd64-llvm19/`: final EXEs, per-console logs and
  the artifact manifest. The initial aggregate failure report is labelled
  separately and does not describe the final console validation.
