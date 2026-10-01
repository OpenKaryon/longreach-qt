# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Modern GNU ld no longer resolves the TLS resolver through implicit DSO
# dependencies. Match modern glibc's explicit loader entry, using Sarge's own
# loader. This changes only a link-time text file, never the runtime binaries.
import os

loader = {'i386': 'ld-linux.so.2', 'amd64': 'ld-linux-x86-64.so.2'}[os.environ.get('SARGE_ARCH', 'i386')]
path = '/work/sysroot/usr/lib/libc.so'
with open(path) as stream:
    text = stream.read()
if loader not in text:
    old = 'GROUP ( /lib/libc.so.6 /usr/lib/libc_nonshared.a )'
    assert old in text, 'Unexpected Sarge libc linker script'
    with open(path, 'w') as stream:
        stream.write(text.replace(old, old[:-1] + 'AS_NEEDED ( /lib/' + loader + ' ) )'))
