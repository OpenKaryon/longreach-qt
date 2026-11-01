# Tooling review fixes after v0.2.0

Validation of local changes based on `205110d791997469a1d47cb08f71901727344d7b`.
The published `v0.2.0` tag is unchanged. These results do not describe a
newly published release or rebuilt SDK image matrix.

## Changes

- Source archives without `.git` can calculate SDK/example fingerprints.
- The Qt 6 project builder exports nested Linux/Windows executables and
  macOS bundles, rejects empty/duplicate exports and forwards `--jobs`.
- Windows VMware uses a fresh 8.3-compatible guest subdirectory and
  requires a report from that run. Old reports are left untouched.
- VirtualBox common authentication options precede guest arguments;
  the backend explicitly accepts Linux guests only.
- The Linux forward matrix has the RHEL/XCB package set and checks
  configuration completeness before starting workers.
- Qt 6 Windows retains upstream DoT dispatch and TLSA parsing while
  resolving DnsQueryEx dynamically and using the legacy API for standard
  DNS on Windows 7. Unsupported legacy server/port settings fail explicitly.

## Validation

All builds and ordinary tests below ran sequentially. Compilation and
consumer checks used one CPU and a 2 GiB container limit, with networking
disabled. The single CentOS runtime container used one CPU and 4 GiB.
No virtual machine was started.

| Check | Result |
|-------|--------|
| Lightweight tooling regressions | 8 tests PASS, no Docker/VM/network calls |
| Source snapshot without `.git`, real `ensure-image --print` / make dry run | PASS; no SDK build executed |
| Windows DNS backend, amd64 | Compiles and links against existing SDK |
| Windows DNS backend, arm64 | Compiles and links against existing SDK |
| DNS linked imports | No static DnsQueryEx import; legacy DnsQuery_W retained |
| Nested Linux application | Built, exported and executed successfully with Qt 6.8.5 |
| Nested macOS application bundle | Cross-built and exported successfully |
| Nested Windows application | Cross-built and exported successfully |
| Library-only consumer project | Empty application export rejected as expected |
| Duplicate consumer output names | Export rejected before copying partial output |
| Existing Qt 6 Linux suite on stock CentOS 7 | 8/8 applications; 528 passed, 0 failed, 51 skipped; no missing libraries |
| Python syntax, API coverage gate, license matrix and reports for Qt 4/5/6 | PASS |
| Repository SPDX/leak scan, stop-word check, diff whitespace, documentation links | PASS |

The lightweight regressions cover archive inventory, consumer job settings,
fresh/missing Windows VMware reports in both launch modes, VirtualBox argv
and unsupported OS handling, and every supported matrix package combination.
They are also included in CI. CentOS was run through the real `run_pair`
path; other matrix entries were not run in this task.

The Windows DNS executables were linked only and never run. No DNS/DoT
requests, crafted inputs, vulnerability reproductions or security-patch
runtime tests were performed. The full Windows SDK images and full target
matrix were not rebuilt. VMware and VirtualBox command behaviour was
checked with mocks; live guest integration was not rerun.

Earlier deferred Qt 4 font/SVG bounds and painting-lab process-ownership
findings are outside these seven fixes and remain open.

Local logs are under `build/review-fixes-20261031/`: `checks/` contains
compile/link logs, source fingerprint, consumer results and the lightweight
gate logs; `forward-runtime/qt6-linux-amd64__centos-7/` contains the actual
per-application runtime output and report.

## Validated implementation files

SHA256 values identify the local implementation independently of a future
commit that records these changes.

| File | SHA256 |
|------|--------|
| `patches/qt6/windows/04-network-win7.patch` | `7fbb3871d93302b820cd31c9939de2665e7c8f5e754fe33dcba6e88c387dcd45` |
| `scripts/build/ensure-image.py` | `a9654290f596eaee09510677c68afd920cef14d8712ca54abb947bb737ac102d` |
| `scripts/build/qt6-build-project.py` | `d2de38a8a0fb4d709ed6593fdf025fa5819191dc0761d881e4aa058d0b083cee` |
| `scripts/run/run.py` | `8e838523f5ac7cd70e6b0a837b80c3fcb97d197f9626b424517702c50e0f6281` |
| `scripts/tests/linux-forward-check.py` | `1630dd9cb60620f72bb68826641a2bb139f1936169c9180c154fba29299fe65d` |
| `scripts/tests/test_tooling.py` | `ad36aea91ba9362dd18e4290127081272f9acc7a4222aaaadc3abf603023762a` |
