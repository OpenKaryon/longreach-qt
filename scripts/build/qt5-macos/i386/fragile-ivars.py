#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Give the i386 compile SDK the instance layouts of the 32-bit system classes.

    fragile-ivars.py <link SDK (10.7)> <compile SDK (a copy of 11.3, edited in place)> <work dir>

The 32-bit Objective-C runtime is the fragile one: a subclass's instance
variables sit at offsets the compiler fixes from the superclass's declared
instance variables. The 11.3 SDK no longer declares any - NSView, NSWindow
and the rest have no ivar block - so a Qt subclass such as QNSView would place
its own variables over AppKit's and corrupt them. The 10.7 SDK still declares
them, and Apple froze those 32-bit layouts for binary compatibility.

So, for every class the 10.7 SDK headers declare with instance variables,
this measures sizeof(struct { @defs(Class) }) against the 10.7 SDK, and gives
the class's @interface in the compile SDK a private char array of the size
its own variables take there. Nothing reads those arrays; they only make every
subclass start where it starts on a real 32-bit Mac.
"""
import re
import subprocess
import sys
from pathlib import Path

link_sdk, compile_sdk, work = (Path(a) for a in sys.argv[1:4])
work.mkdir(parents=True, exist_ok=True)
TARGET = ['-target', 'i386-apple-macosx10.6']
NM = '/usr/local/osxcross/bin/i386-apple-darwin10-nm'

IFACE = re.compile(r'@interface\s+(\w+)\s*(?:<[^>{};]*>)?\s*:\s*(\w+)[^{;@]*?(\{)', re.S)


def framework_dirs(sdk):
    top = sdk / 'System/Library/Frameworks'
    for fw in sorted(top.glob('*.framework')):
        yield fw
        for sub in sorted((fw / 'Frameworks').glob('*.framework')) if (fw / 'Frameworks').is_dir() else []:
            yield sub


# 1. Classes with an ivar block in the 10.7 SDK. The probe imports the umbrella
# headers of the frameworks Qt subclasses from; a class declared elsewhere is
# not measured, and not needed.
UMBRELLAS = ['Foundation', 'AppKit', 'QuartzCore', 'CoreData', 'IOBluetooth', 'IOBluetoothUI',
             'CoreLocation', 'AVFoundation', 'QTKit', 'CoreWLAN', 'ImageCaptureCore', 'StoreKit', 'GSS']
classes = {}
for fw in framework_dirs(link_sdk):
    headers = fw / 'Headers'
    if not headers.is_dir():
        continue
    for h in sorted(headers.glob('*.h')):
        text = h.read_text(errors='replace')
        for m in IFACE.finditer(text):
            # The match must not have run past the end of the interface line
            # into a later declaration.
            if '\n@' in text[m.start(1):m.start(3)] or ';' in text[m.start(1):m.start(3)]:
                continue
            classes.setdefault(m.group(1), m.group(2))
imports = []
for u in UMBRELLAS:
    hdr = f'{u}/{u}.h'
    test = work / 'import.m'
    test.write_text(f'#import <{hdr}>\n')
    if subprocess.run(['clang', *TARGET, '-isysroot', str(link_sdk), '-x', 'objective-c', '-w',
                       '-fsyntax-only', str(test)], capture_output=True).returncode == 0:
        imports.append(hdr)

# 2. Measure them against the 10.7 SDK, dropping what the umbrellas do not declare.
names = sorted(set(classes) | set(classes.values()))
probe = work / 'probe.m'
obj = work / 'probe.o'
while True:
    lines = [f'#import <{i}>' for i in imports]
    for n in names:
        lines.append(f'struct qt_defs_{n} {{ @defs({n}) }};')
        lines.append(f'char qt_size_{n}[sizeof(struct qt_defs_{n})];')
    probe.write_text('\n'.join(lines) + '\n')
    r = subprocess.run(['clang', *TARGET, '-isysroot', str(link_sdk), '-x', 'objective-c', '-w',
                        '-fcommon', '-c', str(probe), '-o', str(obj),
                        '-ferror-limit=0'], capture_output=True, text=True)
    if r.returncode == 0:
        break
    bad = set(re.findall(r"qt_defs_(\w+)", ' '.join(l for l in r.stderr.splitlines() if 'error' in l)))
    bad |= set(re.findall(r"cannot find interface declaration for '(\w+)'", r.stderr))
    bad |= set(re.findall(r"error: [^\n]*'(\w+)'", r.stderr)) & set(names)
    if not bad:
        sys.exit('probe failed:\n' + r.stderr[-4000:])
    names = [n for n in names if n not in bad]

sizes = {}
for line in subprocess.run([NM, str(obj)], capture_output=True, text=True, check=True).stdout.splitlines():
    m = re.match(r'([0-9a-f]+) [Cc] _qt_size_(\w+)$', line.strip())
    if m:
        sizes[m.group(2)] = int(m.group(1), 16)
if not sizes:
    sys.exit('no sizes read from the probe object')

# 3. Pad each class's @interface in the compile SDK by its own ivars' size.
own = {}
for n, sup in classes.items():
    if n in sizes and sup in sizes and sizes[n] > sizes[sup]:
        own[n] = sizes[n] - sizes[sup]

patched = {}
for fw in framework_dirs(compile_sdk):
    headers = fw / 'Headers'
    if not headers.is_dir():
        continue
    for h in sorted(headers.glob('*.h')):
        text = h.read_text(errors='replace')
        out = []
        pos = 0
        for m in re.finditer(r'@interface\s+(\w+)\s*(?:<[^>{};]*>)?\s*:\s*\w+(?:\s*<[^>{};@]*>)?', text):
            n = m.group(1)
            if n not in own or n in patched:
                continue
            if re.match(r'(?:\s*#[^\n]*\n)*\s*\{', text[m.end():]):
                continue  # still declares its variables (NSObject, Foundation's !__OBJC2__ blocks, CALayer)
            out.append(text[pos:m.end()])
            out.append(f'\n{{\n@private\n    char _qt_i386_ivars_{n}[{own[n]}] __attribute__((aligned(4)));\n}}')
            pos = m.end()
            patched[n] = h
        if out:
            out.append(text[pos:])
            h.write_text(''.join(out))

missing = sorted(set(own) - set(patched))
print(f'{len(classes)} classes with ivars in the 10.7 SDK, {len(sizes)} measured, '
      f'{len(own)} with their own variables, {len(patched)} padded in the compile SDK')
for n in ('NSObject', 'NSResponder', 'NSView', 'NSWindow', 'NSPanel', 'NSApplication', 'NSMenu', 'NSMenuItem'):
    if n in sizes:
        print(f'  {n}: {sizes[n]} bytes')
if missing:
    print('not declared in the compile SDK (unused there):', ' '.join(missing[:40]), '...' if len(missing) > 40 else '')
