# Qt 6 Linux amd64: LLVM 19 pilot

On 2026-11-08, Qt 6.8.5 completed a fresh Clang/LLD 19.1.6 build on CentOS 7
in 55.9 minutes (12,745 Ninja steps). The C++23 consumer suite passed all
eight applications: **542 checks passed, 0 failed, 52 skipped**.
The [machine-readable record](qt6-linux-amd64-llvm19-sdk-20261108.json)
contains per-application counts, input hashes, image IDs and binary hashes.

A [later thread-test follow-up](qt6-linux-amd64-llvm-threads-20261108.md)
adds a sixteenth check and a separate `-fexperimental-library` run with
jthread and stop-token checks required to pass. The earlier results below
retain their original source hashes and 15-check counts.

## Build scope

The [experimental recipe](../../docker/qt6/linux/amd64/Dockerfile-llvm)
bootstraps Clang/LLD, compiler-rt, static libc++, libc++abi and libunwind on
glibc 2.17. LLVM 19.1.6 matches the version used by the current Windows
LLVM-MinGW targets. Qt uses its own required language level; consumers
explicitly select C++23.

The seed is the [locked-RPM GCC SDK](qt6-linux-amd64-centos7-rpm-lock-20261104.md):
its patched Qt source, OpenSSL and C/system dependencies are reused.
The Qt libraries are rebuilt from source under
`/opt/qt6-linux-amd64-llvm`. This is not a cold rebuild of all dependencies.
The seed's GCC SDK remains in the image. Default Makefile targets are
unchanged; there is no new published SDK image or release.

- Source base: `8a24b9d0abec467a05f3085bf5266563495c8500` (`v0.2.1`), with local test/recipe changes.
- Seed image ID: `sha256:7c41b21e376019cfcc5be848d99f6df265ce7aff06213b07a7250942f40271b8`.
- Pilot image: `qt6-linux-amd64:llvm19-pilot`, ID `sha256:9af6acfe332d961c3526f22a163e7eeae0962c57892e7590dbf81e0290212839`.
- LLVM archive: `llvm-project-19.1.6.src.tar.xz`, SHA256
  `e3f79317adaa9196d2cfffe1c869d7c100b7540832bc44fe0d3f44a12861fa34`.
  The hash is a local content pin measured from the official HTTPS download,
  not an independently verified upstream signature.
- Build steps and test containers used `--network=none`. Builds used four
  compile jobs, LLVM bootstrap one link job, LLD two threads per link.
  The consumer container used four CPUs and 8 GiB. All operations ran sequentially.

The compiler bootstrap took about 30 minutes. Initial runtime configuration
attempts needed an explicit target triple, the unused ctx-profile runtime
disabled, and a matching per-target compiler-rt install layout. The working
compiler build was reused while correcting that configuration.

Two consumer adjustments were needed: the Quick 3D example now includes
the complete debug-draw type before a header with a `unique_ptr` default
argument; and the pilot passes `-DCMAKE_EXE_LINKER_FLAGS=-no-pie` to match
the seed's non-PIC Wayland stub archives and GCC executable mode.
The Quick 3D example also compiled successfully with the original GCC
11.2.1 SDK and its default language setting (15 Ninja steps, exit 0).
The Qt library build itself needed no additional source patches.

## Ordinary smoke suite

The full suite was built with `-DCMAKE_CXX_STANDARD=23` against the explicit
LLVM SDK prefix and run inside its CentOS 7 SDK container under
Xvfb/offscreen. No application was omitted.

| Application | PASS | FAIL | SKIP |
|---|---:|---:|---:|
| `qt-selftest` | 297 | 0 | 39 |
| `widgets-gallery` | 91 | 0 | 4 |
| `graphics-gallery` | 32 | 0 | 0 |
| `quick-qml-gallery` | 41 | 0 | 4 |
| `gl-heavy-gallery` | 55 | 0 | 4 |
| `painting-lab` | 16 | 0 | 0 |
| `multimedia-lab` | 3 | 0 | 1 |
| `network-gui` | 7 | 0 | 0 |
| **Total** | **542** | **0** | **52** |

The skips cover the existing removed APIs, absent backends/devices and
headless limitations, plus the new `std::jthread` skip. The non-UTF-8
locale and expected backend/plugin warnings did not cause failures.
All nine suite ELF executables require GLIBC versions no newer than 2.17.

## Guarded modern C++ checks

The new console checks use header availability, feature-test macros and the
selected language mode to exclude unsupported syntax and library calls.
Unavailable facilities remain visible as named SKIP lines.

| Compiler / mode | PASS | FAIL | SKIP |
|---|---:|---:|---:|
| Qt 4 SDK, GCC 5, C++14 | 1 | 0 | 14 |
| LLVM pilot, C++17 | 5 | 0 | 10 |
| LLVM pilot, C++20 | 9 | 0 | 6 |
| LLVM pilot, C++23 | 14 | 0 | 1 |
| Same C++23 binary, stock CentOS 7 | 14 | 0 | 1 |
| Same C++23 binary, stock Debian 13 | 14 | 0 | 1 |

The C++23 run executes `if consteval`, `std::expected`, `std::byteswap`,
`std::ranges::to` and `std::print`, as well as the earlier-standard checks.
`std::jthread` is not exposed by this default libc++ 19 configuration.
These checks demonstrate selected facilities, not complete C++23 conformance.

The runtime-only checks use the identical `modern-cxx23` executable,
SHA256 `e7715a21ec9dfb29010be5c4819c685752422916dca00dbe7b1a1c19b973d765`.
It requires GLIBC up to 2.16 and only the system math, dl, rt, pthread,
C and loader shared libraries; there is no shared libstdc++, libc++,
LLVM or Clang runtime dependency. Neither stock runtime container contains
the pilot compiler. Containers test old userland on the host kernel;
an old CentOS kernel and a VM GUI session were not tested here.

## Local evidence

- `build/llvm-pilot/`: `qt-build.log`, `toolchain*.log`,
  `suite-first-attempt.log`, `suite-second-attempt.log`, `suite-build-run.log`,
  `modern-cxx14-gcc.log`, `modern-centos7.log`, `modern-debian13.log`,
  `quick-gcc-default.log`.
- `artifacts/tests-qt6-linux-amd64-llvm19/`: executables, `smoke-report.txt`,
  per-application logs, `modern-cxx{17,20,23}.log`, `source-inputs.json`
  and the artifact manifest. Input hashes were checked again after the run.

Only `v0.2.1` was pushed. The pilot and new self-test changes were local
when these results were recorded. No VM or security regression test was run.
