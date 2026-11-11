# Qt 6 SDK queue: upstream LLVM 21.1.8

This records the five Qt 6.8.5 SDK builds started on 2026-11-10 UTC
(2026-11-11 Moscow). The Linux amd64 build preceded the queue. Runtime
validation for the two ARM64 desktop targets awaits matching hosts or guests.

Build and test one SDK at a time, at most four CPUs and 8 GiB per compilation
container, with networking disabled. Never stop unrelated containers or the
user's Linux Mint VM. No security tests, push or release publication.
Commit completed milestones locally with the existing Codex coauthor trailer.

| Order | SDK | State | Required C++23 runtime |
|---|---|---|---|
| Completed before queue | Linux amd64 | Local image `qt6-linux-amd64:llvm21`, commit `7ffea38334c9` | 25/25; see prior report |
| 1 | Linux arm64 | [SDK built and tested](qt6-linux-arm64-llvm21-sdk-20261111.md) | 25/25 in QtCore and the Qt console, including QtCore in stock CentOS 7 under QEMU |
| 2 | Windows amd64 | [SDK built and tested](qt6-windows-amd64-llvm21-sdk-20261111.md) | 25/25 on the native Windows 11 host and in Windows 7 SP1 and Windows 11 guests |
| 3 | macOS amd64 | [SDK built and tested](qt6-macos-amd64-llvm21-sdk-20261111.md) | 25/25 in the clean High Sierra 10.13.6 guest |
| 4 | Windows arm64 | [SDK built, PE checked](qt6-windows-arm64-llvm21-sdk-20261111.md) | Pending, no configured Windows on ARM host or guest |
| 5 | macOS arm64 | [SDK built, Mach-O checked](qt6-macos-arm64-llvm21-sdk-20261111.md) | Pending, no configured Apple silicon host or guest |

Each required runtime must PASS all 25 names, with zero FAIL/SKIP, using
ordinary libc++ 21 without the experimental-library flag. Preserve guarded
C++14/17/20 source compatibility. Unsupported or unavailable execution is
reported as pending, never converted to a successful skipped run.

The shared compiler is upstream LLVM 21.1.8. Windows headers/CRT are separately
built from pinned mingw-w64 13.0.0 sources; no LLVM-MinGW compiler distribution
is used for the new profiles. Keep Dockerfiles beside the existing target
Dockerfiles; helpers belong under scripts/.

Local queue coordinator: `scripts/build/qt6-llvm-sdk/run.py`.
Per-target logs: `build/qt6-<target>-llvm21-<stage>.log`.
Per-target state/artifacts: `artifacts/tests-qt6-<target>-llvm21/`.
Retained object volumes and stopped owned build containers allow a failed
stage to resume. Wait for unrelated Docker work instead of interrupting it.

Linux arm64 preparation found two integration requirements before compiling
Qt: keep the SDK runtime CMake caches separate when installing the shared
compiler at a new path, and carry the native qsb graphics dependency closure
with the LLVM 21 host tools. glibc, libstdc++ and the loader are not copied
into that host graphics directory. Both requirements are now in the recipe.
