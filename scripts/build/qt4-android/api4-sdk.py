# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Seal/verify the installed API4 static SDK; this is not guest qualification."""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys

SDK = '/opt/qt4-android-armeabi-llvm'
RUNTIME = '/opt/longreach-android-api4'
REPORT = 'longreach-reports/api4-sdk.json'
MODULES = ('Core', 'Declarative', 'Gui', 'Network', 'Script', 'Sql', 'Svg', 'Xml')
PLUGINS = ('plugins/platforms/libqminimal.a', 'plugins/imageformats/libqsvg.a',
           'imports/Qt/labs/folderlistmodel/libqmlfolderlistmodelplugin.a',
           'imports/Qt/labs/gestures/libqmlgesturesplugin.a',
           'imports/Qt/labs/particles/libqmlparticlesplugin.a')
LIBRARIES = ('libc++.a', 'libc++abi.a', 'libc++experimental.a', 'libunwind.a',
             'libclang_rt.builtins-arm-android.a')
OBJECTS = ('crt-donut.o', 'armv5-compat.o', 'tmpfile-donut.o')
QT_ARCHIVE = 'e2882295097e47fe089f8ac741a95fef47e0a73a3f3cdf21b56990638f626ea0'


def load(name):
    spec = importlib.util.spec_from_file_location('api4_sdk_' + name, Path(__file__).with_name(name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# Verification also runs from the sealed installed tree: importing its helper
# closure must not create new payload files.
sys.dont_write_bytecode = True
provenance = load('sdk-provenance')


def digest(path):
    return provenance.digest(path)


def inventory(directory, exclude=()):
    if directory.is_symlink() or not directory.is_dir() or directory.resolve() != directory.absolute():
        raise ValueError('Expected a regular installed SDK directory: ' + str(directory))
    result = {}
    for path in sorted(directory.rglob('*')):
        if path.is_symlink() or getattr(path, 'is_junction', lambda: False)():
            raise ValueError('Installed SDK must not depend on linked build inputs: ' + str(path))
        if path.is_file() and path.relative_to(directory).as_posix() not in exclude:
            result[path.relative_to(directory).as_posix()] = digest(path)
    if not result:
        raise ValueError('Empty installed SDK directory: ' + str(directory))
    return result


def object_header(path, bits, machine, kind):
    with path.open('rb') as stream:
        data = stream.read(64)
    if (len(data) < (52 if bits == 32 else 64) or data[:7] != b'\x7fELF' + bytes((1 if bits == 32 else 2, 1, 1)) or
            struct.unpack_from('<H', data, 18)[0] != machine or struct.unpack_from('<H', data, 16)[0] not in kind):
        raise ValueError('Installed SDK object/tool ABI differs: ' + str(path))


def payload(prefix, runtime):
    sdk_files = inventory(prefix, (REPORT,))
    runtime_files = inventory(runtime)
    expected = {'lib/libQt' + name + '.a' for name in MODULES}
    actual = {name for name in sdk_files if name.startswith('lib/libQt') and name.endswith('.a')}
    if actual != expected:
        raise ValueError('API4 SDK must export all eight configured Qt modules')
    records = []
    for name in sorted(expected | set(PLUGINS)):
        if name not in sdk_files:
            raise ValueError('Missing installed API4 module/plugin: ' + name)
        records.append({'path': name, 'objects': provenance.archive_members(prefix / name, 32, 40)})
    for name in LIBRARIES:
        records.append({'path': 'runtime/lib/' + name,
                        'objects': provenance.archive_members(runtime / 'lib' / name, 32, 40)})
    for name in OBJECTS:
        object_header(runtime / 'lib' / name, 32, 40, (1,))
    for name in ('qmake', 'moc', 'rcc', 'uic'):
        object_header(prefix / 'bin' / name, 64, 62, (2, 3))
    for name in ('bin/cc', 'bin/cxx', 'target.sh', 'include/c++/v1/__config',
                 'sysroot/usr/include/stdlib.h', 'sysroot/usr/lib/libc.so',
                 'sysroot/usr/lib/crtbegin_dynamic.o', 'sysroot/usr/lib/crtbegin_static.o',
                 'sysroot/usr/lib/crtend_android.o'):
        if name not in runtime_files:
            raise ValueError('Missing installed API4 runtime/toolchain input: ' + name)
    for module in MODULES:
        if not any(name.startswith('include/Qt' + module + '/') for name in sdk_files):
            raise ValueError('Missing installed Qt headers: ' + module)
    if (prefix / 'bin/qt.conf').read_text() != '[Paths]\nPrefix=' + SDK + '\n':
        raise ValueError('API4 qmake qt.conf does not select the installed prefix')
    query = (prefix / 'longreach-reports/qmake-query.txt').read_text().splitlines()
    for required in ('QT_VERSION:4.8.7', 'QT_INSTALL_PREFIX:' + SDK,
                     'QT_INSTALL_HEADERS:' + SDK + '/include', 'QT_INSTALL_LIBS:' + SDK + '/lib'):
        if required not in query:
            raise ValueError('Installed qmake query does not match API4 SDK: ' + required)
    specs = provenance.mkspec_helper.verify(prefix, RUNTIME)
    return {'sdk_files': sdk_files, 'runtime_files': runtime_files,
            'static_archives': records, 'installed_mkspecs': specs}


def normalize_metadata(prefix, runtime):
    if runtime.as_posix() != RUNTIME:
        raise ValueError('Metadata relocation requires the declared installed runtime prefix')
    replacements = {'/work/qtquick-donut-sdk': SDK, '/work/sysroot-api4': RUNTIME + '/sysroot',
                    '/work/runtime-build': RUNTIME,
                    '/work/builtins-build/compiler-rt/lib/linux': RUNTIME + '/lib'}
    for path in prefix.rglob('*'):
        if (not path.is_file() or path.relative_to(prefix).parts[0] == 'mkspecs' or
                path.suffix not in ('.prl', '.pc', '.pri')):
            continue
        text = path.read_text(encoding='utf-8')
        for old, new in replacements.items():
            text = text.replace(old, new)
        if text != path.read_text(encoding='utf-8'):
            path.write_text(text, encoding='utf-8')
        for line in text.splitlines():
            if line.startswith('QMAKE_PRL_LIBS') and '/work/' in line:
                raise ValueError('Installed library still uses a build-tree link input: ' + str(path))


def verify(prefix, runtime):
    record = json.loads((prefix / REPORT).read_text(encoding='utf-8'))
    expected = {'schema_version': 1, 'qt': '4.8.7', 'llvm': '21.1.8', 'api': 4,
                'abi': 'armeabi', 'runtime_linkage': 'static', 'sdk_prefix': SDK, 'runtime_prefix': RUNTIME,
                'qt_archive_sha256': QT_ARCHIVE, 'guest_qualification': False}
    if any(record.get(k) != v for k, v in expected.items()) or record.get('exporter_sha256') != digest(Path(__file__)):
        raise ValueError('Installed API4 SDK identity/exporter differs')
    inputs = record.get('recipe_inputs', {})
    if not inputs or any(not re.fullmatch(r'[0-9a-f]{64}', value) for value in inputs.values()):
        raise ValueError('Missing installed API4 SDK recipe identities')
    compiler = Path(record.get('compiler_path', ''))
    if not compiler.is_absolute() or not compiler.is_file() or digest(compiler) != record.get('compiler_sha256'):
        raise ValueError('Installed API4 SDK compiler identity differs')
    if record.get('payload') != payload(prefix, runtime):
        raise ValueError('Installed API4 SDK headers/tools/libraries/runtime bytes changed')
    return record


def seal(prefix, runtime, repo, source, archive, compiler=None):
    # Failures invalidate an earlier seal, never replace it with a partial success.
    (prefix / REPORT).unlink(missing_ok=True)
    if digest(archive) != QT_ARCHIVE:
        raise ValueError('Qt4 API4 archive differs from the pinned source')
    selected = compiler or shutil.which('clang-21')
    if not selected:
        raise ValueError('Missing API4 SDK host compiler')
    compiler = Path(selected).resolve(strict=True)
    object_header(compiler, 64, 62, (2, 3))
    prepared = provenance.source_helper.verify_prepared(repo, archive, source, 'quick', 4)
    files = [repo / 'scripts/build/qt4-android' / name for name in
             ('api4-sdk.py', 'install-api4-sdk.sh', 'api4-clang-wrapper.sh', 'build-native.sh',
              'build-qtcore.sh', 'target-config.sh', 'prepare-source.py', 'patch-qtcore.py',
              'export-mkspecs.py', 'armv5-compat.c', 'crt-donut.c', 'tmpfile-donut.c')]
    files.append(repo / 'docker/qt4/android/Dockerfile')
    files += sorted((repo / 'patches/android/donut').glob('*.patch'))
    record = {'schema_version': 1, 'qt': '4.8.7', 'llvm': '21.1.8', 'api': 4, 'abi': 'armeabi',
              'runtime_linkage': 'static', 'sdk_prefix': SDK, 'runtime_prefix': RUNTIME,
              'exporter_sha256': digest(Path(__file__)), 'qt_archive_sha256': digest(archive),
              'runtime_source_archives': {
                  'llvm-project-21.1.8.src.tar.xz': '4633a23617fa31a3ea51242586ea7fb1da7140e426bd62fc164261fe036aa142',
                  'aosp-ndk-r7-api4-arm.tar.gz': '7049f4b170edc3415d48ff4fb36fe9b110ee7122f65051a727edb75600ad0057'},
              'compiler_path': str(compiler), 'compiler_sha256': digest(compiler),
              'prepared_source_recipe': prepared['recipe'],
              'recipe_inputs': {p.relative_to(repo).as_posix(): digest(p) for p in files},
              'payload': payload(prefix, runtime), 'guest_qualification': False}
    target = prefix / REPORT
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(record, sort_keys=True, indent=2) + '\n', encoding='utf-8')
    return verify(prefix, runtime)


def source_inputs(repo, directory):
    # Use the established complete API4 input set and pin checks. This is a
    # source capture only: no native build, packaging tool or guest executes.
    donor = load('donut-artifacts')
    result = {'inputs': donor.inputs(repo, directory)}
    head = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=repo, capture_output=True, text=True)
    result['git_head'] = head.stdout.strip() if head.returncode == 0 else None
    return result


