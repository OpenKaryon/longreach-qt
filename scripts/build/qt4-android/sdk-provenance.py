# SPDX-License-Identifier: GPL-3.0-or-later
"""Record the installed static SDK's actual ABI, modules and source inputs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import shutil

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--prefix', type=Path, required=True)
parser.add_argument('--source', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
abi = os.environ['ANDROID_ABI']
settings = {'x86': (10, 32, 3, '/opt/longreach-android'),
            'x86_64': (21, 64, 62, '/opt/longreach-android-api21'),
            'arm64-v8a': (21, 64, 183, '/opt/longreach-android-api21')}
api, bits, machine, runtime = settings[abi]
repo = Path('/repo')

def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()

def archive_members(path):
    blob = path.read_bytes()
    if not blob.startswith(b'!<arch>\n'):
        raise RuntimeError(f'Not a regular static archive: {path}')
    offset, members = 8, 0
    while offset < len(blob):
        header = blob[offset:offset + 60]
        if len(header) != 60 or header[58:60] != b'`\n':
            raise RuntimeError(f'Invalid archive header: {path}')
        size = int(header[48:58])
        data = blob[offset + 60:offset + 60 + size]
        if len(data) != size:
            raise RuntimeError(f'Truncated archive member: {path}')
        name = header[:16].decode('ascii').strip()
        if name.startswith('#1/'):
            data = data[int(name[3:]):]
        if data.startswith(b'\x7fELF'):
            if data[4:6] != bytes((1 if bits == 32 else 2, 1)) or struct.unpack_from('<H', data, 18)[0] != machine:
                raise RuntimeError(f'Wrong ABI object in {path}: {name}')
            members += 1
        elif name not in ('/', '//', '/SYM64/'):
            raise RuntimeError(f'Non-ELF code member in {path}: {name}')
        offset += 60 + size + (size % 2)
    if offset != len(blob) or not members:
        raise RuntimeError(f'Empty or invalid archive: {path}')
    return members

modules = sorted(path.name for path in (args.prefix / 'lib').glob('libQt*.a'))
if len(modules) != 14:
    raise RuntimeError(f'Expected fourteen selected Qt4 modules, got {modules}')
archives = sorted(args.prefix.glob('lib/libQt*.a')) + sorted(args.prefix.glob('plugins/**/*.a')) + sorted(args.prefix.glob('imports/**/*.a'))
records = [{'archive': str(path.relative_to(args.prefix)), 'objects': archive_members(path),
            'elf_class': bits, 'machine': machine, 'sha256': digest(path)} for path in archives]
patches = [repo / 'patches/qt4/all/03-static-gui-animation-registration.patch',
           repo / 'patches/qt4/all/04-script-tagged-frame-pointers.patch',
           repo / 'patches/qt4/linux-sarge-llvm/01-xmlpatterns-color-mask.patch']
patches += sorted((repo / 'patches/qt4/android').glob('*.patch'))
helpers = [repo / 'scripts/build/qt4-android' / name for name in
           ('target-config.sh', 'build-qtcore.sh', 'patch-qtcore.py', 'build-api21-sdk.sh', 'sdk-provenance.py', 'cache-inputs.py')]
inputs = {str(path.relative_to(repo)): digest(path) for path in patches + helpers}
source_names = {'src/corelib/thread/qthread_unix.cpp', 'src/corelib/io/qfilesystemengine_unix.cpp',
                'src/corelib/codecs/qtextcodec.cpp', 'src/gui/kernel/qwidget.cpp',
                'src/plugins/platforms/minimal/minimal.pro', 'src/plugins/platforms/minimal/qminimalintegration.h'}
for patch in patches:
    for line in patch.read_text().splitlines():
        if line.startswith('+++ b/'):
            source_names.add(line[6:].split('\t')[0])
actual_source = {name: digest(args.source / name) for name in sorted(source_names)}
configurations = [(args.source / name).read_text().strip() for name in
                  ('.longreach-configuration', '.longreach-object-configuration', '.longreach-plugin-configuration')]
if len(set(configurations)) != 1 or len(configurations[0]) != 64:
    raise RuntimeError('SDK module/plugin objects do not share their effective configuration')
args.output.mkdir(parents=True, exist_ok=True)
(args.output / 'sdk-modules.txt').write_text('\n'.join(modules) + '\n')
(args.output / 'sdk-static-elf.json').write_text(json.dumps({'abi': abi, 'archives': records}, indent=2) + '\n')
(args.output / 'sdk-provenance.json').write_text(json.dumps({
    'qt': '4.8.7', 'llvm': '21.1.8', 'abi': abi, 'api': api,
    'qt_archive_sha256': digest(Path('/inputs/qt-everywhere-opensource-src-4.8.7.tar.gz')),
    'runtime_sha256': digest(Path(runtime) / 'lib/libc++_shared.so'),
    'compiler_executable_sha256': digest(Path(shutil.which('clang-21')).resolve()),
    'configuration_fingerprint': configurations[0], 'recipe_inputs': inputs, 'patched_source': actual_source}, indent=2) + '\n')
print(f'Validated {len(modules)} Qt4 modules and {len(records)} target archives, all ELF{bits}/machine{machine}')
