#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Prepare API21 media from pinned archives; verify retained extracted bytes."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import uuid
import zipfile

ABIS = ('armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64')
LOCK = 'scripts/fetch/locks/qt6-android-api21-inputs.json'


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def write_json(path, value):
    temporary = path.with_name(path.name + '.' + uuid.uuid4().hex + '.tmp')
    try:
        temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n', encoding='utf-8')
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def layout(abi):
    if abi not in ABIS:
        raise ValueError('Unsupported API21 ABI')
    tools, prefix, frontend, engines = {
        'armeabi-v7a': ('tools_r24.4.1-windows.zip', '', 'tools/emulator-arm.exe', ['tools/emulator-arm.exe']),
        'arm64-v8a': ('tools_r25.2.5-windows.zip', 'emulator-25.2.5/', 'tools/emulator.exe',
                      ['tools/qemu/windows-x86_64/qemu-system-aarch64.exe', 'tools/qemu/windows-x86/qemu-system-aarch64.exe']),
        'x86': ('emulator-windows_x64-9536276.zip', 'emulator-32.1.11/', 'emulator/emulator.exe',
                ['emulator/qemu/windows-x86_64/qemu-system-i386-headless.exe', 'emulator/qemu/windows-x86_64/qemu-system-i386.exe']),
        'x86_64': ('emulator-windows_x64-9536276.zip', 'emulator-32.1.11/', 'emulator/emulator.exe',
                   ['emulator/qemu/windows-x86_64/qemu-system-x86_64-headless.exe', 'emulator/qemu/windows-x86_64/qemu-system-x86_64.exe']),
    }[abi]
    return tools, prefix, {
        'emulator': prefix + frontend, 'engine_candidates': [prefix + name for name in engines],
        'kernel': abi + ('/kernel-ranchu' if abi in ('x86', 'x86_64') else '/kernel-qemu'),
        'ramdisk': abi + '/ramdisk.img', 'system': abi + '/system.img', 'userdata': abi + '/userdata.img',
        'build_properties': abi + '/build.prop',
    }


def inventory(base, roots):
    result = set()
    for name in roots:
        directory = base / name
        if not directory.is_dir() or directory.is_symlink():
            return None
        for path in directory.rglob('*'):
            if path.is_symlink():
                return None
            if path.is_file():
                result.add(path.relative_to(base).as_posix())
    return result


def files_match(base, files):
    return all((base / name).is_file() and not (base / name).is_symlink() and digest(base / name) == sha
               for name, sha in files.items())


def prepare_archive(archive, expected_sha, destination, required, derived=()):
    archive_sha = digest(archive)
    if archive_sha != expected_sha:
        raise ValueError('SHA256 mismatch: ' + archive.name)
    destination.mkdir(parents=True, exist_ok=True)
    receipt_path = destination / (archive.name + '.extracted.json')
    recipe = {'schema_version': 1, 'archive_sha256': archive_sha, 'extractor_sha256': digest(Path(__file__))}
    with zipfile.ZipFile(archive) as package:
        members = []
        for member in package.infolist():
            path = PurePosixPath(member.filename)
            if path.is_absolute() or '..' in path.parts or '\\' in member.filename or ':' in member.filename:
                raise ValueError('Invalid media path')
            if not member.is_dir():
                members.append((member, path.as_posix()))
        names = {name for _, name in members}
        if len(names) != len(members) or not names or not set(required).issubset(names):
            raise ValueError('Incomplete or duplicate media archive: ' + archive.name)
        roots = sorted({name.split('/')[0] for name in names})
        if any('/' not in name for name in names):
            raise ValueError('Expected media archive directories')
        try:
            old = json.loads(receipt_path.read_text(encoding='utf-8'))
        except (FileNotFoundError, ValueError):
            old = {}
        expected = old.get('files', {})
        actual = inventory(destination, roots)
        # A marker alone is insufficient. Retained bytes and the owned file set
        # must still match a receipt produced by extraction of this exact archive.
        if (all(old.get(key) == value for key, value in recipe.items()) and isinstance(expected, dict) and
                set(expected) == names and actual is not None and actual - set(derived) == names and
                files_match(destination, expected)):
            return expected
        receipt_path.unlink(missing_ok=True)
        stage = destination / ('.extract-' + uuid.uuid4().hex)
        stage.mkdir()
        files = {}
        for member, name in members:
            target = stage / name
            target.parent.mkdir(parents=True, exist_ok=True)
            with package.open(member) as incoming, target.open('wb') as outgoing:
                shutil.copyfileobj(incoming, outgoing)
            files[name] = digest(target)
        # zipfile verifies member CRCs while reading. Nothing is installed until
        # every archive member was read successfully; partial staging is retained.
        previous = destination / ('previous-extraction-' + uuid.uuid4().hex)
        for name in roots:
            current = destination / name
            if current.exists():
                previous.mkdir(exist_ok=True)
                current.replace(previous / name)
            (stage / name).replace(current)
        stage.rmdir()
        if inventory(destination, roots) != names or not files_match(destination, files):
            raise ValueError('Extracted media changed before completion')
        write_json(receipt_path, {**recipe, 'files': files})
        return files


