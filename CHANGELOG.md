# Changelog

## Unreleased

- Qt 6 moves from 6.8.4 to 6.8.5, the LTS patch release published as open
  source in October 2026: about 690 fixes, among them CVE-2025-10728 and
  CVE-2025-10729 (Qt SVG), and newer bundled libpng, FreeType, libjpeg-turbo,
  libtiff, libwebp, HarfBuzz, PCRE2 and SQLite. The Windows 7 multimedia
  patches and the macOS camera patch follow the reworked Qt Multimedia
  sources; `windows/13` (Qt::Concurrent) is gone, Qt links it itself, and
  Qt 3D's Assimp no longer needs `_fstat64`. `macos/20` builds the Darwin
  media plugin without precompiled headers: since 6.8.5 it links
  Qt::Concurrent, and CMake then writes no rule for the C++ header its
  moc file expects, so the cross build stopped at once.
- Qt 6: the security fixes Qt has published for 6.8 since 6.8.5, as
  `patches/qt6/all/05`-`24`, one per CVE: CVE-2025-12385, CVE-2025-14576,
  CVE-2026-101201, -105923, -105924, -105946, -107157, -107472, -107590,
  -13326, -16762, -6210, -76151, -78253, -79616, -8168, -9499, -96432,
  -19248 and -82292 (QtCore, QtXml, QtNetwork, Qt SVG, Qt Quick, Qt 5 Core
  Compatibility, Qt NFC); `25` the Qt MQTT parser fixes with
  CVE-2026-107457; `26` and `27` memory-safety fixes from Qt's 6.12 branch
  for untrusted input without a CVE diff: QDom, QXmlStreamReader,
  qUncompress, CBOR, HTTP/2, the TIFF and ICNS readers.
- Qt 5: the security fixes Qt has published for 6.8 but not for 5.15,
  ported to 5.15.19 as `patches/qt5/all/09`-`26`, one per CVE:
  CVE-2025-12385, -14575, -5683, CVE-2026-101201, -105924, -105946, -107157,
  -107472, -107590, -11573, -13326, -16762, -19248, -78253, -79616, -8168,
  -82292 and -9499; `27` and `28` the QDom, TIFF and ICNS fixes of Qt 6's
  `all/26` and `all/27`. Qt SVG now draws at most 32 nested groups, as
  Qt 6.8 does since CVE-2026-8168.

## 0.1.0 - 2026-10-23

First public pre-release, source only.

- Static Qt 4.8.7, 5.15.19 and 6.8.4 SDKs built in Docker for Windows, Linux
  and macOS.
- Floors: Qt 4 from Windows 95 OSR2, Debian 3.1 Sarge and Mac OS X 10.2
  Jaguar (PowerPC) / 10.4 Tiger (Intel); Qt 5 from Windows XP SP3, Ubuntu
  10.04 and Mac OS X 10.6 (x86_64 and i386); Qt 6 from Windows 7 SP1,
  RHEL/CentOS 7 and macOS 10.13 (11.0 on Apple silicon). See
  [docs/platforms.md](docs/platforms.md) for what has run where.
- One build per Qt version, OS and architecture (`make qt<N>-<os>-<arch>`),
  each from that combination's floor; the Makefile's shared settings plus
  `mk/qt4.mk`, `mk/qt5.mk` and `mk/qt6.mk`.
- One patch series per Qt generation and OS; every input pinned by SHA256.
- The same eight test applications on all three generations, covering every
  public class each one ships; `scripts/run/run.py` runs them on Docker
  (including 32-bit images), SSH, VMware (including Windows 9x and NT 4),
  VirtualBox targets and the local machine.
- GPL-3.0-or-later; patches and mkspecs keep Qt's licences, so applications
  can still be built under the LGPL.

Also in this release:

- `make <target>-examples` for every target: the SDK when one of its inputs
  changed (`FORCE=1` rebuilds it anyway), then the test applications into
  `artifacts/tests-<image>/`. `make help` lists every target next to its
  `-examples` form.
- `make build-all` (every SDK) and `make build-all-examples` (every SDK and
  its test applications) ask before they start, build up to `BUILD_ALL_JOBS`
  targets at a time - no more than Docker's memory holds, started a few
  minutes apart while enough memory is free - build the failed ones again
  one at a time, and write logs and a summary to `build/build-all-<time>/`
  (`scripts/build/build-all.py`).
- Images and test artifacts take the target's name (`qt5-win-amd64`); a
  `LICENSE_PROFILE` other than the default adds itself
  (`qt5-win-amd64-lgpl-friendly`).
