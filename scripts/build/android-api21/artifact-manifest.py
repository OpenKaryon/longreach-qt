# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Bind a completed Android example generation and its APKs to one immutable SDK."""
import argparse
from contextlib import contextmanager
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import sys
import shutil
import subprocess
import uuid

REPO = Path(__file__).resolve().parents[3]
_host_spec = importlib.util.spec_from_file_location('android_host_tools', Path(__file__).with_name('host-tools.py'))
_host_tools = importlib.util.module_from_spec(_host_spec)
_host_spec.loader.exec_module(_host_tools)
_report_spec = importlib.util.spec_from_file_location('android_sdk_reports', Path(__file__).with_name('sdk-reports.py'))
_reports = importlib.util.module_from_spec(_report_spec)
_report_spec.loader.exec_module(_reports)
APPS = [line.strip() for line in (REPO / 'tests/expected-apps.txt').read_text().splitlines()
        if line.strip() and not line.lstrip().startswith('#') and line.strip() != 'smoke-runner']


@contextmanager
def artifact_lease(root, already_held=False):
    # PowerShell's FileShare.None and this open stream exclude each other on
    # Windows. Python contenders additionally lock byte zero; on POSIX use
    # flock, as FileStream does for an exclusive share mode.
    # Internal subprocesses are explicitly delegated their parent's lease.
    if already_held:
        yield
        return
    busy = f'Another Longreach operation owns artifact directory: {root}'
    try:
        stream = (root / '.longreach-artifacts.lock').open('a+b')
    except OSError as error:
        raise RuntimeError(busy + ': ' + str(error)) from error
    with stream:
        stream.seek(0, 2)
        if not stream.tell():
            stream.write(b'0')
            stream.flush()
        stream.seek(0)
        try:
            if os.name == 'nt':
                import msvcrt
                msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as error:
            raise RuntimeError(busy) from error
        try:
            yield
        finally:
            stream.seek(0)
            if os.name == 'nt':
                msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(stream.fileno(), fcntl.LOCK_UN)


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def write_text_atomic(path, value):
    temporary = path.with_name(path.name + '.' + uuid.uuid4().hex + '.tmp')
    try:
        with temporary.open('x', encoding='utf-8', newline='\n') as stream:
            stream.write(value)
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def write_json(path, value):
    write_text_atomic(path, json.dumps(value, indent=2, sort_keys=True) + '\n')


def invalidate_results(root):
    # A new generation or run cannot inherit the previous aggregate PASS.
    # Keep APKs, individual run directories and screenshots themselves intact.
    for name in ('final-results.json', 'final-results-table.md', 'apk-native-abi-check.json',
                 'apk-architecture-final.json', 'screenshots.json'):
        (root / name).unlink(missing_ok=True)


def create_json(path, value):
    # Reserve a generation atomically, including callers outside PowerShell.
    with path.open('x', encoding='utf-8') as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write('\n')


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def identity(root, qt, abi, sdk=None):
    if sdk is None:
        sdk = (root / 'examples-sdk-image-id.txt').read_text().strip()
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', sdk):
        raise ValueError('Missing immutable SDK image identity')
    return {'qt_major': qt, 'abi': abi, 'sdk_image_id': sdk}


def source_files(root, qt, abi, include_reports=True, sdk=None):
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
    if include_reports:
        result.update(producer_reports(root, qt, abi, sdk or identity(root, qt, abi)['sdk_image_id']))
        runtime = root / ('libc++_shared.so' if qt == 6 else 'native/libc++_shared.so')
        if digest(runtime) != (root / 'runtime-sha256.txt').read_text().split()[0]:
            raise ValueError('Example runtime bytes changed from SDK producer report')
    return result


def producer_reports(root, qt, abi, sdk):
    return _reports.verify_export(root, qt, abi, sdk)


def build_sources(qt):
    # Record the application snapshot independently of Git commit IDs, which
    # may change when the already-tested target commits are amended.
    paths = set()
    for directory in ('tests', 'cmake'):
        paths.update(path for path in (REPO / directory).rglob('*')
                     if path.is_file() and '__pycache__' not in path.parts and path.suffix not in ('.pyc', '.java'))
    paths.add(REPO / 'scripts/build/android-api21/sdk-reports.py')
    for name in ('build-examples.sh', 'deploy-examples.py', 'toolchain.cmake', 'target-config.sh', 'mkspec/qmake.conf'):
        path = REPO / f'scripts/build/qt{qt}-android' / name
        if path.is_file():
            paths.add(path)
    return {path.relative_to(REPO).as_posix(): digest(path) for path in sorted(paths)}


