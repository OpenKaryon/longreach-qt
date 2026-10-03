#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Produce a Tiger-compatible application bundle around a flat executable."""
import os
from pathlib import Path
import plistlib

name = os.environ['TARGET_NAME']
bundle = Path(os.environ['BUNDLE'])
with (bundle / 'Contents/Info.plist').open('wb') as stream:
    plistlib.dump({'CFBundleExecutable': name, 'CFBundleName': name,
                  'CFBundleIdentifier': 'org.openkaryon.longreach-qt.' + name,
                  'CFBundlePackageType': 'APPL', 'CFBundleVersion': '4.8.7',
                  'LSMinimumSystemVersion': '10.4', 'NSHighResolutionCapable': False}, stream)
(bundle / 'Contents/PkgInfo').write_bytes(b'APPL????')
