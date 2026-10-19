# Licensing the SDK and applications built with it

Longreach Qt itself - the Dockerfiles, Makefile, scripts, CMake toolchains and
the test suite - is GPL-3.0-or-later, Copyright (C) 2026 OpenKaryon
([`LICENSE`](../LICENSE)). What becomes part of Qt keeps Qt's terms:

| Files | Licence |
|-------|---------|
| `patches/qt5`, `patches/qt6`, the Qt 5 mkspecs, the runtime objects linked into Qt 5 applications | LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only (Qt 5/6's own) |
| `patches/qt4`, the Qt 4 mkspecs, the Windows 95 runtime object | LGPL-2.1-only OR GPL-3.0-only (Qt 4.8's own) |
| the Jaguar libgcc header (`scripts/build/qt4-macos-jaguar/libgcc-dlfcn.h`) | GPL-3.0-or-later WITH GCC-exception-3.1 |

Every source file names its licence in an `SPDX-License-Identifier` line; the
texts are in [`licenses/`](../licenses/). Because the patched Qt stays under
Qt's licences, an application built with a Longreach Qt SDK can be distributed
under the LGPL rules - the GPL of the kit covers the build tooling, not what
you build with it.

Qt, its add-on modules, OpenSSL, the toolchains and everything else an SDK
contains keep their own terms. The strongest applicable terms of the libraries
actually linked into an application determine how that combined binary may be
distributed. Apple's SDKs are fetched from Apple for each build and never
redistributed; Apple licenses them for use on Apple hardware.

This is an engineering guide, not legal advice. The authoritative terms are
the license files shipped with each source module and, where applicable, the
user's commercial agreement with The Qt Company.

## Profiles

| Profile | Modules admitted | Consequence for an application |
|---|---|---|
| `lgpl-friendly` | MIT/BSD/LGPL Qt modules; no GPL-only add-ons | Application code may use another license, including a proprietary one, if all LGPL obligations are met |
| `gpl-enabled` | Everything above plus GPL-only Qt add-ons | A distributed application that links a GPL-only module must use GPL-compatible terms and provide corresponding source, unless commercial Qt terms cover it |
| `commercial-qt` | Same technical module set as `gpl-enabled` | Rights come from the user's commercial Qt agreement; selecting this name does not grant a license |

Select the profile on a Make target with `LICENSE_PROFILE`. `lgpl-friendly`
is enforced by the Linux Qt 5/6 images; the Windows and macOS ones do not
leave the GPL-only modules out yet, so their targets refuse it rather than
build an image that carries the name:

```sh
make qt5-linux-amd64 LICENSE_PROFILE=lgpl-friendly
make qt5-linux-amd64 LICENSE_PROFILE=gpl-enabled
make qt6-linux-amd64 LICENSE_PROFILE=commercial-qt
```

A profile other than the default is part of the Docker image and artifact
name, for example `qt5-linux-amd64-lgpl-friendly`, so two profiles cannot
silently overwrite one another; the default keeps the plain name
(`qt5-linux-amd64`). `gpl-enabled` is the default because it is the full
module set. The default is compatibility,
not a recommendation for proprietary applications.

“GPL-enabled” is the broader profile. GPL code can be combined with compatible
MIT and LGPL code; the reverse restriction matters: an LGPL-friendly product
must not accidentally link a GPL-only module.

The machine-readable source of this table is
[`licenses/module-matrix.json`](../licenses/module-matrix.json). Build and
artifact tooling must consume that file rather than maintaining another list.

## Static linking matters

Every SDK produced here is static. For an LGPL library, a distributor must let
the recipient replace the LGPL component and relink the application. Publishing
the complete application source is one way to make that practical; otherwise
the distributor normally needs to provide suitable object files, library
sources, notices and relinking/install instructions. Merely saying “the
application is MIT” does not discharge those obligations.

For a GPL-only library, static versus dynamic linking does not create an
LGPL-style escape: a distributed combined application needs GPL-compatible
terms, unless the user has commercial rights for that module.

## Current smoke applications

The applications are separate executables. Running or shipping the folder does
not fuse them into one combined program, so classify each executable by what it
links:

| Application | Open-source classification today | Reason |
|---|---|---|
| `qt-selftest` | Qt 4: LGPL-friendly; Qt 5/6: GPL-enabled | Qt 5/6 link Qt Network Authorization; Qt 6 also links available GPL-only IoT/virtual-keyboard modules |
| `gl-heavy-gallery` | Qt 4: LGPL-friendly; Qt 5/6: GPL-enabled | Qt 4 uses LGPL QtOpenGL; Qt 5/6 link Qt Charts and Qt Data Visualization |
| `widgets-gallery` | LGPL-friendly | No GPL-only module linked |
| `graphics-gallery` | LGPL-friendly | No GPL-only module linked |
| `quick-qml-gallery` | Qt 4: LGPL-friendly; Qt 5/6: GPL-enabled when Qt Quick 3D is available | Its Qt Quick 3D checks link the GPL-only Qt Quick 3D when the SDK contains it; the `lgpl-friendly` build has none, so the checks are left out |
| `painting-lab` | LGPL-friendly | No GPL-only module linked |
| `multimedia-lab` | LGPL-friendly | Qt Multimedia and Qt TextToSpeech are LGPL options |
| `network-gui` | Qt 4: LGPL-friendly; Qt 5/6: GPL-enabled when Qt HTTP Server is available | The Qt 5/6 HTTP demonstration links Qt HTTP Server when the SDK contains it; otherwise it uses Qt Network |
| `smoke-runner` | LGPL-friendly | Starts sibling processes; it does not link their Qt modules |

If all example source code were combined into **one** executable, that binary
would be GPL-enabled because it would link the GPL-only modules used by
`qt-selftest`, `gl-heavy-gallery`, `network-gui` and `quick-qml-gallery`. Keeping the examples separate preserves a
useful distinction: the other examples do not inherit GPL merely because
another executable in the same artifact does.

Qt MQTT checks live in `qt-selftest`, which is already GPL-enabled in a full
Qt 5/6 build. Qt HTTP Server support is now present in `network-gui`; the
machine-readable matrix conservatively classifies the Qt 5/6 executable as
GPL-enabled because it can link that module in a full SDK. The
`lgpl-friendly` smoke build does not discover GPL-only modules, so its
`network-gui` uses the Qt Network fallback instead.

The enforced implementation is the Qt 5/6 Linux path (amd64, i386, arm64). Under
`lgpl-friendly`, Qt configure omits Charts, Data Visualization, Quick3D,
Network Authorization and Virtual Keyboard plus the corresponding Qt 6 GPL
add-ons. The smoke CMake project independently refuses to discover those
modules, removes Network Authorization from `qt-selftest`, and omits the Qt 5/6
`gl-heavy-gallery` target whose primary subjects are GPL-only. This second gate
is intentional: an SDK assembled elsewhere must not be able to bypass the
profile merely by still containing a forbidden archive.

## Commercial Qt

The build kit cannot confer commercial Qt rights. A `commercial-qt` build
profile only records the user's assertion that the SDK will be used under an
applicable commercial agreement. The manifest must say this explicitly; it is
not a license key and not a substitute for reviewing that agreement.
