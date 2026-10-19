# Scripts

Grouped by the workflow that calls them.

| Directory | What |
|-----------|------|
| `fetch/` | Getting build inputs: `fetch.py` (download + pinned SHA256, used by every Makefile download rule), `mirror.py` and `sources.json` (the OpenKaryonLab copies), the macOS SDK, the Qt 6 source, the Debian Sarge and Ubuntu Lucid package locks |
| `build/` | Copied into the Docker builds or driving them: OpenSSL, CMake, licence profiles, the Qt 5 add-ons, the test suite builds (`tests.sh` for Qt 5/6 with CMake, `qt4-tests.sh` for Qt 4 with qmake), the per-target helpers (`qt4-*`, `qt5-*`, `qt6-*`), `ensure-image.py`, `build-all.py` (every target's SDK and test applications in one run) |
| `audit/` | Checks on built binaries and on the tree: Mach-O and PE import audits (`macos-symbol-audit.sh`, `qt6-macos-audit.sh`, `qt6-win7-audit.sh`, `qt4_win95_imports.py`), static-dependency checks (`qt4-check-deps.sh`), the Qt API database refresh (`qt_api_audit.py`), the repository leak scan (`repo_scan.py`), the stop-word check for private names (`stop_words.py`, its list kept outside the repository) and the Git hooks that run it (`git_hooks.py`) |
| `tests/` | Around the test suite: extracting binaries, manifests, the coverage gate (`check_coverage.py`) and its class databases, the Linux forward check |
| `licenses/` | `report.py`, which reads `licenses/module-matrix.json` and enforces the licence profiles |

Generated `coverage-gap*.txt` files are written to `scripts/tests/` and ignored by git.
