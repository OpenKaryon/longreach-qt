# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Bind a completed Android example generation and its APKs to one immutable SDK."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import uuid

REPO = Path(__file__).resolve().parents[3]
APPS = [line.strip() for line in (REPO / 'tests/expected-apps.txt').read_text().splitlines()
        if line.strip() and not line.lstrip().startswith('#') and line.strip() != 'smoke-runner']


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def write_json(path, value):
    temporary = path.with_name(path.name + '.tmp')
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
    temporary.replace(path)


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def identity(root, qt, abi, sdk=None):
    if sdk is None:
        sdk = (root / 'examples-sdk-image-id.txt').read_text().strip()
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', sdk):
        raise ValueError('Missing immutable SDK image identity')
    return {'qt_major': qt, 'abi': abi, 'sdk_image_id': sdk}


def source_files(root, qt, abi):
    bases = ['deployment', 'sdk-packaging', 'libc++_shared.so'] if qt == 6 else [
        'deployment', 'deployment-extended', 'sdk/jar', 'sdk/src/android/java', 'native/libc++_shared.so']
    required = [(f'deployment/{app}', app) for app in APPS]
    if qt == 5:
        required.append(('deployment-extended/qt-selftest', 'qt-selftest'))
    for directory, app in required:
        for name in (f'libs/{abi}/lib{app}_{abi}.so', 'res/values/libs.xml'):
            if not (root / directory / name).is_file():
                raise ValueError(f'Missing completed deployment: {directory}/{name}')
    jar = root / ('sdk-packaging/jar' if qt == 6 else 'sdk/jar')
    if not list(jar.glob('*.jar')):
        raise ValueError('Missing SDK Java JARs')
    result = {}
    for name in bases:
        base = root / name
        if not base.exists():
            raise ValueError(f'Missing example packaging input: {name}')
        paths = sorted(base.rglob('*')) if base.is_dir() else [base]
        for path in paths:
            if path.is_symlink() or not path.resolve().is_relative_to(root):
                raise ValueError(f'Unexpected linked packaging input: {path}')
            if path.is_file():
                result[path.relative_to(root).as_posix()] = digest(path)
    return result



def build_sources(qt):
    # Record the application snapshot independently of Git commit IDs, which
    # may change when the already-tested target commits are amended.
    paths = set()
    for directory in ('tests', 'cmake'):
        paths.update(path for path in (REPO / directory).rglob('*')
                     if path.is_file() and '__pycache__' not in path.parts and path.suffix != '.pyc')
    for name in ('build-examples.sh', 'deploy-examples.py', 'toolchain.cmake', 'target-config.sh', 'mkspec/qmake.conf'):
        path = REPO / f'scripts/build/qt{qt}-android' / name
        if path.is_file():
            paths.add(path)
    return {path.relative_to(REPO).as_posix(): digest(path) for path in sorted(paths)}


def begin(root, qt, abi, sdk):
    pending = identity(root, qt, abi, sdk)
    pending['generation'] = uuid.uuid4().hex
    pending['build_source_sha256'] = build_sources(qt)
    # Invalidate completion BEFORE any deployment or runtime can be overwritten.
    write_json(root / 'examples-in-progress.json', pending)
    for name in ('examples-manifest.json', 'apk-manifest.json'):
        (root / name).unlink(missing_ok=True)
    return pending


def finish(root, qt, abi, sdk):
    pending = read_json(root / 'examples-in-progress.json')
    expected = identity(root, qt, abi, sdk)
    if any(pending.get(k) != v for k, v in expected.items()):
        raise ValueError('Example generation does not match the selected SDK/ABI')
    if pending['build_source_sha256'] != build_sources(qt):
        raise ValueError('Application build inputs changed while examples were being compiled')
    pending['schema_version'] = 1
    pending['files'] = source_files(root, qt, abi)
    for name in ('sdk-image-id.txt', 'examples-sdk-image-id.txt'):
        (root / name).write_text(sdk + '\n')
    write_json(root / 'examples-manifest.json', pending)
    (root / 'examples-in-progress.json').unlink()
    return pending


def completed(root, qt, abi):
    if (root / 'examples-in-progress.json').exists():
        raise ValueError('Example generation is incomplete; rerun examples before packaging/testing')
    manifest = read_json(root / 'examples-manifest.json')
    if manifest.get('schema_version') != 1:
        raise ValueError('Unsupported example manifest')
    expected = identity(root, qt, abi)
    if any(manifest.get(k) != v for k, v in expected.items()):
        raise ValueError('Example manifest SDK/ABI differs from selected artifacts')
    if (root / 'sdk-image-id.txt').read_text().strip() != expected['sdk_image_id']:
        raise ValueError('SDK and example identities differ')
    return manifest


def check_examples(root, qt, abi):
    manifest = completed(root, qt, abi)
    if manifest['files'] != source_files(root, qt, abi):
        raise ValueError('Example/dependency/Java/runtime bytes changed after the completed build')
    return manifest


def apk_paths(qt):
    paths = [f'apk/{app}.apk' for app in APPS]
    if qt == 5:
        paths.append('apk/extended/qt-selftest.apk')
    return paths


def record_apks(root, qt, abi):
    examples = check_examples(root, qt, abi)
    result = {k: examples[k] for k in ('qt_major', 'abi', 'sdk_image_id', 'generation')}
    result['schema_version'] = 1
    result['examples_manifest_sha256'] = digest(root / 'examples-manifest.json')
    result['files'] = {name: digest(root / name) for name in apk_paths(qt)}
    write_json(root / 'apk-manifest.json', result)
    return result


def check_apks(root, qt, abi):
    examples = completed(root, qt, abi)
    apks = read_json(root / 'apk-manifest.json')
    if apks.get('schema_version') != 1 or any(
            apks.get(k) != examples[k] for k in ('qt_major', 'abi', 'sdk_image_id', 'generation')):
        raise ValueError('APKs belong to a different or incomplete example generation')
    if apks['examples_manifest_sha256'] != digest(root / 'examples-manifest.json'):
        raise ValueError('APK provenance does not match the completed examples')
    if apks['files'] != {name: digest(root / name) for name in apk_paths(qt)}:
        raise ValueError('APK bytes changed after packaging')
    return apks


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('begin', 'finish', 'check-examples', 'record-apks', 'check-apks'))
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--qt-major', type=int, choices=(5, 6), required=True)
    parser.add_argument('--abi', choices=('armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64'), required=True)
    parser.add_argument('--sdk-image-id')
    args = parser.parse_args()
    root = args.root.resolve()
    root.mkdir(parents=True, exist_ok=True)
    options = (root, args.qt_major, args.abi)
    if args.command in ('begin', 'finish'):
        if not args.sdk_image_id:
            parser.error('begin/finish require --sdk-image-id')
        globals()[args.command](*options, args.sdk_image_id)
    else:
        globals()[args.command.replace('-', '_')](*options)
    print(f'Android artifact {args.command}: Qt{args.qt_major} {args.abi} PASS')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError) as error:
        sys.exit(f'Android artifact validation failed: {error}')
