#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Verify and extract only the NDK platform inputs and Android build tools."""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import zipfile

abi = os.environ.get('ANDROID_ABI', 'armeabi-v7a')
triples = {'armeabi-v7a': 'arm-linux-androideabi', 'arm64-v8a': 'aarch64-linux-android', 'x86_64': 'x86_64-linux-android'}
triple = triples[abi]
lock = json.loads(Path('/repo/scripts/fetch/locks/qt6-android-api21-inputs.json').read_text())
for record in lock['sources']:
    name = record['file']
    if name not in ('android-ndk-r27-linux.zip', 'build-tools_r36_linux.zip', 'android-35.jar'):
        continue
    archive = Path('/inputs') / name
    digest = hashlib.sha256()
    with archive.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    digest = digest.hexdigest()
    if digest != record['sha256']:
        raise ValueError(f'SHA256 mismatch: {name}')
    if name == 'android-35.jar':
        destination = Path('/work/android-sdk/platforms/android-35/android.jar')
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(archive, destination)
        continue
    with zipfile.ZipFile(archive) as package:
        for member in package.infolist():
            path = PurePosixPath(member.filename)
            if path.is_absolute() or '..' in path.parts:
                raise ValueError('Invalid archive path')
            if member.is_dir():
                continue
            relative = '/'.join(path.parts[1:])
            if name == 'android-ndk-r27-linux.zip':
                if not (relative == 'source.properties' or relative.startswith(('meta/',
                        'sources/android/cpufeatures/', 'sources/android/native_app_glue/',
                        'toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include/',
                        f'toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/{triple}/'))):
                    continue
                destination = Path('/ndk') / relative
            else:
                destination = Path('/work/android-sdk/build-tools/36.0.0') / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            with package.open(member) as incoming, destination.open('wb') as outgoing:
                shutil.copyfileobj(incoming, outgoing)
            mode = (member.external_attr >> 16) & 0o777
            if mode:
                destination.chmod(mode)
print('Verified platform-only NDK r27, platform35 jar and Linux Build Tools36')
