# SPDX-License-Identifier: GPL-3.0-or-later
"""Seal and export the exact producer-report set from an immutable Android SDK."""
import argparse
from contextlib import nullcontext
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import uuid

INVENTORY = 'sdk-report-inventory.json'
SOURCE = 'sdk-report-source.json'
CONTROL = {INVENTORY, SOURCE, 'sdk-image-id.txt'}
NAMED = {'qt-sdk-config.summary', 'qt-patch-state.json', 'runtime-sha256.txt', 'runtime-elf.txt',
         'runtime-atomic-exports.txt', 'platform-input-provenance.json', 'runtime-input-provenance.json'}


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def write(path, value):
    temporary = path.with_name(path.name + '.' + uuid.uuid4().hex + '.tmp')
    try:
        temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n', encoding='utf-8')
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def target(qt, abi):
    abis = ('x86', 'x86_64', 'arm64-v8a') if qt == 4 else ('armeabi-v7a', 'x86', 'x86_64', 'arm64-v8a')
    if qt not in (4, 5, 6) or abi not in abis:
        raise ValueError('Unsupported installed Android SDK target')
    return {'qt_major': qt, 'abi': abi, 'api': 10 if (qt == 4 and abi == 'x86') or (qt == 5 and abi in ('x86', 'armeabi-v7a')) else 21}


def required(qt, abi):
    selected = target(qt, abi)
    names = {'sdk-modules.txt', 'sdk-qmake-query.txt', 'sdk-compiler-version.txt', 'runtime-sha256.txt', 'runtime-elf.txt'}
    if qt == 4:
        names.update(('sdk-static-elf.json', 'sdk-provenance.json'))
        if selected['api'] == 10:
            names.add('runtime-input-provenance.json')
    else:
        names.update(('qt-sdk-config.summary', 'qt-patch-state.json', f'sdk-api{selected["api"]}-elf.json',
                      'platform-input-provenance.json' if selected['api'] == 21 else 'runtime-input-provenance.json'))
    if qt == 5 and selected['api'] == 10:
        names.add('sdk-api21-forward-symbols.json')
    names.add('runtime-atomic-exports.txt')
    return names


def files(directory):
    result = {}
    for path in sorted(directory.rglob('*')):
        if path.is_symlink():
            raise ValueError('Linked SDK producer report: ' + str(path))
        if path.is_file():
            name = path.relative_to(directory).as_posix()
            if name != INVENTORY:
                result[name] = digest(path)
    return result


def policy(record, qt, abi):
    selected = target(qt, abi)
    names = record.get('files', {})
    if (record.get('schema_version') != 1 or any(record.get(key) != value for key, value in selected.items()) or
            not isinstance(names, dict) or not re.fullmatch(r'[0-9a-f]{64}', record.get('producer_source_sha256', ''))):
        raise ValueError('Missing or mismatched SDK producer inventory')
    audit = {name for name in names if name.startswith('sdk-java-audit/')}
    if (set(names) != required(qt, abi) | audit or
            (qt == 6 and (len(audit) != 10 or any(not name.endswith('.jar') or len(PurePosixPath(name).parts) != 2 for name in audit))) or
            (qt != 6 and audit)):
        raise ValueError('SDK producer report set differs from the target policy')
    for name, sha in names.items():
        path = PurePosixPath(name)
        if path.is_absolute() or '..' in path.parts or '\\' in name or ':' in name or not re.fullmatch(r'[0-9a-f]{64}', sha):
            raise ValueError('Invalid SDK producer report entry')
    return selected


def seal(directory, qt, abi):
    (directory / INVENTORY).unlink(missing_ok=True)
    record = {'schema_version': 1, **target(qt, abi), 'producer_source_sha256': digest(Path(__file__)), 'files': files(directory)}
    policy(record, qt, abi)
    write(directory / INVENTORY, record)
    return record


def verify_producer(directory, qt, abi):
    record = read(directory / INVENTORY)
    policy(record, qt, abi)
    if files(directory) != record['files']:
        raise ValueError('SDK producer report bytes or exact file set changed')
    return record


def visible(directory, dedicated=False):
    if dedicated:
        result = set()
        for path in directory.rglob('*'):
            parts = path.relative_to(directory).parts
            if parts[0] == 'sdk-report-history' or parts[0].startswith(('.sdk-report-input-', '.sdk-report-export-')):
                continue
            if path.is_file() and not (len(parts) == 1 and (path.name in CONTROL or path.name == '.longreach-artifacts.lock')):
                result.add(path.relative_to(directory).as_posix())
        return result
    result = set()
    for path in directory.iterdir():
        if path.is_file() and path.name not in CONTROL and (path.name.startswith('sdk-') or path.name in NAMED):
            result.add(path.name)
    audit = directory / 'sdk-java-audit'
    if audit.exists():
        result.update(path.relative_to(directory).as_posix() for path in audit.rglob('*') if path.is_file())
    return result


