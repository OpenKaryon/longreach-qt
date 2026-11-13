# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
import os
from pathlib import Path
import re

include = Path('/opt/sysroot-xp/include')
intrin = include / 'intrin.h'
text = intrin.read_text()
for symbol in ('_m_prefetchw', '_mm_movedup_pd', '_mm_movehdup_ps', '_mm_moveldup_ps'):
    text, removed = re.subn(r'^[ \t]*__MACHINEX86X[^\n]*\b' + symbol + r'\([^\n]*\n', '', text, flags=re.M)
    assert removed <= 1
intrin.write_text(text)

comdef = include / 'comdef.h'
text = comdef.read_text()
original = '__debugbreak();'
if original in text:
    assert text.count(original) == 1
    comdef.write_text(text.replace(original, 'DebugBreak();'))


if os.environ['XP_ARCH'] == 'amd64':
    # Match the declared return type in both branches of the legacy wrapper.
    stralign = include / 'stralign.h'
    text = stralign.read_text()
    for function in ('wcschr', 'wcsrchr'):
        old = f'return {function}((PCWSTR)String,Character);'
        assert text.count(old) == 1
        text = text.replace(old, f'return (PUWSTR_C) {function}((PCWSTR)String,Character);')
    stralign.write_text(text)

# New Clang headers can supply _xgetbv as a macro before MinGW's header.
intrinsics = include / 'psdk_inc/intrin-impl.h'
text = intrinsics.read_text()
original = '#if __INTRINSIC_PROLOG(_xgetbv)'
replacement = '#if !defined(_xgetbv) && __INTRINSIC_PROLOG(_xgetbv)'
if original in text:
    assert text.count(original) == 1
    intrinsics.write_text(text.replace(original, replacement))
else:
    assert replacement in text
