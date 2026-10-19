# Where the build's inputs come from

Every file a build downloads is pinned: archives by SHA256 (in the Makefile,
`mk/*.mk`, the Dockerfiles and `scripts/fetch/`), Git projects by commit,
base images by digest. A pin stops the build when upstream changes a file; it
does not help when upstream deletes it, and a busy upstream (download.qt.io,
Docker Hub) rate-limits parallel builds. So the GitHub organisation
[OpenKaryonLab](https://github.com/OpenKaryonLab) keeps a copy of everything
that may be redistributed, and the build takes it from there. Where upstream
is somewhere else than GitHub, it is the fallback; the pin decides what is
accepted from either.

[`scripts/fetch/sources.json`](../scripts/fetch/sources.json) lists it:

| What | Copy (first) | Upstream (fallback) |
|---|---|---|
| Source archives (Qt, OpenSSL, GCC, LLVM, LLVM-MinGW, CMake, ninja, xcb-util-cursor) | release `sources` of [longreach-qt-sources](https://github.com/OpenKaryonLab/longreach-qt-sources) | the project's own site, unless that is GitHub (LLVM, LLVM-MinGW, CMake, ninja) |
| osxcross and the projects its `build.sh` clones (cctools-port, apple-libtapi, xar) | OpenKaryonLab/&lt;name&gt;, each pinned commit tagged `longreach/<first 12 hex digits>` | none: github.com/tpoechtrager is on GitHub too, so it is only where `mirror.py` copies from |
| Base images (Debian 12, Ubuntu 14.04-22.04, CentOS 7.9) | ghcr.io/openkaryonlab/&lt;name&gt; | Docker Hub, same digest |

- Archives: `scripts/fetch/fetch.py` (and `qt6-fetch-source.py`,
  `scripts/build/cmake.sh`) take a file `sources.json` lists from the copy;
  upstream is the fallback only when it is not on GitHub, and taking it prints
  a warning, since it means the copy lacks the file. The SHA256 is checked
  either way. Files that are not copied (Apple SDKs, Debian and Ubuntu
  packages) come from upstream only. `LONGREACH_MIRROR` names another copy;
  `LONGREACH_UPSTREAM_FIRST=1` tries upstream first, for a new pin whose file
  is not copied yet.
- osxcross and its projects are fetched by commit from the OpenKaryonLab
  copies only, `LAB_GIT/<project>.git` (`scripts/build/git-fetch-pinned.sh`).
  `scripts/build/osxcross-sources.sh` lays the projects out and osxcross'
  `TP_OSXCROSS_DEV` makes `build.sh` use them instead of cloning upstream
  branches, which move. compiler-rt (Qt 5 macOS) comes from the LLVM 14.0.6
  release archive.
- Base images are pinned by digest and pulled through `BASE_REGISTRY`, the
  copy by default. A `FROM` cannot fall back, so when ghcr.io is down, pull
  the same digests from Docker Hub:

      make qt5-linux-amd64 BASE_REGISTRY=docker.io/library

- Where an input comes from (`BASE_REGISTRY`, `LAB_GIT`, `LONGREACH_MIRROR`)
  is not part of an image's fingerprint
  (`scripts/build/ensure-image.py`), so switching sources rebuilds nothing.

Not copied, because their licences do not allow it: the Apple SDKs
(`MacOSX10.2.8`, `10.4u`, `10.7`, `14.0`) and Apple's Command Line Tools
package the 11.3 SDK is packed from. make fetches them into `downloads/` from
where they are published (phracker/MacOSX-SDKs, joseluisq/macosx-sdks,
swcdn.apple.com) and checks their SHA256 pins; keep your own copies, and put
them back in `downloads/` under the same names when those go away. The Debian Sarge and Ubuntu Lucid packages
(`scripts/fetch/locks/`) come from archive.debian.org and
old-releases.ubuntu.com, which are archives themselves.

Maintainers fill the copies with `scripts/fetch/mirror.py`, logged in to gh
(and to ghcr.io, for images) as one of the `publishers` in `sources.json`,
since what is published shows that account (pushes use gh's token too, not
the system credential helper); tags are made as the clone's own git identity:

    python scripts/fetch/mirror.py check            # sources.json against the build's pins
    python scripts/fetch/mirror.py check --online   # ... and the copies hold every pin
    python scripts/fetch/mirror.py repos --apply    # Git copies and longreach/<commit> tags
    python scripts/fetch/mirror.py archives --apply # release assets, uploaded when the SHA256 matches
    python scripts/fetch/mirror.py images --apply   # base images to ghcr.io

Images copied to ghcr.io start as private packages: make each one public in
the organisation's package settings, or builds without a login cannot pull
them (`check --online` with `docker logout ghcr.io` shows it).

The release only grows. A new version of an archive is a new file name, so an
update uploads that one file, and the files older tags of this repository
name stay where they were. A file already there under the same name but with
other content (upstream rolled it again) stops `archives`: keep the old one,
and give the new one, and its pin, a new name.

A new pin goes into `sources.json` too; `check` fails until it does, and
also when a Dockerfile takes a base image without `${BASE_REGISTRY}` and a
digest. Copy it before relying on it: `check --online` fails until the copy
holds it.
