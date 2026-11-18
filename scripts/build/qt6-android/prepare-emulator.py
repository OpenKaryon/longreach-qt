#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Prepare verified API21 ARMv7 media and the legacy Windows emulator."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repo', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
lock = json.loads((args.repo / 'scripts/fetch/locks/qt6-android-api21-inputs.json').read_text())
root = args.output / 'media'
root.mkdir(parents=True, exist_ok=True)
for name in ('armeabi-v7a-21_r04.zip', 'tools_r24.4.1-windows.zip'):
    record = next(item for item in lock['sources'] if item['file'] == name)
    archive = args.repo / 'downloads/android-lollipop' / name
    with archive.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    if digest != record['sha256']:
        raise ValueError(f'SHA256 mismatch: {name}')
    marker = root / (name + '.sha256')
    required = (['armeabi-v7a/' + filename for filename in
                 ('kernel-qemu', 'ramdisk.img', 'system.img', 'userdata.img', 'build.prop')]
                if name.startswith('armeabi') else ['tools/emulator-arm.exe', 'tools/lib'])
    if (marker.is_file() and marker.read_text().strip() == digest
            and all((root / relative).exists() for relative in required)):
        continue
    with zipfile.ZipFile(archive) as package:
        for member in package.infolist():
            path = Path(member.filename)
            if path.is_absolute() or '..' in path.parts:
                raise ValueError('Invalid media path')
            destination = root / path
            if member.is_dir():
                destination.mkdir(parents=True, exist_ok=True)
            else:
                destination.parent.mkdir(parents=True, exist_ok=True)
                with package.open(member) as incoming, destination.open('wb') as outgoing:
                    shutil.copyfileobj(incoming, outgoing)
    marker.write_text(digest + '\n')
# SDK Tools24 looks here to recognize the system version instead of guessing10000.
properties = root / 'armeabi-v7a/system/build.prop'
properties.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(root / 'armeabi-v7a/build.prop', properties)
print('Prepared Android5.0.2/API21 ARMv7 emulator media')
