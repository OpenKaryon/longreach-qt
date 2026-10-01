# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon

"""Write Linux newc cpio using the sysroot's real Unix file metadata."""
from __future__ import print_function
import gzip
import os
import stat

root = '/work/sysroot'
output = '/out/sarge-initramfs.cpio.gz'
excluded = ('usr/include', 'usr/share/doc', 'usr/share/man', 'usr/share/info',
            'usr/share/locale', 'proc/', 'tmp/', 'var/cache/', 'root/')


def excluded_path(name):
    return any(name == p.rstrip('/') or name.startswith(p.rstrip('/') + '/') for p in excluded)


with gzip.GzipFile(output, 'wb', compresslevel=6, mtime=0) as archive:
    def entry(name, metadata, data):
        name = (name if isinstance(name, bytes) else name.encode('utf-8')) + b'\0'
        fields = [metadata.st_ino & 0xffffffff, metadata.st_mode, 0, 0, 1, 0,
                  len(data), 0, 0, os.major(metadata.st_rdev), os.minor(metadata.st_rdev), len(name), 0]
        header = ('070701' + ''.join('%08x' % value for value in fields)).encode('ascii')
        archive.write(header + name)
        archive.write(b'\0' * (-(len(header) + len(name)) % 4))
        archive.write(data)
        archive.write(b'\0' * (-len(data) % 4))

    for parent, dirs, files in os.walk(root):
        relative = os.path.relpath(parent, root)
        if relative == '.':
            relative = ''
        dirs[:] = sorted(d for d in dirs if not excluded_path('/'.join(p for p in (relative, d) if p)))
        for name in sorted(dirs + files):
            relative_name = '/'.join(p for p in (relative, name) if p)
            if excluded_path(relative_name):
                continue
            path = os.path.join(parent, name)
            metadata = os.lstat(path)
            if stat.S_ISREG(metadata.st_mode):
                with open(path, 'rb') as source:
                    data = source.read()
            elif stat.S_ISLNK(metadata.st_mode):
                target = os.readlink(path)
                data = target if isinstance(target, bytes) else target.encode('utf-8')
            elif stat.S_ISDIR(metadata.st_mode) or stat.S_ISCHR(metadata.st_mode) or stat.S_ISBLK(metadata.st_mode):
                data = b''
            else:
                continue
            entry(relative_name, metadata, data)
    entry('TRAILER!!!', os.lstat(root), b'')
print('initramfs bytes:', os.path.getsize(output))