- Optional Linux libraries at run time: `scripts/build/dlopen` makes static
  stub archives that load a shared library on first use, so a binary starts
  where the library is missing and uses it where it is installed. A
  libwayland older than the one the stubs are made from counts as missing,
  and Qt uses xcb there.
- Qt 5 Linux: QtWayland; QtMultimedia with PulseAudio, ALSA and GStreamer
  1.0; QtSpeech with speech-dispatcher; QtBluetooth with BlueZ - all through
  those stubs (`patches/qt5/linux/04` and `05`).
- Qt 6 Linux amd64: QtWayland, through the same stubs.
- Qt 5 Linux arm64 is cross-built for Ubuntu 14.04 (glibc 2.19), with the
  Lucid build's static X libraries and modules.
- Qt 6 Linux arm64 is cross-built for RHEL/CentOS 7 aarch64 (glibc 2.17),
  with OpenSSL, D-Bus and QtWayland; `scripts/build/rpm-sysroot.py` makes its
  sysroot from the CentOS vault.
- Qt 6 macOS: `patches/qt6/macos/18` guards the Metal, save dialog and
  text-to-speech APIs newer than 10.13 that the availability audit found
  unguarded; `19` lets projects that use the SDK find QtNfc.
- Qt 4 Linux: `patches/qt4/linux/03` binds a GLX context only when it is not
  already current, which Debian 4.0's X server needs to keep a GL window's
  frame.
- `scripts/run/run.py --host qemu:<distro>` runs a suite on 64-bit
  distributions with glibc before 2.14, which a container host cannot run
  (`centos-5-x86_64`, `debian-4-amd64`).
- qt-selftest's macOS TLS check uses a temporary keychain, so it passes over
  SSH as well.
- Results: Qt 4 Linux amd64 8/8 on CentOS 5.11 and Debian 4.0; Qt 4 macOS
  i386 8/8 on Tiger 10.4.10 (QEMU, emulated Core Duo); Qt 5 and Qt 6 macOS
  8/8 on a clean macOS 10.13.6; Qt 4 Windows i386 8/8 on Windows 95 OSR2
  (QEMU). See [docs/platforms.md](docs/platforms.md).

### Since the first tag (2026-10-15)

- `scripts/audit/stop_words.py` checks the tree, the staged changes, commit
  messages and identities, the history or a push against a list of private
  words kept outside the repository (`.stopwords`); `scripts/audit/git_hooks.py
  install` runs it from pre-commit, commit-msg and pre-push hooks.
- A bare `make` prints `make help` instead of downloading the Qt 5 sources.
- `make qt6-linux-amd64` and `qt6-linux-arm64` download ninja and
  xcb-util-cursor themselves; a fresh clone had no rule for them.
- The Qt 6 cross targets and `make build-all` build qt6-host only when its
  inputs changed (`make build-qt6-host`), not again whenever Docker has
  dropped its cache. `make build-all` starts the next target at once after
  one whose image was current, without the five-minute gap.
- `DOCKER_BUILD_FLAGS` with a single flag (`DOCKER_BUILD_FLAGS=--progress=plain`)
  no longer stops `make build-<target>`.
- An SDK image is rebuilt only when what its own `docker build` uses changed:
  its Dockerfile, build arguments, the files it copies and (Qt 6 cross
  targets) qt6-host. Before, any change under `scripts/build/`, the
  Makefile or a generation's `mk/*.mk`, `docker/`, `patches/` or `cmake/`
  marked every image of that generation, or all of them, out of date.
  `PARALLEL_JOBS` is not part of it.
- The Qt 4 Linux and macOS images copy only `patches/qt4/all` and their own
  system's patches, and the Qt 6 images only the Qt and LLVM-MinGW archives
  from the build context instead of bind-mounting all of it, which gave the
  Docker cache a new key for any change in the repository.
- `make qt4-macos-ppc-examples` (and `qt4-macos-i386-examples`) no longer
  fails on Windows when an earlier run left its `imports/` folder.
- What the build downloads has a copy in the OpenKaryonLab organisation,
  and the build takes it from there first, upstream only when the copy lacks
  it, if upstream is not on GitHub as well (docs/sources.md,
  scripts/fetch/sources.json): source archives as the
  release `sources` of longreach-qt-sources (`fetch.py`,
  `qt6-fetch-source.py`, `cmake.sh`); osxcross and the projects its build.sh
  clones by branch (cctools-port, apple-libtapi, xar), now fetched by commit
  for every macOS image, from the copies only, since upstream is on GitHub
  too (`git-fetch-pinned.sh`); the base images, now pinned
  by digest and pulled through `BASE_REGISTRY` (ghcr.io/openkaryonlab, or
  docker.io/library). `LONGREACH_UPSTREAM_FIRST=1` reverses the order for a
  pin not copied yet. Where an input comes from is not part of an image's
  fingerprint, so switching sources rebuilds nothing.
  `scripts/fetch/mirror.py` checks the list against the pins (`check
  --online`: and against the copies) and fills the copies.
