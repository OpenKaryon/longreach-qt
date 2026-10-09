# Contributing

Thank you for helping old systems keep running new software.

- **Reports**: say which target and image, the system it ran on, and attach
  `smoke-report.txt` and the application's log.
- **Patches to Qt** go into `patches/qt<N>/<os>/` as the next number of the
  series, with an SPDX line (Qt's licence, see [licensing](docs/licensing.md))
  and a header: what it changes, why, how it was checked. Newer APIs are
  selected at run time or by the deployment target, never removed. Check that
  the whole series still applies to the pristine Qt archive.
- **Tests**: a patch that changes behaviour comes with a check in `tests/`,
  ideally one that fails on the floor without it. The suite must keep
  building on Qt 4, 5 and 6 (the coverage gate in CI tells you if a class
  dropped out).
- **Kit changes**: one Dockerfile per target, every input pinned by SHA256,
  new source files with an SPDX line (`scripts/audit/repo_scan.py --spdx`).
  Commit messages say why, not only what.
- **Results**: add a result file from `scripts/run/run.py --json` only for a
  run of the current tree, and update [platforms](docs/platforms.md).

By contributing you agree that your contribution is licensed under the terms
of the files it changes: GPL-3.0-or-later for the kit, Qt's licences for
patches and mkspecs.
