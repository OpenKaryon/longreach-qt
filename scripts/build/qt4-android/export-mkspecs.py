# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Export installed Qt4 specs independently of retained build-tree wrappers."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import uuid

SPEC = 'android-longreach-clang'
RECEIPT = '.longreach-export.json'
OMIT = {'default', 'default-host', 'linux-donut-host', 'linux-donut-llvm', SPEC, RECEIPT}
RUNTIMES = {'/opt/longreach-android', '/opt/longreach-android-api21'}
CONFIG = '''include(../linux-g++/qmake.conf)
# Preserve named-spec scopes when qmake selects the regular default directory.
CONFIG += android-longreach-clang
QMAKE_CC = @RUNTIME@/bin/cc -fgnu89-inline
QMAKE_CXX = @RUNTIME@/bin/cxx -DQT_NO_SHAREDMEMORY -DQT_NO_SYSTEMSEMAPHORE
QMAKE_LINK = $$QMAKE_CXX
QMAKE_LINK_SHLIB = $$QMAKE_CXX
QMAKE_AR = llvm-ar-21 cqs
QMAKE_RANLIB = llvm-ranlib-21
QMAKE_LIBS_THREAD =
QMAKE_CFLAGS_THREAD =
QMAKE_CXXFLAGS_THREAD =
DEFINES += QT_NO_LINUX_FUTEX
'''


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def directory(path):
    path = Path(path).absolute()
    if path.resolve() != path or not path.is_dir():
        raise ValueError('Expected an unlinked directory: ' + str(path))
    return path


def inventory(root):
    result = {}
    for path in sorted(root.rglob('*')):
        if path.is_symlink() or getattr(path, 'is_junction', lambda: False)():
            raise ValueError('Linked installed mkspec: ' + str(path))
        if path.is_file() and path.relative_to(root).as_posix() != RECEIPT:
            result[path.relative_to(root).as_posix()] = digest(path)
        elif not path.is_file() and not path.is_dir():
            raise ValueError('Unsupported mkspec file: ' + str(path))
    return result


def verify_tree(root, runtime):
    if runtime not in RUNTIMES:
        raise ValueError('Unsupported installed runtime prefix')
    root = directory(root)
    record = json.loads((root / RECEIPT).read_text(encoding='utf-8'))
    if (record.get('schema_version') != 1 or record.get('runtime') != runtime or
            record.get('default_spec') != SPEC or record.get('exporter_sha256') != digest(Path(__file__))):
        raise ValueError('Installed mkspec receipt belongs to another exporter/runtime')
    files = inventory(root)
    if files != record.get('files'):
        raise ValueError('Installed mkspec bytes or file set changed')
    if any((root / name).exists() or (root / name).is_symlink() for name in OMIT - {'default', SPEC, RECEIPT}):
        raise ValueError('Build-only mkspec leaked into installed SDK')
    if (root / SPEC / 'qmake.conf').read_bytes() != CONFIG.replace('@RUNTIME@', runtime).encode():
        raise ValueError('Installed target spec does not use the selected runtime')
    for name in ('qmake.conf', 'qplatformdefs.h'):
        if (root / 'default' / name).read_bytes() != (root / SPEC / name).read_bytes():
            raise ValueError('Default mkspec differs from the installed target spec')
    for name in ('linux-g++/qmake.conf', 'qconfig.pri', 'features/qt_config.prf'):
        if not (root / name).is_file():
            raise ValueError('Incomplete installed mkspec support: ' + name)
    for name in ('common', 'features'):
        if not (root / name).is_dir():
            raise ValueError('Incomplete installed mkspec support: ' + name)
    return record


def verify(prefix, runtime):
    return verify_tree(directory(prefix) / 'mkspecs', runtime)


def remove_owned(directory_path, prefix, marker):
    # Only disposable swap/staging directories created by this invocation.
    if (directory_path.resolve().parent != prefix or directory_path.is_symlink() or
            not directory_path.name.startswith(marker)):
        raise ValueError('Unexpected installed-spec cleanup path')
    shutil.rmtree(directory_path)


def export(source, prefix, runtime):
    source = directory(directory(source) / 'mkspecs')
    prefix = directory(prefix)
    if source.is_relative_to(prefix) or prefix.is_relative_to(source):
        raise ValueError('Source and installed mkspec trees must be separate')
    if runtime not in RUNTIMES:
        raise ValueError('Unsupported installed runtime prefix')
    destination = prefix / 'mkspecs'
    if destination.is_symlink() or getattr(destination, 'is_junction', lambda: False)():
        raise ValueError('Linked installed mkspec destination')
    if destination.exists() and not destination.is_dir():
        raise ValueError('Installed mkspec destination is not a directory')
    stage = prefix / ('.longreach-mkspec-stage-' + uuid.uuid4().hex)
    stage.mkdir()
    try:
        for child in sorted(source.iterdir()):
            if child.name in OMIT:
                continue
            if child.is_symlink() or getattr(child, 'is_junction', lambda: False)():
                raise ValueError('Linked source mkspec: ' + str(child))
            if child.is_dir():
                inventory(child)  # Never dereference build-tree links while copying.
                shutil.copytree(child, stage / child.name)
            elif child.is_file():
                shutil.copyfile(child, stage / child.name)
            else:
                raise ValueError('Unsupported source mkspec: ' + str(child))
        header = directory(source / 'linux-donut-llvm') / 'qplatformdefs.h'
        if header.is_symlink() or header.parent.is_symlink() or not header.is_file():
            raise ValueError('Missing regular target qplatformdefs.h')
        spec = stage / SPEC
        spec.mkdir()
        (spec / 'qmake.conf').write_bytes(CONFIG.replace('@RUNTIME@', runtime).encode())
        shutil.copyfile(header, spec / 'qplatformdefs.h')
        # A regular directory alias works without symlink support after SDK export.
        # Both directories have the same parent, so ../common includes stay valid.
        shutil.copytree(spec, stage / 'default')
        record = {'schema_version': 1, 'runtime': runtime, 'default_spec': SPEC,
                  'exporter_sha256': digest(Path(__file__)), 'files': inventory(stage)}
        (stage / RECEIPT).write_text(json.dumps(record, sort_keys=True, indent=2) + '\n', encoding='utf-8')
        verify_tree(stage, runtime)
        if destination.is_dir():
            try:
                if verify(prefix, runtime) == record:
                    return record  # Keep installed timestamps and client cache inputs.
            except (ValueError, OSError, KeyError):
                pass
        previous = prefix / ('.longreach-mkspec-swap-' + uuid.uuid4().hex)
        if destination.exists():
            destination.rename(previous)
        try:
            stage.rename(destination)
            verify(prefix, runtime)
        except BaseException:
            if destination.exists():
                destination.rename(stage)
            if previous.exists():
                previous.rename(destination)
            raise
        if previous.exists():
            remove_owned(previous, prefix, '.longreach-mkspec-swap-')
        return record
    finally:
        if stage.exists():
            remove_owned(stage, prefix, '.longreach-mkspec-stage-')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('export', 'verify'))
    parser.add_argument('--source', type=Path)
    parser.add_argument('--prefix', required=True, type=Path)
    parser.add_argument('--runtime', required=True, choices=sorted(RUNTIMES))
    args = parser.parse_args(argv)
    if args.command == 'export':
        if not args.source:
            parser.error('export requires --source')
        export(args.source, args.prefix, args.runtime)
    else:
        verify(args.prefix, args.runtime)
    print('Installed Qt4 mkspecs verified: ' + args.runtime)


if __name__ == '__main__':
    main()
