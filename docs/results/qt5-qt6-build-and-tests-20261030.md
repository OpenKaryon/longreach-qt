# Qt 5 and Qt 6: builds and Linux amd64 tests, 2026-10-30

Source commit: `ea9b0aa77cf130020af7e21b45dd51a595f9b19b` (`main`), including the QDom save compatibility
fix. All 15 test-suite manifests record this commit and a clean source tree.
Qt 5 is 5.15.19; Qt 6 is 6.8.5.

## Builds

The SDK and test-application build completed on 2026-10-30. Targets ran
one at a time: **16 passed, 0 failed, stopped or skipped** (nine Qt 5
targets, six Qt 6 targets and the Qt 6 host tools). Every target passed
on its first attempt. The build may reuse cached SDK layers; PASS records
a successful build command, not a clean rebuild of every SDK component.

Each of the 15 target suites contains eight test applications and
`smoke-runner`. This table records successful builds; runtime evidence
for the current suites is listed separately below.

| Target | Result | Minutes | Test-suite executables |
|--------|--------|---------|------------------------|
| `qt6-host` | PASS | 0.2 | - |
| `qt5-win-i386` | PASS | 69.7 | 9 |
| `qt5-win-amd64` | PASS | 55.2 | 9 |
| `qt5-win-arm64` | PASS | 43.4 | 9 |
| `qt5-linux-i386` | PASS | 33.1 | 9 |
| `qt5-linux-amd64` | PASS | 0.2 | 9 |
| `qt5-linux-arm64` | PASS | 30.3 | 9 |
| `qt5-macos-amd64` | PASS | 28.3 | 9 |
| `qt5-macos-i386` | PASS | 30.3 | 9 |
| `qt5-macos-arm64` | PASS | 28.0 | 9 |
| `qt6-win-amd64` | PASS | 34.3 | 9 |
| `qt6-win-arm64` | PASS | 29.8 | 9 |
| `qt6-linux-amd64` | PASS | 1.0 | 9 |
| `qt6-linux-arm64` | PASS | 47.3 | 9 |
| `qt6-macos-amd64` | PASS | 29.7 | 9 |
| `qt6-macos-arm64` | PASS | 29.2 | 9 |

Local build evidence: `build/build-all-20261030-0250/summary.json`,
`summary.md`, `progress.log` and the per-target logs in that directory.
Every target log ends with `=== PASS (exit 0)`.

SHA256 of `summary.json`: `b62ef0dc11f053009f62e798875ba9892000b83b272356a2071b8cc630741667`.

## Runtime tests

| Suite | System | Applications | Passed | Failed | Skipped | Record |
|-------|--------|--------------|--------|--------|---------|--------|
| `qt5-linux-amd64` | debian-13 | 8/8 | 511 | 0 | 87 | [json](qt5-linux-amd64-debian-13-docker-20261030.json) |
| `qt5-linux-amd64` | centos-7 | 8/8 | 511 | 0 | 87 | [json](qt5-linux-amd64-centos-7-docker-20261030.json) |
| `qt6-linux-amd64` | debian-13 | 8/8 | 528 | 0 | 51 | [json](qt6-linux-amd64-debian-13-docker-20261030.json) |
| `qt6-linux-amd64` | centos-7 | 8/8 | 528 | 0 | 51 | [json](qt6-linux-amd64-centos-7-docker-20261030.json) |

Qt 6 was rerun on 2026-10-30 against the final suite from the build
above: Debian 13 first, then CentOS 7, with no overlap. All nine
executable SHA256 values in each runtime record match the current
manifest and files, including the rebuilt `quick-qml-gallery`.

Qt 5 was not rerun in this follow-up. Its existing QDom-fix runs
completed on 2026-10-29 at 21:46-21:48 UTC (their records use the
runner host date, 2026-10-30). All nine executable SHA256 values in
both records still match the final suite manifest and files.

Both generations ran in stock distribution containers under Xvfb,
with the standard runtime packages installed by `scripts/run/run.py`.
Skipped checks remain reported separately; none is counted as passed.
These runs check the container userlands on the host kernel.
The [Windows and macOS follow-up](windows-macos-final-20261030.md)
records the subsequent validation of those suites. Other platforms
retain their earlier runtime results in [platforms.md](../platforms.md).

Local runtime logs:

- Qt 5: `build/runs/q56b-qt5-linux-amd64-debian-13-docker/` and
  `build/runs/q56b-qt5-linux-amd64-centos-7-docker/`.
- Qt 6: `build/runs/q56c-qt6-linux-amd64-debian-13-docker/` and
  `build/runs/q56c-qt6-linux-amd64-centos-7-docker/`.