def begin(root, qt, abi, sdk):
    if (root / 'examples-in-progress.json').exists():
        raise ValueError('An incomplete example generation already exists; stop its producer before explicit recovery')
    pending = identity(root, qt, abi, sdk)
    pending['generation'] = uuid.uuid4().hex
    pending['build_source_sha256'] = build_sources(qt)
    # Invalidate completion BEFORE any deployment or runtime can be overwritten.
    create_json(root / 'examples-in-progress.json', pending)
    invalidate_results(root)
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
    pending['schema_version'] = 2
    pending['files'] = source_files(root, qt, abi, sdk=sdk)
    for name in ('sdk-image-id.txt', 'examples-sdk-image-id.txt'):
        (root / name).write_text(sdk + '\n')
    write_json(root / 'examples-manifest.json', pending)
    (root / 'examples-in-progress.json').unlink()
    return pending


def completed(root, qt, abi):
    if (root / 'examples-in-progress.json').exists():
        raise ValueError('Example generation is incomplete; rerun examples before packaging/testing')
    manifest = read_json(root / 'examples-manifest.json')
    if manifest.get('schema_version') not in (1, 2):
        raise ValueError('Unsupported example manifest')
    expected = identity(root, qt, abi)
    if any(manifest.get(k) != v for k, v in expected.items()):
        raise ValueError('Example manifest SDK/ABI differs from selected artifacts')
    if (root / 'sdk-image-id.txt').read_text().strip() != expected['sdk_image_id']:
        raise ValueError('SDK and example identities differ')
    return manifest


def check_examples(root, qt, abi):
    manifest = completed(root, qt, abi)
    if manifest['files'] != source_files(root, qt, abi, include_reports=manifest['schema_version'] >= 2, sdk=manifest['sdk_image_id']):
        raise ValueError('Example/dependency/Java/runtime bytes changed after the completed build')
    return manifest


def apk_paths(qt):
    paths = [f'apk/{app}.apk' for app in APPS]
    if qt == 5:
        paths.append('apk/extended/qt-selftest.apk')
    return paths


_native_abi = None


def native_abi():
    global _native_abi
    if _native_abi is None:
        spec = importlib.util.spec_from_file_location('android_packaged_native_abi', Path(__file__).with_name('native-abi.py'))
        _native_abi = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(_native_abi)
    return _native_abi


def apk_digest(root, relative):
    path = root / relative
    if not path.resolve().is_relative_to(root.resolve()):
        raise ValueError('Linked APK leaves the artifact root')
    for parent in (path, *path.parents):
        if parent == root.parent:
            break
        if parent.is_symlink() or (hasattr(parent, 'is_junction') and parent.is_junction()):
            raise ValueError('Linked APK input: ' + relative)
    return digest(path)


def packaging_inputs(qt, android_sdk, javac=None):
    android_sdk = Path(android_sdk).resolve()
    javac = Path(javac or shutil.which('javac') or 'missing-javac').resolve()
    sources = sorted((REPO / f'scripts/build/qt{qt}-android').glob('package*.ps1'))
    java = (REPO / 'tests/android-donut/java' if qt == 4
            else REPO / 'tests/android' / ('java-qt6' if qt == 6 else 'java'))
    sources += sorted(p for p in java.rglob('*') if p.is_file())
    if qt == 4:
        sources += [REPO / 'scripts/build/qt4-android' / name
                    for name in ('host.ps1', 'api21.ps1', 'artifact-manifest.py')]
    sources += [p for p in (REPO / 'scripts/build/android-api21').glob('artifact-*') if p.is_file()]
    sources += [REPO / 'scripts/build/android-api21' / name for name in ('host-tools.py', 'packaging-host.ps1', 'sdk-reports.py', 'sdk-reports.ps1', 'check-api10-api21-symbols.py')
                if (REPO / 'scripts/build/android-api21' / name).is_file()]
    snapshot = _host_tools.snapshot(android_sdk, javac)
    if qt != 4:
        path = android_sdk / 'platforms/android-35/framework.aidl'
        snapshot['tool_sha256']['android-sdk/platforms/android-35/framework.aidl'] = digest(path)
    sources.append(REPO / 'scripts/fetch/locks/android-windows-host-tools.json')
    snapshot['source_sha256'] = {p.relative_to(REPO).as_posix(): digest(p) for p in sources}
    return snapshot



def signing_inputs(root, qt):
    required = ['apk/local-examples.jks'] + (['apk/extended/local-examples.jks'] if qt == 5 else [])
    for relative in required:
        if not (root / relative).is_file():
            raise ValueError('Missing initial signing key: ' + relative)
    return {p.relative_to(root).as_posix(): digest(p) for p in sorted((root / 'apk').rglob('*.jks'))}


