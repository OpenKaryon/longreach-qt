# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Refresh recipe-owned Qt4 sources without replacing retained build outputs."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tarfile
import tempfile

STATE = '.longreach-prepared-source.json'


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def selected_patches(repo, profile, api):
    if profile != 'quick':
        return []
    result = [repo / 'patches/qt4/all' / name for name in (
        '03-static-gui-animation-registration.patch', '04-script-tagged-frame-pointers.patch')]
    if api != 4:
        directory = repo / 'patches/qt4/android'
        if not directory.is_dir():
            raise ValueError('Missing Android patch directory: ' + str(directory))
        result += sorted(directory.glob('*.patch'))
        result.append(repo / 'patches/qt4/linux-sarge-llvm/01-xmlpatterns-color-mask.patch')
    return result


def recipe_inputs(repo, archive, profile, api):
    patches = selected_patches(repo, profile, api)
    helpers = [repo / 'scripts/build/qt4-android' / name for name in (
        'prepare-source.py', 'patch-qtcore.py')]
    return {'schema_version': 1, 'profile': profile, 'api': api,
            'archive_sha256': digest(archive),
            'files': {path.relative_to(repo).as_posix(): digest(path) for path in helpers + patches}}


def extract_source(archive, destination):
    # The pinned Qt 4.8.7 source distribution contains regular files and
    # directories only, below one root directory. Keep that explicit contract.
    with tarfile.open(archive, 'r:gz') as source:
        root_name = None
        for member in source:
            parts = PurePosixPath(member.name).parts
            if not parts or any(part in ('.', '..') for part in parts) or PurePosixPath(member.name).is_absolute():
                raise ValueError('Unexpected Qt source archive member: ' + member.name)
            if root_name is None:
                root_name = parts[0]
            if parts[0] != root_name or not (member.isdir() or member.isfile()):
                raise ValueError('Unsupported Qt source archive layout: ' + member.name)
            target = destination.joinpath(*parts[1:])
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with source.extractfile(member) as data, target.open('wb') as output:
                    shutil.copyfileobj(data, output)
                target.chmod(member.mode)


def apply_recipe(stage, repo, profile, api):
    environment = dict(os.environ, ANDROID_API=str(api))
    subprocess.run([sys.executable, str(repo / 'scripts/build/qt4-android/patch-qtcore.py'), profile],
                   cwd=stage, env=environment, check=True)
    for patch in selected_patches(repo, profile, api):
        with patch.open('rb') as data:
            subprocess.run(['patch', '-p1', '--fuzz=0', '--batch', '--forward'],
                           stdin=data, cwd=stage, check=True)


def source_inventory(stage):
    return {path.relative_to(stage).as_posix(): digest(path)
            for path in sorted(stage.rglob('*')) if path.is_file()}


def sync_sources(stage, tree, previous, current):
    # Compare prepared generations, not generated qconfig headers/Makefiles in
    # the live tree. Unchanged source inputs must not overwrite configure output.
    for name, sha in current.items():
        source, target = stage / name, tree / name
        if previous.get(name) != sha:
            target.parent.mkdir(parents=True, exist_ok=True)
            if not target.is_file() or digest(target) != sha:
                shutil.copyfile(source, target)
                target.chmod(source.stat().st_mode)
    for name in previous.keys() - current.keys():
        (tree / name).unlink(missing_ok=True)


def prepare(repo, archive, tree, profile, api):
    inputs = recipe_inputs(repo, archive, profile, api)
    state = tree / STATE
    previous = json.loads(state.read_text()) if state.is_file() else None
    if previous and previous['recipe'] == inputs and (tree / 'configure').is_file():
        return False
    tree.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='qt4-source-', dir=tree.parent) as directory:
        stage = Path(directory)
        extract_source(archive, stage)
        pristine = source_inventory(stage)
        apply_recipe(stage, repo, profile, api)
        current = source_inventory(stage)
        if 'configure' not in current:
            raise ValueError('Qt source archive does not contain configure')
        tree.mkdir(parents=True, exist_ok=True)
        sync_sources(stage, tree, previous['source'] if previous else {}, current)
        removed = sorted(pristine.keys() - current.keys())
        for name in removed:
            (tree / name).unlink(missing_ok=True)
        # A legacy tree has no prepared-source manifest. Reconfigure once after
        # migrating its sources, retaining unowned objects and other build files.
        configuration = {name: sha for name, sha in current.items()
                         if name == 'configure' or name.startswith(('qmake/', 'mkspecs/', 'config.tests/'))
                         or name.endswith(('.pro', '.pri', '.prf', '.conf'))
                         or name.startswith('src/corelib/global/qconfig')}
        if previous is None or previous.get('configuration') != configuration:
            (tree / '.donut-configured').unlink(missing_ok=True)
            (tree / '.longreach-configuration').unlink(missing_ok=True)
        configuration_key = hashlib.sha256(json.dumps(configuration, sort_keys=True).encode()).hexdigest()
        (tree / '.longreach-source-configuration').write_text(configuration_key + '\n')
        temporary = tree / (STATE + '.tmp')
        modified = {name: sha for name, sha in current.items() if pristine.get(name) != sha}
        temporary.write_text(json.dumps({'recipe': inputs, 'source': current,
                                         'configuration': configuration, 'modified_source': modified,
                                         'removed_source': removed}, sort_keys=True) + '\n')
        temporary.replace(state)
    return True


def verify_prepared(repo, archive, tree, profile, api):
    prepared = json.loads((tree / STATE).read_text())
    if prepared['recipe'] != recipe_inputs(repo, archive, profile, api):
        raise RuntimeError('Prepared Qt4 sources belong to another source recipe')
    actual = {name: digest(tree / name) for name in prepared['modified_source']}
    if actual != prepared['modified_source'] or any((tree / name).exists() for name in prepared['removed_source']):
        raise RuntimeError('Patched Qt4 sources differ from their prepared generation')
    return prepared


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--tree', type=Path, required=True)
    parser.add_argument('--profile', choices=('core', 'quick'), required=True)
    parser.add_argument('--api', choices=(4, 10, 21), type=int, required=True)
    args = parser.parse_args()
    changed = prepare(args.repo.resolve(), args.archive.resolve(), args.tree.resolve(), args.profile, args.api)
    print('Qt4 prepared sources: ' + ('updated' if changed else 'retained'))


if __name__ == '__main__':
    main()
