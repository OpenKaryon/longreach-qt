#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Check a Jaguar executable's imports against the 10.2.8 SDK, per library.

With the two-level namespace each import names the library that must export
it, e.g. "(from libSystem)". A strong import whose library, including the
sub-libraries an umbrella re-exports, lacks the symbol on 10.2 stops dyld
before main. Weak imports are listed but allowed: the code must check them
for NULL. Every dependent library must also exist in the 10.2.8 SDK.

usage: check-imports.py <executable> <report>
"""
import os
import re
import subprocess
import sys

SDK = '/opt/jaguar/MacOSX10.2.8.sdk'
NM = '/opt/osxcross-ppc/target/bin/powerpc-apple-darwin8-nm'
OTOOL = '/opt/osxcross-ppc/target/bin/powerpc-apple-darwin8-otool'
MACHO = {b'\xfe\xed\xfa\xce', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbe'}


def is_macho(path):
    try:
        with open(path, 'rb') as f:
            return f.read(4) in MACHO
    except OSError:
        return False


def exports(paths):
    out = set()
    for path in paths:
        text = subprocess.run([NM, '-arch', 'all', '-g', path], capture_output=True, text=True).stdout
        for line in text.splitlines():
            parts = line.split()
            if len(parts) >= 3 and parts[-2] not in ('U', 'u'):
                out.add(parts[-1])
    return out


def library_files(install_name):
    """The SDK binary for an install name, plus what it re-exports."""
    main = SDK + install_name
    if not os.path.exists(main):
        return None
    files = [main]
    if install_name.startswith('/usr/lib/libSystem'):
        system = SDK + '/usr/lib/system'
        files += [os.path.join(system, f) for f in os.listdir(system)
                  if is_macho(os.path.join(system, f)) and '_debug' not in f and '_profile' not in f]
    framework = re.match(r'(.*\.framework)/', install_name)
    if framework:
        root = SDK + framework.group(1)
        for dirpath, _, names in os.walk(os.path.join(root, 'Versions')):
            if '/Frameworks/' not in dirpath + '/':
                continue
            for name in names:
                full = os.path.join(dirpath, name)
                if is_macho(full) and '_debug' not in name and '_profile' not in name and not os.path.islink(full):
                    files.append(full)
    return files


def main():
    exe, report_path = sys.argv[1], sys.argv[2]
    libs = [l.split(' (compatibility')[0].strip()
            for l in subprocess.run([OTOOL, '-L', exe], capture_output=True, text=True).stdout.splitlines()[1:]]
    short = {}
    problems = []
    tables = {}
    for lib in libs:
        files = library_files(lib)
        if files is None:
            problems.append(f'MISSING-LIBRARY {lib}')
            continue
        tables[lib] = exports(files)
        # nm names the library by its leaf, possibly shortened: libz.1 for
        # libz.1.1.3.dylib, CoreFoundation for the framework binary.
        pieces = os.path.basename(lib).split('.')
        for n in range(1, len(pieces) + 1):
            short['.'.join(pieces[:n])] = lib
    imports = subprocess.run([NM, '-m', exe], capture_output=True, text=True).stdout
    weak = []
    count = 0
    for line in imports.splitlines():
        m = re.match(r'\s*\(undefined(?: \[lazy bound\])?\) (weak )?external (\S+) \(from (\S+)\)', line)
        if not m:
            continue
        count += 1
        is_weak, symbol, origin = bool(m.group(1)), m.group(2), m.group(3)
        lib = short.get(origin)
        if lib is None or lib not in tables:
            problems.append(f'UNKNOWN-ORIGIN {symbol} from {origin}')
        elif symbol not in tables[lib]:
            (weak if is_weak else problems).append(
                f'{"weak   " if is_weak else "MISSING"} {symbol} from {origin}')
    with open(report_path, 'w') as report:
        for line in problems + weak:
            report.write(line + '\n')
        summary = (f'imports {count}, libraries {len(libs)}, weak-only on 10.2: {len(weak)}, '
                   f'problems: {len(problems)}')
        report.write(summary + '\n')
    print(summary)
    for line in problems:
        print(line)
    sys.exit(1 if problems else 0)


if __name__ == '__main__':
    main()
