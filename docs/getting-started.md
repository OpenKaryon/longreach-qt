# Getting started

## Host requirements

- Docker with BuildKit (Docker Desktop on Windows or macOS, Docker Engine on
  Linux), able to run `linux/amd64` containers; `linux/386` and `linux/arm64`
  targets run under the emulation Docker Desktop ships, or binfmt/QEMU on Linux.
- GNU make and Python 3.11 or newer on the host. On Windows the Makefile works
  from Git Bash with make installed.
- Disk: about 30 GB free for one target (a Qt source tree, its build tree and
  the Docker layers), 400 GB or more to build every target. Memory: 16 GB;
  linking the large Qt modules can take more than 1 GB per compiler job, so
  cap the jobs with `PARALLEL_JOBS` on smaller machines.
- Network access for the first build of each target: the inputs are fetched
  once into `downloads/` and checked against their pinned SHA256.

## Building an SDK

```sh
make qt5-linux-amd64
```

builds the image `qt5-linux-amd64`: the toolchain and the
static Qt installed under `/usr/local/Qt-5.15`, plus the test suite built
against it under `/opt/qt-smoke-bin`. The names of every target are on the
[target pages](targets/); `make -n <target>` shows what it would do. The
Makefile holds the shared settings; each generation's inputs, images and
targets are in `mk/qt4.mk`, `mk/qt5.mk` and `mk/qt6.mk`.

`make <target>-examples` (`make qt5-win-i386-examples`) builds the SDK only
when an input changed - it fingerprints the make settings, the Dockerfile,
the patches and scripts the target uses, and labels the image with it - and
then builds the test applications into `artifacts/tests-<image>/`.
`make build-<target>` does the first half alone. `FORCE=1` rebuilds the
image anyway, `NO_CACHE=1` rebuilds it without the Docker cache.

`make build-all-examples` runs `<target>-examples` for every target
(`make build-all`: `build-<target>`, the SDKs alone) after asking whether to
start (`YES=1` does not ask). Up to `BUILD_ALL_JOBS` targets build at once:
no more than Docker's memory holds at about 2 GB per compiler job
(`PARALLEL_JOBS` 6 makes 12 GB a build, so a 31 GB Docker VM runs two), one
start every five minutes and only while 12 GB is free. The failed ones are
built again one at a time, and the logs and a summary go to
`build/build-all-<time>/`.
`BUILD_ALL_ARGS` passes more options to `scripts/build/build-all.py`
(`--only`, `--skip`, `--min-free-gb`, `--gb-per-job`, `--start-gap`, `--retries`; see its
`--help`).

Useful variables:

| Variable | Default | |
|----------|---------|---|
| `PARALLEL_JOBS` | 6 | compiler jobs inside the build |
| `LICENSE_PROFILE` | `gpl-enabled` | `lgpl-friendly` leaves out the GPL-only Qt modules ([licensing](licensing.md)); another profile is added to the image name (`qt5-linux-amd64-lgpl-friendly`) |
| `DOWNLOAD_DIR` | `downloads` | where the inputs are kept |
| `QT4_VERSION`, `QT5_VERSION`, `QT6_VERSION` | 4.8.7, 5.15.19, 6.8.4 | another version also needs its `*_SHA256` (and patches that apply to it) |
| `QT5_MACOS_TARGET_AMD64` | 10.6 | a higher Qt 5 macOS deployment target leaves out the static OpenSSL and libc++ the old systems need |
| `QT6_SOURCE` | | a Qt 6 source archive of your own, for LTS releases not yet public |

## Using an SDK

Run your build inside the image, with your sources mounted:

```sh
docker run --rm -v "$PWD:/src" -w /src qt5-win-i386 \
    'mkdir -p build && cd build && qmake ../app.pro && make -j8'
```

The Qt 4 and Qt 5 images take the command as one argument (their
entrypoint is `bash -l -c`); with a Qt 6 image write `bash -c '...'`.

Qt 4 and Qt 5 SDKs carry qmake (configured for the target: `qmake` in the
image cross-compiles); Qt 5 and Qt 6 SDKs work with CMake through the
toolchain files under `cmake/`. `scripts/build/qt6-build-project.py` builds a
CMake project against a Qt 6 image.

Everything is static, so the application links the Qt modules it uses and
nothing has to be shipped beside it except the plugins Qt needs at run time
(already linked in) and, on Linux, the system libraries a desktop has. Two
link flags are worth adding for size: `-Wl,--gc-sections` on Linux and
Windows, `-Wl,-dead_strip` on macOS (Qt's own objects are compiled with one
section per function, so the linker can drop what you never call; measured
12% on Linux, under 1% on Windows, where the compiler already does most of
it). The Qt 4 mkspecs already pass them.

Windows binaries built with the Qt 5 and Qt 4 SDKs need no MinGW runtime DLLs
(`-static-runtime` and the Qt 4 mkspec patch). On Linux, link
`-static-libgcc -static-libstdc++` if your application must start on the
floor: a newer libstdc++ than the floor's would otherwise be required. The
Qt 4 and Lucid mkspecs do that already.

## Images and tags

Images are built locally and tagged `qt<N>-<os>-<arch>` (`qt5-macos-i386`,
`qt4-win-i386`); a `LICENSE_PROFILE` other than the default adds itself
(`qt5-macos-i386-lgpl-friendly`). Qt 4 images carry no profile: every Qt 4
module is under the LGPL. No prebuilt images are published for
0.1.0; [releasing.md](releasing.md) says what later releases will publish.

## Cleaning up

`downloads/` holds every fetched input and can be deleted; it is refilled on
the next build. `make prune-cache` drops the Docker build cache and dangling
images, `make clean` removes `build/` and `artifacts/`. `make image-sizes` lists the kit's images and their
sizes.