- The Qt 6 macOS images take the macOS SDK from `downloads/`, fetched by make
  with its SHA256 like every other input, instead of downloading it inside
  Docker; a kept copy of the SDK now works by putting it there.
- `LICENSE_PROFILE=lgpl-friendly` is refused by the Windows and macOS Qt 5/6
  targets, which do not leave the GPL-only modules out yet; before, they built
  an image under that name with the modules in it. Named on the make command
  line they stop before any download; `make build-all` skips them with that
  profile.
- Every image stops at a patch that does not apply; the loops of the Qt 4
  Windows, Qt 5 Windows and macOS and Qt 6 images used to go on with the next
  one. qt4-win-amd64 checks the DLLs of every test application, not only the
  last one's. `patch` runs with `--fuzz=0`, so a patch whose context has
  moved stops the build too, like `git apply`; the twelve Qt 4 Windows and
  Qt 6 patches that needed fuzz are written again to apply exactly, with the
  same result.
- `manifest.json` named the kit's licence MIT; it is GPL-3.0-or-later.
- `make qt5-linux-arm64` fetches the X sources it copies
  (`qt5-lucid-fetch.py --sources-only`); a fresh clone failed there.
- `qt6-linux-arm64` builds the OpenSSL version make fetched; `QT6_SOURCE`
  replaces an archive already in `downloads/`, with `make build-qt6-*` too,
  which took an image built from the old one as current; the Qt 6
  `-examples` targets no longer need CMake on the host.
- `LONGREACH_MIRROR` reaches the CMake downloads inside the images, and the
  Qt 6 source fetch goes on to the Qt sites when the copy fails in any way, not
  only with a 404.
- `make verify-downloads` checks every pinned file in `downloads/` once, and
  the Sarge and Lucid packages against their locks (`--verify-only`), and says
  how many it checked; `make build-all` runs it before it starts. A
  `QT6_SOURCE` archive is the user's, so it is not held to the 6.8.4 pin.
- The Qt 5 macOS SDK is packed in the digest-pinned Ubuntu 22.04 image (as
  linux/amd64, under the download lock), and the run.py QEMU helper is built
  from it (as linux/amd64 on any host, showing Docker's output when that
  fails); `fetch-macos-sdk.sh` fails instead of
  keeping a short archive, and `qt5-extract-tests` fails when a binary could
  not be copied.
- `mirror.py`: `repos` can run again (existing `longreach/` tags are kept, a
  refused push is reported); `archives` checks a download before keeping it
  and reports a release file GitHub gives no SHA256 for; `check` matches each
  image's tag and digest together, looks at every Dockerfile and the scripts
  in subfolders, and finds images named by tag only in make and commit pins
  `sources.json` does not list. `archives` creates the `downloads/` folders,
  downloads under the build's lock, goes on after a run that stopped between
  creating the repository or release and the first upload, and fails on a
  local file that does not match its pin. A dry run needs no git identity.
- `scripts/build/qt6-build-project.py` prepares the Qt image of every platform
  with `make build-qt6-<platform>`, for the licence profile it then builds in
  (`--license-profile`, or `LICENSE_PROFILE`); for Linux and macOS it used to run its own
  `docker build` without the inputs make fetches, and `--download` (gone)
  fetched a wrongly named archive without a SHA256.
- A `QT6_VERSION` other than 6.8.4 is not downloaded without
  `QT6_ARCHIVE_SHA256` (or a `QT6_SOURCE` archive); it used to be taken unchecked.
- One build at a time on a machine: a second `make build-all`, `make
  build-<target>` (or `<target>-examples`) or plain `make <target>` started
  while one of the first three runs stops with an error that points at `make
  build-all BUILD_ALL_JOBS=N`, which builds several targets at once within
  the memory; a second one used to wait, or, next to a build-all, run
  alongside it. A plain `make <target>` only checks when it starts and does
  not keep a later build out; `make build-<target>` does. An image that is already current is still handed out (so
  `qt6-build-project.py` works during a build-all). The same target is never built
  twice at once (an image built as a prerequisite, qt6-host, waits for its
  own build instead). Two targets that need the same input
  no longer download it into the same `.part`: the second waits for the first
  (locks under `build/locks/`).
