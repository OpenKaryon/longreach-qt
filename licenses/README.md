# Licences

Every source file names its licence in an `SPDX-License-Identifier` line.

| Licence | Applies to |
|---------|------------|
| GPL-3.0-or-later (`../LICENSE`) | The kit itself: Dockerfiles, the Makefile, scripts, CMake toolchains, the test suite |
| LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only | What becomes part of Qt 5 and Qt 6: `patches/qt5`, `patches/qt6`, Qt 5 mkspecs, the runtime objects linked into Qt 5 applications |
| LGPL-2.1-only OR GPL-3.0-only | What becomes part of Qt 4: `patches/qt4`, Qt 4 mkspecs, the Windows 95 runtime object |
| GPL-3.0-or-later WITH GCC-exception-3.1 | The header added to the Jaguar PowerPC libgcc |

Code that ends up inside Qt, or inside every application built with an SDK,
keeps Qt's own terms, so the licence profiles in `module-matrix.json` (and the
`lgpl-friendly` build) stay valid for applications.

The texts are in this directory, named by SPDX identifier;
GPL-3.0-only.txt is the same text as `../LICENSE`.

`module-matrix.json` classifies each Qt module by licence for the profiles;
`scripts/licenses/report.py` reads it.

Copyright (C) 2026 OpenKaryon.
