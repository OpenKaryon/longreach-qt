# Testing

## The suite

`tests/` holds eight applications and a runner, one directory each, listed in
`tests/expected-apps.txt`. Every Qt 4, 5 and 6 target builds all of them:

| Application | What it checks |
|-------------|----------------|
| `qt-selftest` | the non-visual modules: core, I/O, serialization, images, networking (TLS loopback included), SQL, XML, scripting, concurrency, sensors, serial, Bluetooth, positioning, D-Bus and the rest |
| `widgets-gallery` | widgets, item views, dialogs, tray, clipboard, styles, accessibility; on Qt 4 also Qt3Support and the Qt 4-only API |
| `graphics-gallery` | QPainter, images, a shaped window, animations, SVG |
| `painting-lab` | raster, text, alpha, print preview |
| `multimedia-lab` | Qt 5/6 player, camera and audio; Qt 4's low-level audio and video classes |
| `gl-heavy-gallery` | Qt3D, Charts and DataVisualization on Qt 5/6; QtOpenGL on Qt 4 |
| `quick-qml-gallery` | QML and Qt Quick 2 on Qt 5/6; QtDeclarative (Quick 1) on Qt 4 |
| `network-gui` | TCP, UDP, HTTP, SSL, WebSockets where present |
| `smoke-runner` | runs the others with `--selftest` and writes `smoke-report.txt` |

Each application has `--selftest`: it runs its checks, prints `PASS`, `FAIL`
or `SKIP` per check and a summary line, and exits non-zero on a failure. A
check that needs something the system does not have (a camera, a printer, a
newer OS) reports SKIP. `smoke-runner [--timeout=N] [--reverse] [--only=APP]
[--gui]` runs them in turn; it fails on a non-zero exit, a crash, a timeout or
a FAIL line. Messages that are expected noise on minimal systems are listed
in [expected-smoke-warnings.md](expected-smoke-warnings.md).

Qt 5 and Qt 6 build the suite with CMake (`scripts/build/tests.sh`; the
configure step fails if an application of `expected-apps.txt` cannot be
built, unless the licence profile leaves it out). Qt 4 builds it with qmake
from `<app>/<app>.pro` (`scripts/build/qt4-tests.sh`, which checks the same
list). Where a module is newer than Qt 4 the application uses the
period-equivalent one, so every generation produces the same names.

The Qt 4/5 SDK images build the suite in their final stage, which proves the
installed SDK stands on its own; `make qt5-extract-tests QT5_IMAGE=<image>` (Qt 5),
`make qt4-extract-tests QT4_IMAGE=<image>` and the `-examples`/`-smoke`
targets (Qt 4 Mac, Qt 6) put the binaries and a `manifest.json` in
`artifacts/`.

## Coverage

`scripts/tests/check_coverage.py` compares the Qt classes the suite references
with each version's public API (`scripts/tests/qt-api-classes*.txt`,
regenerated from a Qt source tree by `make regen-db`). Only sources a
version's build compiles count for it, and API no Longreach Qt target can reach
(Qt for Embedded Linux, Symbian and Windows CE on Qt 4, QNX transports,
Android, internal Wayland plugin classes) leaves the denominator with a stated
reason. Today all three generations are at 100%:

```sh
python scripts/tests/check_coverage.py          # per module, all three
python scripts/tests/check_coverage.py --gate   # CI: fails below 95% on the worst
```

## Running on a target

`scripts/run/run.py` copies a suite to a machine, checks it by SHA256, runs
`smoke-runner`, fetches the logs and writes a result in the format of
[results/](results/):

```sh
python scripts/run/run.py --suite artifacts/tests-qt5-linux-amd64-gpl-enabled --host docker:centos-7
python scripts/run/run.py --suite artifacts/tests-qt4-win-i386 --host windows-xp --json docs/results/<name>.json
```

`docker:<distro>` hosts are built in: a stock container of CentOS 7,
Ubuntu 16.04, 18.04 or 24.04, Debian 13, Fedora or Arch, with the libraries a
desktop has and Xvfb. Other hosts are described in
`scripts/run/hosts.local.json` (copy `scripts/run/hosts.example.json`; the file
is not tracked): `ssh` for Linux and macOS machines, `vmware` (vmrun) for
Linux and Windows guests, `virtualbox` (VBoxManage). A guest password is read
from the environment variable the host names, or asked for; it is never
written down.

`scripts/tests/linux-forward-check.py` runs the Linux suites on every
distribution at once and writes `docs/results/linux-forward-<date>.json`.

The old systems themselves (Windows 95, Mac OS X 10.2, Debian Sarge) were
installed and driven with tools that are specific to one lab and are not part
of Longreach Qt; [platforms](platforms.md) records what was run where.

## CI

`.github/workflows/repository-checks.yml` checks every push: Python syntax,
the coverage gate, the licence matrix, and `scripts/audit/repo_scan.py
--spdx` (an SPDX line in every source file; no host paths, e-mail addresses,
private keys, passwords or torrent links). Building the SDKs takes hours per
target and is not part of CI.
