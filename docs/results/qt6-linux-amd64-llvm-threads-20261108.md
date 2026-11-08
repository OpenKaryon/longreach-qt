# LLVM pilot: experimental thread self-test

On 2026-11-08 the existing Qt 6 Linux amd64 LLVM SDK was checked again with
an additional guarded stop-token/callback test and a separate experimental
library run. Qt and LLVM were not rebuilt. The
[machine-readable record](qt6-linux-amd64-llvm19-threads-20261108.json)
contains input and executable hashes and per-application results.

## Run settings

The [pilot script](../../scripts/tests/qt6-linux-amd64-llvm/run-suite.sh)
first builds and runs the ordinary eight-app C++23 smoke suite. It then
uses a separate build directory for the full console `qt-selftest`, adding
`-fexperimental-library` for compilation and linking. This exposes
libc++ 19's experimental `std::jthread` and `std::stop_token` support.
Both named checks must report PASS: SKIP fails that script stage.
The ordinary flags, binaries and logs are preserved separately.
The actual required-check function was also verified against the saved
ordinary SKIP log (rejected) and experimental PASS log (accepted); shell
syntax validation passed.

The jthread check covers thread execution, token delivery and automatic
join. The stop-token check covers the initial state, cancellation,
idempotent repeated requests, and callbacks registered before and after
cancellation. No sleep or timing-dependent assertion is used.

The SDK remains `qt6-linux-amd64:llvm19-pilot`, image ID
`sha256:9af6acfe332d961c3526f22a163e7eeae0962c57892e7590dbf81e0290212839`.
Source base is `8a24b9d0abec467a05f3085bf5266563495c8500` with local changes.
The script's ordinary and experimental builds/runs took 2.93 minutes.
All stages, stock-userland checks and the legacy compiler check ran
sequentially. Consumer compilation used at most four jobs in one container
limited to four CPUs and 8 GiB. Runtime-only checks used one CPU and 1 GiB;
the Qt 4 check used two CPUs and 2 GiB. Networking was disabled.

## Results

| Check | PASS | FAIL | SKIP |
|---|---:|---:|---:|
| Ordinary suite, all 8 applications | 542 | 0 | 53 |
| Ordinary console `qt-selftest` (part of that suite) | 297 | 0 | 40 |
| Experimental console `qt-selftest` | 299 | 0 | 38 |
| Language checks, ordinary C++17 | 5 | 0 | 11 |
| Language checks, ordinary C++20 | 9 | 0 | 7 |
| Language checks, ordinary C++23 | 14 | 0 | 2 |
| Language checks, experimental C++23 | 16 | 0 | 0 |
| Same experimental language binary, stock CentOS 7 | 16 | 0 | 0 |
| Same experimental language binary, stock Debian 13 | 16 | 0 | 0 |
| Qt 4 SDK, GCC 5, C++14 | 1 | 0 | 15 |

The two ordinary C++23 skips are jthread and stop-token/callback support;
both execute and pass with the experimental flag. The remaining full-console
skips are the existing unsupported APIs, devices and backends. The legacy
build still excludes unsupported modern syntax and headers.

Every ordinary suite executable and the experimental console binary meets
the GLIBC 2.17 floor. The experimental QtCore language binary needs GLIBC
up to 2.16 and only the system math, dl, rt, pthread, C and loader shared
libraries. It needs no shared libc++, libc++experimental, libstdc++, LLVM
or Clang library. Its SHA256 is
`70768bf73db882b924e65db46b415670133ddbf4aa75e21ea1e13977270c274c`.
The identical binary passed in both stock runtime images without LLVM.
These are container/userland checks on the host kernel, not VM or old-kernel
checks. No security regression tests were run.

## Evidence

- `artifacts/tests-qt6-linux-amd64-llvm19-threads/`: ordinary suite, separate
  experimental executables/logs, `source-inputs.json` and artifact manifest.
- `build/llvm-pilot/`: `suite-threads-build-run.log`, `threads-centos7.log`,
  `threads-debian13.log`, `threads-cxx14-gcc.log` and `threads-required-gate.log`.
- The [initial pilot report](qt6-linux-amd64-llvm-20261108.md) retains the
  earlier 15-check results. This follow-up has 16 checks and distinct artifacts.

The changes and results remain local; no commit or push was made.

## Source-layout follow-up

The LLVM recipe now lives beside the existing amd64 recipe as
`docker/qt6/linux/amd64/Dockerfile-llvm`; compiler wrappers and test helpers
live under `scripts/`, and the [instructions](../targets/qt6-linux-llvm.md)
live under `docs/targets/`. The earlier JSON input paths and hashes remain
historical evidence of their original runs.

The relocated Dockerfile passed `docker build --check` without warnings.
The current runner then passed sequentially in the existing SDK: all eight
ordinary applications (542/0/53), the experimental console (299/0/38), and
all sixteen experimental language checks (16/0/0). The runner took 2.77
minutes; GLIBC limits remain 2.17 for the suite/console and 2.16 for the
language binary. Qt and LLVM were not rebuilt. The result JSON records the
current input hashes separately under `layout_recheck`.

Local evidence: `build/llvm-pilot/layout-dockerfile-check.log`,
`build/llvm-pilot/layout-suite-build-run.log` and
`artifacts/tests-qt6-linux-amd64-llvm19-layout/`.
