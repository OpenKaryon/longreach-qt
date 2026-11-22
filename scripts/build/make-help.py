#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Print the targets `make help` lists: each SDK target next to its -examples.

    python scripts/build/make-help.py qt4=4.8.7 qt5=5.15.19 qt6=6.8.5 TARGET...

The Makefile passes its Qt versions and the targets its simple-build-targets
definitions made.
"""
import sys


def main() -> int:
    versions = dict(a.split('=', 1) for a in sys.argv[1:] if '=' in a)
    targets = [a for a in sys.argv[1:] if '=' not in a]
    width = max(len(f'make {t}') for t in targets) + 2
    print('make <target>            the SDK: a Docker image with the toolchain and Qt')
    print('make <target>-examples   desktop: prepare the SDK if needed, then build applications')
    print('                         Android: build and package APKs with a ready SDK (no SDK build)')
    for generation, version in versions.items():
        print(f'\nQt {version}')
        for target in targets:
            if target.startswith(generation + '-'):
                print(f'  {f"make {target}":<{width}}make {target}-examples')
    print('\nAndroid (Windows + PowerShell 7; docs/android-build.md):')
    print('  SDK and -examples only; use scripts/run/ Android runners to run saved APKs')
    print('  make qt4-android-arm-legacy      original API4 ARM combined build/package; no SDK phases')
    print('\nEvery target in one run (asks first; hours to a day or more):')
    print('  make build-all               every SDK')
    print('  make build-all-examples      every SDK and its test applications')
    print('  BUILD_ALL_JOBS=2 builds two at once; scripts/build/build-all.py --help has the rest')
    print('  Android runs alone; build-all-examples schedules SDK then ready APKs')
    print('Settings (PARALLEL_JOBS, LICENSE_PROFILE, ...): docs/getting-started.md')
    return 0


if __name__ == '__main__':
    sys.exit(main())
