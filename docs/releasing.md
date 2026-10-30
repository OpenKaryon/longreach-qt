# Releasing

## Versions

`MAJOR.MINOR.PATCH`. Until 1.0 a minor version may change target names,
image layouts and patch numbering; a patch version only fixes. The Qt versions
built (4.8.7, 5.15.19, 6.8.5) are part of a release's description, not of its
number: moving to a newer Qt 5.15 or 6.8 patch release is a minor version.

## What a release contains

- [0.1.0](releases/0.1.0.md): the source tree only, as a GitHub pre-release.
- 0.2.0 (planned): source-only pre-release; prebuilt SDK images deferred.
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

## 0.2.0 preparation

The selected scope is a source-only pre-release. The
[candidate notes](releases/0.2.0.md) describe its new validation and
remaining gaps. This is a locally prepared candidate, not a published
version; README and CHANGELOG retain that distinction.

- [x] Qt 6 version change selects minor version 0.2.0.
- [x] Record all 22 final Windows/macOS runs and current Qt 5/6 Linux
  amd64 results, with executable SHA256 values.
- [x] Keep ARM, PowerPC, older-floor gaps and NT4 investigation explicit.
- [x] Prepare CHANGELOG and source-only release notes.
- [ ] A fresh full build from empty downloads remains unverified by
  this preparation; previous cached builds are identified in the notes.
- [ ] Resolve the remaining runtime gaps or explicitly accept them as
  pre-release limitations at publication review.
- [ ] Set the release date, tag `v0.2.0`, push and publish only after
  separate authorization.

The local delivery consists of a Git source archive, release notes, a
preflight report, a provenance manifest and SHA256SUMS. Packaging verifies
archive contents against the candidate commit and excludes local
downloads, build outputs, test artifacts and host configuration.

## Updates

Security fixes in OpenSSL 3 are picked up by moving `OPENSSL_VERSION` and its
SHA256; OpenSSL 1.0.2u (every Qt 4 target but win-amd64) receives none, which is why it
is used only where nothing newer runs. Newer Qt patch releases are adopted
when the patch series still apply and the suite passes on every floor.
