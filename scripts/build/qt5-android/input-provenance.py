#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Record the actual shared LLVM runtime inputs for the legacy API10 profile."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess

repo = Path(os.environ.get('REPO_ROOT', '/repo'))
prefix = Path('/opt/longreach-android')
abi = os.environ.get('ANDROID_ABI', 'armeabi-v7a')
settings = {
    'armeabi-v7a': ('armv7a-linux-androideabi10', 'arm', 40),
    'x86': ('i686-linux-android10', 'x86', 3),
}
if abi not in settings:
    raise ValueError('The legacy runtime provenance requires ARMv7 or x86')
target, arch, machine = settings[abi]


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


runtime = prefix / 'lib/libc++_shared.so'
header = runtime.read_bytes()[:20]
if header[:6] != b'\x7fELF\x01\x01' or struct.unpack_from('<H', header, 18)[0] != machine:
    raise ValueError('Installed legacy runtime has the wrong target ABI')
lock = json.loads((repo / 'scripts/fetch/locks/qt5-android-api10-inputs.json').read_text())
name = f'aosp-ndk-r7-api9-{arch}.tar.gz'
selected = next(item for item in lock['sources'] if item['file'] == name)
archive = repo / 'downloads/android-gingerbread' / name
if digest(archive) != selected['sha256']:
    raise ValueError('Legacy sysroot archive differs from its lock')
llvm = next(item for item in lock['shared_sources'] if item['file'].startswith('llvm-project-'))
if digest(repo / 'downloads' / llvm['file']) != llvm['sha256']:
    raise ValueError('LLVM archive differs from its lock')
helpers = [repo / 'scripts/build/qt5-android' / name for name in (
    'target-config.sh', 'build-runtime.sh', 'install-toolchain.sh',
    'clang-wrapper.sh', 'compat.c', 'input-provenance.py')]
helpers += [repo / 'scripts/build/qt4-android' / name for name in ('crt-donut.c', 'tmpfile-donut.c')]
patches = sorted((repo / 'patches/android/gingerbread').glob('*.patch'))
headers = {str(path.relative_to(prefix / 'sysroot')): digest(path)
           for path in sorted((prefix / 'sysroot/usr/include').rglob('*')) if path.is_file()}
compiler = Path(shutil.which('clang-21')).resolve()
manifest = {
    'api': 10, 'abi': abi, 'target': target, 'elf_bits': 32, 'elf_machine': machine,
    'llvm_source': llvm, 'sysroot_source': selected,
    'compiler_version': subprocess.check_output([str(compiler), '--version'], text=True).strip(),
    'compiler_executable_sha256': digest(compiler),
    'libcxx_shared_sha256': digest(runtime),
    'effective_headers': headers,
    'recipe_inputs': {str(path.relative_to(repo)): digest(path) for path in helpers + patches},
    'locale_profile': 'classic C/POSIX; wide characters disabled',
    'unwind_frame_header_cache': False,
}
if abi == 'x86':
    source = Path('/work/android-llvm/llvm-project-21.1.8.src/compiler-rt/lib/builtins/atomic.c')
    manifest['generic_atomic_provider'] = {
        'implementation': 'upstream compiler-rt 21.1.8 atomic.c',
        'source_sha256': digest(source), 'shared_library': 'libc++_shared.so',
        'lock_backend': 'pthread',
    }
(prefix / 'runtime-input-provenance.json').write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
print(f'Recorded API10 {abi} runtime provenance and {len(headers)} effective headers')