def check_source_binding(manifest, snapshot):
    if (manifest.get('api') != 4 or manifest.get('abi') != 'armeabi' or
            manifest.get('qt') != '4.8.7' or manifest.get('guest_qualification') is not False):
        raise ValueError('SDK producer source binding has the wrong identity or scope')
    sources = snapshot['inputs']['sources']
    recipe = manifest.get('recipe_inputs', {})
    if not recipe:
        raise ValueError('SDK producer has no recipe input identities')
    selected = dict(recipe)
    for name, sha in manifest['prepared_source_recipe'].get('files', {}).items():
        if name in selected and selected[name] != sha:
            raise ValueError('SDK prepared-source and producer recipes disagree: ' + name)
        selected[name] = sha
    for name, sha in selected.items():
        if sources.get(name) != sha:
            raise ValueError('SDK producer differs from captured source: ' + name)
    archives = snapshot['inputs']['archives']
    if manifest['qt_archive_sha256'] != archives.get('downloads/qt-everywhere-opensource-src-4.8.7.tar.gz'):
        raise ValueError('SDK Qt source archive differs from capture')
    for name, sha in manifest['runtime_source_archives'].items():
        key = ('android-inputs/' if name == 'aosp-ndk-r7-api4-arm.tar.gz' else 'downloads/') + name
        if archives.get(key) != sha:
            raise ValueError('SDK runtime source archive differs from capture: ' + name)
    return True


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('action', choices=('seal', 'verify', 'capture-source', 'compare-source', 'normalize-metadata', 'check-source-binding'))
    p.add_argument('--prefix', type=Path, default=Path(SDK))
    p.add_argument('--runtime', type=Path, default=Path(RUNTIME))
    p.add_argument('--repo', type=Path, default=Path('/repo'))
    p.add_argument('--source', type=Path, default=Path('/work/qt4-donut-quick'))
    p.add_argument('--archive', type=Path, default=Path('/inputs/qt-everywhere-opensource-src-4.8.7.tar.gz'))
    p.add_argument('--input-directory', type=Path)
    p.add_argument('--snapshot', type=Path)
    p.add_argument('--manifest', type=Path)
    a = p.parse_args()
    if a.action == 'check-source-binding':
        if not a.manifest or not a.snapshot:
            p.error('source binding requires --manifest and --snapshot')
        check_source_binding(json.loads(a.manifest.read_text(encoding='utf-8-sig')),
                             json.loads(a.snapshot.read_text(encoding='utf-8-sig')))
        print('API4 SDK producer/source binding: PASS')
        return
    if a.action == 'normalize-metadata':
        normalize_metadata(a.prefix, a.runtime)
        return
    if a.action in ('capture-source', 'compare-source'):
        if not a.input_directory or not a.snapshot:
            p.error('source capture/comparison requires --input-directory and --snapshot')
        current = source_inputs(a.repo, a.input_directory)
        if a.action == 'capture-source':
            if a.snapshot.exists():
                raise ValueError('Preserve the previous SDK source snapshot before retrying')
            a.snapshot.write_text(json.dumps(current, sort_keys=True, indent=2) + '\n', encoding='utf-8')
        elif current != json.loads(a.snapshot.read_text(encoding='utf-8')):
            raise ValueError('API4 SDK source/archive inputs changed during the build')
        print('API4 SDK source ' + a.action + ': PASS')
        return
    if a.action == 'seal':
        seal(a.prefix, a.runtime, a.repo, a.source, a.archive)
    else:
        verify(a.prefix, a.runtime)
    print('Installed Qt4 API4 SDK ' + a.action + ': PASS (not guest qualification)')


if __name__ == '__main__':
    main()
