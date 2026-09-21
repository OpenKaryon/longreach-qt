#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Fail unless every GLIBC_x.y version an ELF file needs is <= the limit."""
import re
import subprocess
import sys

path, limit = sys.argv[1], tuple(int(x) for x in sys.argv[2].split('.'))
text = subprocess.run(['readelf', '-V', '--wide', path], stdout=subprocess.PIPE, universal_newlines=True, check=True).stdout
needed = sorted({tuple(int(x) for x in v.split('.')) for v in re.findall(r'GLIBC_(\d+(?:\.\d+)+)', text)})
newest = needed[-1] if needed else (0,)
print(path, 'needs GLIBC up to', '.'.join(map(str, newest)))
too_new = [v for v in needed if v > limit]
if too_new:
    sys.exit('too new: ' + ', '.join('GLIBC_' + '.'.join(map(str, v)) for v in too_new))
