# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Bind a completed Android example generation and its APKs to one immutable SDK."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import shutil
import subprocess
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


def source_files(root, qt, abi, include_reports=True):
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
        result.update(producer_reports(root))
    return result


def producer_reports(root):
    paths = list(root.glob('sdk-*.json')) + list(root.glob('sdk-*.txt'))
    paths += [root / 'platform-input-provenance.json', root / 'runtime-input-provenance.json', root / 'qt-patch-state.json']
    return {p.relative_to(root).as_posix(): digest(p) for p in paths if p.is_file() and p.name != 'sdk-image-id.txt'}



def build_sources(qt):
    # Record the application snapshot independently of Git commit IDs, which
    # may change when the already-tested target commits are amended.
    paths = set()
    for directory in ('tests', 'cmake'):
        paths.update(path for path in (REPO / directory).rglob('*')
                     if path.is_file() and '__pycache__' not in path.parts and path.suffix not in ('.pyc', '.java'))
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
    if manifest['files'] != source_files(root, qt, abi, include_reports=manifest['schema_version'] >= 2):
        raise ValueError('Example/dependency/Java/runtime bytes changed after the completed build')
    return manifest


def apk_paths(qt):
    paths = [f'apk/{app}.apk' for app in APPS]
    if qt == 5:
        paths.append('apk/extended/qt-selftest.apk')
    return paths


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
    java = REPO / 'tests/android' / ('java-qt6' if qt == 6 else 'java')
    sources += sorted(p for p in java.rglob('*') if p.is_file())
    sources += [p for p in (REPO / 'scripts/build/android-api21').glob('artifact-*') if p.is_file()]
    tools = android_sdk / 'build-tools/36.0.0'
    if not tools.is_dir():
        raise ValueError('Missing pinned-version Android build tools 36.0.0')
    external = sorted(p for p in tools.rglob('*') if p.is_file())
    external += [android_sdk / 'platforms/android-35/android.jar',
                 android_sdk / 'platforms/android-35/framework.aidl', javac]
    # javac/keytool use one JDK; d8/apksigner batch launchers may select
    # JAVA_HOME or a different java on PATH. Capture both toolchains.
    java_roots = {javac.parent.parent}
    if os.environ.get('JAVA_HOME'):
        java_roots.add(Path(os.environ['JAVA_HOME']).resolve())
    if shutil.which('java'):
        java_roots.add(Path(shutil.which('java')).resolve().parent.parent)
    for java_root in sorted(java_roots):
        external += [p for p in (java_root / 'bin').glob('*') if p.is_file()]
        external += [p for p in (java_root / 'conf').rglob('*') if p.is_file()]
        for relative in ('release', 'lib/modules', 'lib/tools.jar', 'jre/lib/rt.jar'):
            if (java_root / relative).is_file():
                external.append(java_root / relative)
    return {'source_sha256': {p.relative_to(REPO).as_posix(): digest(p) for p in sources},
            'tool_sha256': {str(p): digest(p) for p in external},
            'javac_version': subprocess.check_output([str(javac), '-version'], text=True, stderr=subprocess.STDOUT).strip()}


def signing_inputs(root):
    return {p.relative_to(root).as_posix(): digest(p) for p in sorted((root / 'apk').rglob('*.jks'))}


def begin_apks(root, qt, abi, android_sdk, javac=None):
    examples = check_examples(root, qt, abi)
    pending = root / 'apk-in-progress.json'
    if pending.exists():
        raise ValueError('An incomplete APK generation already exists; stop its producer before explicit recovery')
    # Capture Java, scripts and tools before any APK is replaced.
    state = {'examples_manifest_sha256': digest(root / 'examples-manifest.json'),
             'packaging_inputs': packaging_inputs(qt, android_sdk, javac),
             'signing_inputs': signing_inputs(root), 'generation': examples['generation'],
             'sdk_report_sha256': producer_reports(root)}
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
    if pending['sdk_report_sha256'] != producer_reports(root):
        raise ValueError('SDK producer reports changed during packaging')
    keys = signing_inputs(root)
    if any(keys.get(k) != v for k, v in pending['signing_inputs'].items()):
        raise ValueError('Signing input changed during packaging')
    result = {k: examples[k] for k in ('qt_major', 'abi', 'sdk_image_id', 'generation')}
    result.update(schema_version=2, examples_manifest_sha256=pending['examples_manifest_sha256'],
                  packaging_inputs=pending['packaging_inputs'], signing_inputs=keys, sdk_report_sha256=pending['sdk_report_sha256'])
    result['files'] = {name: apk_digest(root, name) for name in apk_paths(qt)}
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
    if apks['sdk_report_sha256'] != producer_reports(root):
        raise ValueError('SDK producer reports differ from the packaged generation')
    if apks['examples_manifest_sha256'] != digest(root / 'examples-manifest.json'):
        raise ValueError('APK provenance does not match the completed examples')
    if apks['files'] != {name: apk_digest(root, name) for name in apk_paths(qt)}:
        raise ValueError('APK bytes changed after packaging')
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
    args = parser.parse_args()
    root = args.root.resolve()
    root.mkdir(parents=True, exist_ok=True)
    options = (root, args.qt_major, args.abi)
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
