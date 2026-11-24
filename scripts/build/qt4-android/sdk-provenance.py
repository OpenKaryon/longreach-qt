# SPDX-License-Identifier: GPL-3.0-or-later
"""Record the installed static SDK's actual ABI, modules and source inputs."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import os
import re
import shutil
import struct
import uuid

SETTINGS = {'x86': (10, 32, 3, '/opt/longreach-android'),
            'x86_64': (21, 64, 62, '/opt/longreach-android-api21'),
            'arm64-v8a': (21, 64, 183, '/opt/longreach-android-api21')}
HELPERS = ('target-config.sh', 'build-qtcore.sh', 'patch-qtcore.py', 'build-api21-sdk.sh',
           'sdk-provenance.py', 'cache-inputs.py', 'prepare-source.py', 'export-mkspecs.py')
REPORTS = ('sdk-modules.txt', 'sdk-static-elf.json', 'sdk-provenance.json')


def load_helper(name):
    spec = importlib.util.spec_from_file_location('qt4_provenance_' + name, Path(__file__).with_name(name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


source_helper = load_helper('prepare-source')
mkspec_helper = load_helper('export-mkspecs')


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def write(path, text):
    temporary = path.with_name(path.name + '.' + uuid.uuid4().hex + '.tmp')
    try:
        temporary.write_text(text, encoding='utf-8')
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def archive_members(path, bits, machine):
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


def produce(prefix, source, output, abi, *, repo=Path('/repo'),
            archive=Path('/inputs/qt-everywhere-opensource-src-4.8.7.tar.gz'),
            runtime=None, compiler=None):
    output.mkdir(parents=True, exist_ok=True)
    # A failed check must not leave an earlier success available for sealing.
    for name in REPORTS:
        (output / name).unlink(missing_ok=True)
    api, bits, machine, runtime_prefix = SETTINGS[abi]
    installed_mkspecs = mkspec_helper.verify(prefix, runtime_prefix)
    modules = sorted(path.name for path in (prefix / 'lib').glob('libQt*.a'))
    if len(modules) != 14:
        raise RuntimeError(f'Expected fourteen selected Qt4 modules, got {modules}')
    archives = sorted(prefix.glob('lib/libQt*.a')) + sorted(prefix.glob('plugins/**/*.a')) + sorted(prefix.glob('imports/**/*.a'))
    records = [{'archive': str(path.relative_to(prefix)), 'objects': archive_members(path, bits, machine),
                'elf_class': bits, 'machine': machine, 'sha256': digest(path)} for path in archives]
    patches = [repo / 'patches/qt4/all/03-static-gui-animation-registration.patch',
               repo / 'patches/qt4/all/04-script-tagged-frame-pointers.patch',
               repo / 'patches/qt4/linux-sarge-llvm/01-xmlpatterns-color-mask.patch']
    patches += sorted((repo / 'patches/qt4/android').glob('*.patch'))
    helpers = [repo / 'scripts/build/qt4-android' / name for name in HELPERS]
    inputs = {path.relative_to(repo).as_posix(): digest(path) for path in patches + helpers}
    prepared = source_helper.verify_prepared(repo, archive, source, 'quick', api)
    configurations = [(source / name).read_text().strip() for name in
                      ('.longreach-configuration', '.longreach-object-configuration', '.longreach-plugin-configuration')]
    if len(set(configurations)) != 1 or not re.fullmatch(r'[0-9a-f]{64}', configurations[0]):
        raise RuntimeError('SDK module/plugin objects do not share their effective configuration')
    compiler = compiler or shutil.which('clang-21')
    if not compiler:
        raise RuntimeError('Missing compiler executable for SDK provenance')
    record = {
        'qt': '4.8.7', 'llvm': '21.1.8', 'abi': abi, 'api': api,
        'qt_archive_sha256': digest(archive),
        'runtime_sha256': digest(Path(runtime or runtime_prefix) / 'lib/libc++_shared.so'),
        'compiler_executable_sha256': digest(Path(compiler).resolve()),
        'prepared_source_recipe': prepared['recipe'],
        'configuration_fingerprint': configurations[0], 'recipe_inputs': inputs,
        'patched_source': prepared['modified_source'], 'installed_mkspecs': installed_mkspecs}
    write(output / 'sdk-modules.txt', '\n'.join(modules) + '\n')
    write(output / 'sdk-static-elf.json', json.dumps({'abi': abi, 'archives': records}, indent=2) + '\n')
    write(output / 'sdk-provenance.json', json.dumps(record, indent=2) + '\n')
    print(f'Validated {len(modules)} Qt4 modules and {len(records)} target archives, all ELF{bits}/machine{machine}')
    return record


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prefix', type=Path, required=True)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(argv)
    produce(args.prefix, args.source, args.output, os.environ['ANDROID_ABI'])


if __name__ == '__main__':
    main()