- `DOWNLOAD_DIR` is fixed to `downloads/`, which the Dockerfiles copy from;
  setting it on the make command line is an error instead of a broken build.
- The xcb and libxkbcommon sources Qt 5 Linux builds are listed in
  `sources.json` and come from the OpenKaryonLab copy first.
- `make qt6-host-smoke` skips gl-heavy-gallery when the host image has no Qt 3D
  or Data Visualization, as its comment always said, instead of failing the
  configure step.
- The Qt 4 and Qt 5 Linux sysroots take only the packages their lock names,
  each checked against its SHA256; a `.deb` an older lock left in
  `downloads/` used to be extracted too.
- The Qt 4 macOS i386 build reuses its source tree (a cache mount, which
  outlasts `--no-cache`) only while the archive and the patches are the same,
  and only once every patch went on; a patch removed or renamed used to stay
  applied.
- The CentOS 7 aarch64 sysroot of qt6-linux-arm64 comes from a lock
  (`scripts/fetch/locks/qt6-centos7-aarch64-packages.json`, written with
  `rpm-sysroot.py --write-lock`): 72 packages by https URL and SHA256. It
  used to take the newest packages over http and trust the checksums of the
  index fetched with them.
- qt4-macos-ppc takes xar from the OpenKaryonLab copy at its pinned commit; the
  ppc-test branch of osxcross cloned xar's master from upstream.
- `qt5-lucid-lock.py` reads the Lucid indexes over https; the locks written
  again that way name the same packages and SHA256s, now by https URL.
- The Debian 12 and Ubuntu 22.04 stages install their packages from the
  archive as it was at the date in `scripts/build/apt-snapshot.sh`
  (20261019T000000Z, through snapshot.debian.org and snapshot.ubuntu.com), so
  an image built later gets the same versions; `APT_SNAPSHOT=<date>` takes
  another date, `APT_SNAPSHOT=none` the live archive. An index apt cannot
  fetch stops the build (`APT::Update::Error-Mode`); `apt-get update` only
  warned and the install took older packages from the indexes it had. An
  image's fingerprint takes only the build arguments its Dockerfile declares.
- The Ubuntu 14.04-18.04 stages update apt through
  `scripts/build/apt-update.sh`, which fails when an index could not be
  fetched; their apt reported it as a warning and installed older packages.
- Downloads inside the images are tried again before a build fails: CMake
  (`cmake.sh`, qt6-linux-amd64) five times, the osxcross projects
  (`git-fetch-pinned.sh`) and the CentOS 7 aarch64 packages three times, the
  packages apt installs five times (Ubuntu 14.04-18.04) or ten (Debian 12,
  Ubuntu 22.04). One failed request ended an image build an hour in.
- Stopping `make build-all` (Ctrl-C, Ctrl-Break, SIGTERM, a closed
  terminal on Linux and macOS) stops every build it started, with all their
  processes, also the ones whose parent has gone: each gets a minute to end
  by itself (docker cancels its build; interrupting again ends them at
  once), then it is killed; build-all exits 130. So does any error that
  ends build-all, with its own exit. The summary lists what finished and
  what was stopped either way. On Windows build-all holds its builds in a
  job object, so they end with it however it ends (a closed console or a
  killed build-all ends them at once). A signal that was ignored when
  build-all started (`nohup`) stays ignored. Stopping make alone left
  ensure-image.py and docker build running.
- A `QT6_SOURCE` archive already in place is not copied again by each make
  of a build, and one with other content does not replace it while another
  Qt 6 target is being built from it through `make build-<target>`,
  `<target>-examples` or `make build-all` (their build locks are held during
  the replacement, which is one rename; a plain `make qt6-<target>` is a bare
  docker build and takes no lock). An image's inputs are read under its
  target's lock and again after the build: one that was there and changed
  or went, or a file new outside `downloads/`, fails the build instead of
  labelling the image with inputs it was not built from; what the make
  fetched into `downloads/` is added to the label. What `fetch.py`, the
  Sarge, Lucid and Qt 6 fetchers download is written to `build/partial/`
  (`downloads/.partial/` when `downloads/` is linked to another drive;
  beside the file only in a folder linked to a drive of its own) and moved
  in only once its SHA256 matches the pin; a wrong local Qt 6 archive is
  named. A `.part` an earlier version of them left beside a file is
  removed. A
  connection cut mid-file, also one the server just closes before the length
  it announced, is retried by `fetch.py`; `qt6-fetch-source.py` goes on to
  the next source.
- `make download-qt-mobility` and `scripts/fetch/fetch-git-archive.py` are
  gone: no target used Qt Mobility.
