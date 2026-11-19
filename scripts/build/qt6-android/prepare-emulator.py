#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Prepare verified API21 target media and the legacy Windows emulator."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--abi', choices=('armeabi-v7a', 'arm64-v8a'), default='armeabi-v7a')
parser.add_argument('--repo', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
lock = json.loads((args.repo / 'scripts/fetch/locks/qt6-android-api21-inputs.json').read_text())
root = args.output / 'media'
root.mkdir(parents=True, exist_ok=True)
kernel = 'kernel-qemu'
emulator = 'emulator.exe' if args.abi == 'arm64-v8a' else 'emulator-arm.exe'
tools = 'tools_r25.2.5-windows.zip' if args.abi == 'arm64-v8a' else 'tools_r24.4.1-windows.zip'
for name in (f'{args.abi}-21_r04.zip', tools):
    record = next(item for item in lock['sources'] if item['file'] == name)
    archive = args.repo / 'downloads/android-lollipop' / name
    with archive.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    if digest != record['sha256']:
        raise ValueError(f'SHA256 mismatch: {name}')
    extract = root / 'emulator-25.2.5' if name == 'tools_r25.2.5-windows.zip' else root
    marker = extract / (name + '.sha256')
    required = ([args.abi + '/' + filename for filename in
                 (kernel, 'ramdisk.img', 'system.img', 'userdata.img', 'build.prop')]
                if name.startswith(args.abi) else [f'tools/{emulator}', 'tools/lib'])
    if (marker.is_file() and marker.read_text().strip() == digest
            and all((extract / relative).exists() for relative in required)):
        continue
    with zipfile.ZipFile(archive) as package:
        for member in package.infolist():
            path = Path(member.filename)
            if path.is_absolute() or '..' in path.parts:
                raise ValueError('Invalid media path')
            destination = extract / path
            if member.is_dir():
                destination.mkdir(parents=True, exist_ok=True)
            else:
                destination.parent.mkdir(parents=True, exist_ok=True)
                with package.open(member) as incoming, destination.open('wb') as outgoing:
                    shutil.copyfileobj(incoming, outgoing)
    marker.write_text(digest + '\n')
# SDK Tools24 looks here to recognize the system version instead of guessing10000.
properties = root / args.abi / 'system/build.prop'
properties.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(root / args.abi / 'build.prop', properties)
print(f'Prepared Android5.0.2/API21 {args.abi} emulator media')