def ready_path(output, abi):
    return output / 'media' / ('prepared-' + abi + '.json')


def validate_ready(ready, output, abi, repo, verify_files=True):
    tools, prefix, roles = layout(abi)
    lock = json.loads((repo / LOCK).read_text())
    locked = {item['file']: item['sha256'] for item in lock['sources']}
    images = [name for name in locked if name.startswith(f'{abi}-21_r')]
    files = ready.get('files', {})
    roots = ready.get('owned_roots', [])
    if (ready.get('schema_version') != 1 or ready.get('abi') != abi or ready.get('roles') != roles or
            ready.get('extractor_sha256') != digest(Path(__file__)) or
            ready.get('input_lock_sha256') != digest(repo / LOCK) or not files or
            roots != [abi, prefix + ('emulator' if abi in ('x86', 'x86_64') else 'tools')] or
            not {roles['emulator'], *roles['engine_candidates'], *[roles[key] for key in ('kernel', 'ramdisk', 'system', 'userdata', 'build_properties')], abi + '/system/build.prop'}.issubset(files) or
            any(locked.get(item['file']) != item['sha256'] for item in ready.get('archives', [])) or
            len(images) != 1 or len(ready.get('archives', [])) != 2 or {item['file'] for item in ready.get('archives', [])} != {tools, *images}):
        raise ValueError('Missing or mismatched prepared API21 media receipt')
    if verify_files and (inventory(output / 'media', roots) != set(files) or not files_match(output / 'media', files)):
        raise ValueError('Prepared API21 media bytes or inventory changed')
    return ready


def verify_ready(output, abi, repo, verify_files=True):
    return validate_ready(json.loads(ready_path(output, abi).read_text(encoding='utf-8')),
                          output, abi, repo, verify_files)


def prepare(repo, output, abi):
    root = output / 'media'
    root.mkdir(parents=True, exist_ok=True)
    ready_path(output, abi).unlink(missing_ok=True)
    lock = json.loads((repo / LOCK).read_text())
    tools, prefix, roles = layout(abi)
    images = [item['file'] for item in lock['sources'] if item['file'].startswith(f'{abi}-21_r')]
    if len(images) != 1:
        raise ValueError('Expected one pinned API21 system image for ' + abi)
    files, archives = {}, []
    for name, extract_prefix in ((images[0], ''), (tools, prefix)):
        record = next(item for item in lock['sources'] if item['file'] == name)
        required = ([roles[key] for key in ('kernel', 'ramdisk', 'system', 'userdata', 'build_properties')]
                    if name == images[0] else [roles['emulator'], *roles['engine_candidates']])
        required = [value.removeprefix(extract_prefix) for value in required]
        derived = [abi + '/system/build.prop'] if name == images[0] else []
        extracted = prepare_archive(repo / 'downloads/android-lollipop' / name, record['sha256'],
                                    root / extract_prefix, required, derived)
        files.update({extract_prefix + key: sha for key, sha in extracted.items()})
        archives.append({'file': name, 'sha256': record['sha256']})
    # SDK Tools24 reads this compatibility copy rather than guessing API10000.
    properties = root / abi / 'system/build.prop'
    properties.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(root / roles['build_properties'], properties)
    files[abi + '/system/build.prop'] = digest(properties)
    ready = {'schema_version': 1, 'abi': abi, 'extractor_sha256': digest(Path(__file__)),
             'input_lock_sha256': digest(repo / LOCK), 'archives': archives, 'roles': roles, 'files': files,
             'owned_roots': [abi, prefix.rstrip('/') + '/emulator' if prefix.startswith('emulator-32')
                             else prefix + 'tools']}
    write_json(ready_path(output, abi), ready)
    verify_ready(output, abi, repo)
    return ready


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--abi', choices=ABIS, default='armeabi-v7a')
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(argv)
    prepare(args.repo, args.output, args.abi)
    print(f'Prepared verified Android5.0.2/API21 {args.abi} emulator media')


if __name__ == '__main__':
    main()
