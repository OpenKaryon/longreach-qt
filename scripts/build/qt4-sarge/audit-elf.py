# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon

"""Assert the ELF class and machine, and resolve every dependency through Sarge's loader."""
from __future__ import print_function
import glob
import hashlib
import json
import os
import re
import subprocess

root = '/work/sysroot'
arch = os.environ.get('SARGE_ARCH', 'i386')
elf_class, machine, loader = {'i386': ('ELF32', 'Intel 80386', '/lib/ld-linux.so.2'),
                              'amd64': ('ELF64', 'Advanced Micro Devices X86-64', '/lib/ld-linux-x86-64.so.2')}[arch]
records = []
for path in sorted(glob.glob('/out/bin/*')):
    header = subprocess.check_output(['readelf', '-h', path]).decode('utf-8')
    versions = subprocess.check_output(['readelf', '-V', path]).decode('utf-8')
    dynamic = subprocess.check_output(['readelf', '-d', path]).decode('utf-8')
    required = sorted(set(re.findall(r'Name: (GLIBC_[0-9.]+)', versions)),
                      key=lambda v: tuple(int(n) for n in v[6:].split('.')))
    assert elf_class in header and machine in header and 'UNIX - System V' in header, path
    assert required and tuple(int(n) for n in required[-1][6:].split('.')) <= (2, 3, 2), path
    dependencies = re.findall(r'\(NEEDED\).*\[([^]]+)\]', dynamic)
    assert not any(n.startswith(('libQt', 'libstdc++', 'libgcc_s')) for n in dependencies), path
    assert not re.search(r'\((?:RPATH|RUNPATH)\)', dynamic), path
    resolved = subprocess.check_output([root + loader, '--library-path',
        root + '/lib/tls:' + root + '/lib:' + root + '/usr/lib:' + root + '/usr/X11R6/lib',
        '--list', path]).decode('utf-8')
    for target in re.findall(r'=>\s+(\S+)\s+\(', resolved):
        assert target.startswith(root + '/'), (path, target)
    with open(path, 'rb') as stream:
        digest = hashlib.sha256(stream.read()).hexdigest()
    records.append({'binary': os.path.basename(path), 'sha256': digest,
                    'glibc_versions': required, 'needed': dependencies,
                    'sarge_loader_resolution': resolved.strip().splitlines()})
expected = [line.strip() for line in open('/work/suite/expected-apps.txt') if line.strip() and not line.startswith('#')]
assert sorted(r['binary'] for r in records) == sorted(expected), 'Expected tests/expected-apps.txt'
with open('/out/elf-audit.json', 'w') as output:
    json.dump({'binaries': records, 'max_glibc': '2.3.2'}, output, indent=2)
print('ELF audit passed: %d %s binaries, max GLIBC_2.3.2, Sarge dependencies only' % (len(records), arch))
