# Releasing

## Versions

`MAJOR.MINOR.PATCH`. Until 1.0 a minor version may change target names,
image layouts and patch numbering; a patch version only fixes. The Qt versions
built (4.8.7, 5.15.19, 6.8.5) are part of a release's description, not of its
number: moving to a newer Qt 5.15 or 6.8 patch release is a minor version.

## What a release contains

- 0.1.0: the source tree only, as a GitHub pre-release.
- Later: prebuilt Windows and Linux SDK images for the targets whose results
  are recorded for that release. macOS SDK images will not be published -
  they contain Apple's SDK, which may not be redistributed; build them
  yourself.

## Checklist

1. Every target builds from a clean `downloads/` (`make verify-downloads`
   checks the pinned inputs).
2. For each target, the suite has run on its floor and on a current system,
   and the result files in `docs/results/` come from this tree's commit
   (`scripts/run/run.py --json`). Targets that could only be built are marked
   so in [platforms.md](platforms.md).
3. The coverage gate passes and `scripts/audit/repo_scan.py --spdx` is clean.
4. `CHANGELOG.md` lists what changed for users.
5. Tag `vX.Y.Z`, push the tag, create the GitHub release from it.

## Updates

Security fixes in OpenSSL 3 are picked up by moving `OPENSSL_VERSION` and its
SHA256; OpenSSL 1.0.2u (every Qt 4 target but win-amd64) receives none, which is why it
is used only where nothing newer runs. Newer Qt patch releases are adopted
when the patch series still apply and the suite passes on every floor.