def begin_apks(root, qt, abi, android_sdk, javac=None):
    pending = root / 'apk-in-progress.json'
    if pending.exists():
        raise ValueError('An incomplete APK generation already exists; stop its producer before explicit recovery')
    invalidate_results(root)
    examples = check_examples(root, qt, abi)
    # Capture Java, scripts and tools before any APK is replaced.
    state = {'examples_manifest_sha256': digest(root / 'examples-manifest.json'),
             'packaging_inputs': packaging_inputs(qt, android_sdk, javac),
             'signing_inputs': signing_inputs(root, qt), 'generation': examples['generation'],
             'sdk_report_sha256': producer_reports(root, qt, abi, examples['sdk_image_id'])}
    create_json(pending, state)
    (root / 'apk-manifest.json').unlink(missing_ok=True)
    return state


def record_apks(root, qt, abi, android_sdk=None, javac=None):
    examples = check_examples(root, qt, abi)
    pending = read_json(root / 'apk-in-progress.json')
    if pending['generation'] != examples['generation'] or pending['examples_manifest_sha256'] != digest(root / 'examples-manifest.json'):
        raise ValueError('Native example generation changed during packaging')
    if pending['packaging_inputs'] != packaging_inputs(qt, android_sdk, javac):
        raise ValueError('Java, packaging scripts or tools changed during packaging')
    if pending['sdk_report_sha256'] != producer_reports(root, qt, abi, examples['sdk_image_id']):
        raise ValueError('SDK producer reports changed during packaging')
    keys = signing_inputs(root, qt)
    if keys != pending['signing_inputs']:
        raise ValueError('Signing input changed during packaging')
    result = {k: examples[k] for k in ('qt_major', 'abi', 'sdk_image_id', 'generation')}
    result.update(schema_version=2, examples_manifest_sha256=pending['examples_manifest_sha256'],
                  packaging_inputs=pending['packaging_inputs'], signing_inputs=keys, sdk_report_sha256=pending['sdk_report_sha256'])
    result['files'] = {name: apk_digest(root, name) for name in apk_paths(qt)}
    for name in result['files']:
        native_abi().inspect_apk(root / name, abi)
    write_json(root / 'apk-manifest.json', result)
    (root / 'apk-in-progress.json').unlink()
    return result


def check_apks(root, qt, abi):
    examples = completed(root, qt, abi)
    if (root / 'apk-in-progress.json').exists():
        raise ValueError('APK generation is incomplete; rerun packaging after explicit recovery')
    apks = read_json(root / 'apk-manifest.json')
    if apks.get('schema_version') != 2 or any(
            apks.get(k) != examples[k] for k in ('qt_major', 'abi', 'sdk_image_id', 'generation')):
        raise ValueError('APKs belong to a different or incomplete example generation')
    if apks['sdk_report_sha256'] != producer_reports(root, qt, abi, examples['sdk_image_id']):
        raise ValueError('SDK producer reports differ from the packaged generation')
    if apks['examples_manifest_sha256'] != digest(root / 'examples-manifest.json'):
        raise ValueError('APK provenance does not match the completed examples')
    if apks['files'] != {name: apk_digest(root, name) for name in apk_paths(qt)}:
        raise ValueError('APK bytes changed after packaging')
    for name in apks['files']:
        native_abi().inspect_apk(root / name, abi)
    return apks


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('begin', 'finish', 'check-examples', 'begin-apks', 'record-apks', 'check-apks'))
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--qt-major', type=int, choices=(5, 6), required=True)
    parser.add_argument('--abi', choices=('armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64'), required=True)
    parser.add_argument('--sdk-image-id')
    parser.add_argument('--android-sdk', type=Path)
    parser.add_argument('--javac', type=Path)
    parser.add_argument('--artifact-lease-held', action='store_true',
                        help='internal: the calling process already holds the artifact lease')
    args = parser.parse_args()
    root = args.root.resolve()
    root.mkdir(parents=True, exist_ok=True)
    options = (root, args.qt_major, args.abi)
    with artifact_lease(root, args.artifact_lease_held):
        if args.command in ('begin', 'finish'):
            if not args.sdk_image_id:
                parser.error('begin/finish require --sdk-image-id')
            globals()[args.command](*options, args.sdk_image_id)
        elif args.command in ('begin-apks', 'record-apks'):
            if not args.android_sdk:
                parser.error('APK generation requires --android-sdk')
            globals()[args.command.replace('-', '_')](*options, args.android_sdk, args.javac)
        else:
            globals()[args.command.replace('-', '_')](*options)
    print(f'Android artifact {args.command}: Qt{args.qt_major} {args.abi} PASS')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError) as error:
        sys.exit(f'Android artifact validation failed: {error}')