def verify_export(directory, qt, abi, sdk):
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', sdk):
        raise ValueError('Missing immutable SDK report source identity')
    record = read(directory / INVENTORY)
    selected = policy(record, qt, abi)
    source = read(directory / SOURCE)
    if (source.get('schema_version') != 1 or source.get('sdk_image_id') != sdk or
            any(source.get(key) != value for key, value in selected.items()) or
            source.get('inventory_sha256') != digest(directory / INVENTORY)):
        raise ValueError('SDK report export belongs to a different image/inventory')
    if visible(directory, dedicated=qt == 4) != set(record['files']):
        raise ValueError('Exported SDK producer report set changed')
    actual = {name: digest(directory / name) for name in record['files']}
    if actual != record['files']:
        raise ValueError('Exported SDK producer report bytes changed')
    return {**actual, INVENTORY: digest(directory / INVENTORY), SOURCE: digest(directory / SOURCE)}


def export(source, output, qt, abi, sdk):
    """Caller owns the artifact lease; update reports only, preserving old bytes."""
    if output.resolve().is_relative_to(source.resolve()):
        raise ValueError('SDK report export cannot write into its producer directory')
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', sdk):
        raise ValueError('Missing immutable SDK report source identity')
    for name in ('final-results.json', 'final-results-table.md', 'apk-native-abi-check.json', 'apk-architecture-final.json', 'screenshots.json'):
        (output / name).unlink(missing_ok=True)
    record = verify_producer(source, qt, abi)
    if qt == 4 and visible(output, dedicated=True) != visible(output):
        raise ValueError('Qt4 SDK report directory contains unrecognized files; archive them explicitly')
    try:
        current = verify_export(output, qt, abi, sdk)
    except (FileNotFoundError, ValueError, KeyError):
        current = None
    if current and current[INVENTORY] == digest(source / INVENTORY):
        return current  # identical immutable SDK: keep report files and history
    stage = output / ('.sdk-report-export-' + uuid.uuid4().hex)
    stage.mkdir()
    for name in [*record['files'], INVENTORY]:
        target_path = stage / name
        target_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / name, target_path)
    binding = {'schema_version': 1, **target(qt, abi), 'sdk_image_id': sdk, 'inventory_sha256': digest(stage / INVENTORY)}
    write(stage / SOURCE, binding)
    verify_export(stage, qt, abi, sdk)
    old = visible(output) | {name for name in (INVENTORY, SOURCE) if (output / name).is_file()}
    if old:
        history = output / 'sdk-report-history' / uuid.uuid4().hex
        for name in sorted(old):
            backup = history / name
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(output / name, backup)
    # Remove the completion marker before the first live file can change.
    (output / SOURCE).unlink(missing_ok=True)
    for name in old - {SOURCE}:
        (output / name).unlink()
    for name in [*record['files'], INVENTORY]:
        destination = output / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(stage / name, destination)
    if verify_producer(source, qt, abi) != record or digest(source / INVENTORY) != binding['inventory_sha256']:
        raise ValueError('SDK report source changed during export')
    if (visible(output, dedicated=qt == 4) != set(record['files']) or
            any(digest(output / name) != sha for name, sha in record['files'].items()) or
            digest(output / INVENTORY) != binding['inventory_sha256']):
        raise ValueError('SDK report export copy changed before publication')
    try:
        write(output / SOURCE, binding)  # publish the source binding last
        result = verify_export(output, qt, abi, sdk)
    except BaseException:
        (output / SOURCE).unlink(missing_ok=True)
        raise
    # Only a successful, owned stage is removed; interrupted stages survive.
    if stage.resolve().parent != output.resolve() or stage.is_symlink():
        raise ValueError('Unexpected SDK report stage cleanup path')
    for path in sorted(stage.rglob('*'), key=lambda item: len(item.parts), reverse=True):
        path.rmdir() if path.is_dir() else path.unlink()
    stage.rmdir()
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('seal', 'export', 'verify'))
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--qt-major', type=int, choices=(4, 5, 6), required=True)
    parser.add_argument('--abi', required=True)
    parser.add_argument('--sdk-image-id', default=os.environ.get('LONGREACH_SDK_IMAGE_ID'))
    parser.add_argument('--artifact-lease-held', action='store_true', help='internal: host producer owns the output lease')
    args = parser.parse_args(argv)
    if args.action == 'seal':
        seal(args.source, args.qt_major, args.abi)
    elif args.action == 'verify':
        verify_producer(args.source, args.qt_major, args.abi)
    else:
        if not args.output:
            parser.error('export requires --output')
        args.output = args.output.resolve()
        args.output.mkdir(parents=True, exist_ok=True)
        lease = nullcontext()
        if not args.artifact_lease_held:
            spec = importlib.util.spec_from_file_location('report_artifact_lease', Path(__file__).with_name('artifact-manifest.py'))
            artifacts = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(artifacts)
            lease = artifacts.artifact_lease(args.output)
        with lease:
            export(args.source, args.output, args.qt_major, args.abi, args.sdk_image_id or '')


if __name__ == '__main__':
    main()
