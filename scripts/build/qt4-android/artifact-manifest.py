# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Bind installed-SDK Qt4 native generations, packaged bytes and tool receipts."""
import argparse
import hashlib
import importlib.util
from pathlib import Path
import re
import sys
import uuid
import zipfile

_spec = importlib.util.spec_from_file_location('android_artifacts', Path(__file__).resolve().parents[1] / 'android-api21/artifact-manifest.py')
common = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(common)

PROFILES = ('bootstrap', 'strict', 'core', 'selftest', 'widgets', 'graphics',
            'painting', 'multimedia', 'gl', 'qml', 'network', 'quick')


def identity(root, abi, sdk=None):
    if sdk is None:
        sdk = (root / 'sdk-image-id.txt').read_text().strip()
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', sdk):
        raise ValueError('Missing immutable Qt4 SDK image identity')
    return {'qt_major': 4, 'abi': abi, 'api': 10 if abi == 'x86' else 21, 'sdk_image_id': sdk}


def native_files(root, selected):
    manifest = common.read_json(root / 'native/examples-build.json')
    if (manifest.get('schema_version') != 2 or
            any(manifest.get(k) != selected[k] for k in ('abi', 'api', 'sdk_image_id'))):
        raise ValueError('Native generation ABI/API/SDK/runtime differs from the selected artifacts')
    clients = manifest.get('clients', [])
    if (len(clients) != len(PROFILES) or {item['profile'] for item in clients} != set(PROFILES)):
        raise ValueError('Expected all twelve Qt4 JNI clients')
    files = {'native/examples-build.json': common.digest(root / 'native/examples-build.json')}
    for item in clients:
        name = item['profile']
        relative = f'native/{name}.so'
        if item['native'] != name + '.so' or common.digest(root / relative) != item['sha256']:
            raise ValueError('Native artifact differs from example build: ' + name)
        files[relative] = item['sha256']
    relative = 'native/libc++_shared.so'
    files[relative] = common.digest(root / relative)
    if files[relative] != manifest.get('runtime_sha256'):
        raise ValueError('Native generation runtime differs from example build')
    reports = root / 'sdk-reports'
    if not reports.is_dir() or not any(path.is_file() for path in reports.rglob('*')):
        raise ValueError('Missing Qt4 SDK producer reports')
    snapshot = common._reports.verify_export(reports, 4, selected['abi'], selected['sdk_image_id'])
    files.update({'sdk-reports/' + name: sha for name, sha in snapshot.items()})
    producer_runtime = (reports / 'runtime-sha256.txt').read_text().split()[0]
    if files[relative] != producer_runtime:
        raise ValueError('Native runtime differs from the SDK producer report')
    return files


def begin(root, abi, sdk):
    pending = dict(identity(root, abi, sdk), schema_version=3, generation=uuid.uuid4().hex)
    common.create_json(root / 'examples-in-progress.json', pending)
    common.invalidate_results(root)
    for name in ('examples-manifest.json', 'apk-manifest.json', 'apk-packages.json'):
        (root / name).unlink(missing_ok=True)
    return pending


def finish(root, abi, sdk):
    pending = common.read_json(root / 'examples-in-progress.json')
    selected = identity(root, abi, sdk)
    if any(pending.get(k) != v for k, v in selected.items()):
        raise ValueError('Qt4 example generation does not match the selected SDK/ABI')
    pending['files'] = native_files(root, selected)
    for name in ('sdk-image-id.txt', 'examples-sdk-image-id.txt'):
        common.write_text_atomic(root / name, sdk + '\n')
    common.write_json(root / 'examples-manifest.json', pending)
    (root / 'examples-in-progress.json').unlink()
    return pending


def check_examples(root, abi):
    if (root / 'examples-in-progress.json').exists():
        raise ValueError('Qt4 example generation is incomplete; recover it before packaging/testing')
    manifest = common.read_json(root / 'examples-manifest.json')
    selected = identity(root, abi)
    if (manifest.get('schema_version') != 3 or any(manifest.get(k) != v for k, v in selected.items()) or
            (root / 'examples-sdk-image-id.txt').read_text().strip() != selected['sdk_image_id']):
        raise ValueError('SDK/example identities differ from the completed Qt4 generation')
    if manifest['files'] != native_files(root, selected):
        raise ValueError('Qt4 native generation or producer reports changed after completion')
    return manifest


def signing_inputs(root):
    return {'local-probe.jks': common.digest(root / 'local-probe.jks')}


def begin_apks(root, abi, android_sdk, javac=None):
    examples = check_examples(root, abi)
    state = {'generation': examples['generation'],
             'examples_manifest_sha256': common.digest(root / 'examples-manifest.json'),
             'packaging_inputs': common.packaging_inputs(4, android_sdk, javac),
             'signing_inputs': signing_inputs(root)}
    common.create_json(root / 'apk-in-progress.json', state)
    common.invalidate_results(root)
    for name in ('apk-manifest.json', 'apk-packages.json'):
        (root / name).unlink(missing_ok=True)
    return state


def package_records(root, examples):
    records = []
    for profile in PROFILES:
        apk = profile + '.apk'
        sha = common.apk_digest(root, apk)
        with zipfile.ZipFile(root / apk) as archive:
            members = archive.namelist()
            actual = [name for name in members if name.startswith('lib/') and name.endswith('.so')]
            expected = {f'lib/{examples["abi"]}/libdonut_probe.so': f'native/{profile}.so',
                        f'lib/{examples["abi"]}/libc++_shared.so': 'native/libc++_shared.so'}
            if len(actual) != len(expected) or set(actual) != set(expected):
                raise ValueError('Unexpected packaged Qt4 native libraries: ' + profile)
            for member, source in expected.items():
                data = archive.read(member)
                if hashlib.sha256(data).hexdigest() != examples['files'][source]:
                    raise ValueError('Packaged Qt4 native library differs from its completed generation: ' + profile)
                common.native_abi().inspect_bytes(data, examples['abi'], member)
        records.append({'profile': profile, 'apk': apk, 'sha256': sha,
                        'abi': examples['abi'], 'api': examples['api'], 'sdk_image_id': examples['sdk_image_id'],
                        'generation': examples['generation'],
                        'native_sha256': examples['files'][f'native/{profile}.so'],
                        'examples_manifest_sha256': common.digest(root / 'examples-manifest.json')})
    return records


def record_apks(root, abi, android_sdk, javac=None):
    examples = check_examples(root, abi)
    pending = common.read_json(root / 'apk-in-progress.json')
    if (pending['generation'] != examples['generation'] or
            pending['examples_manifest_sha256'] != common.digest(root / 'examples-manifest.json')):
        raise ValueError('Qt4 native generation changed during packaging')
    if pending['packaging_inputs'] != common.packaging_inputs(4, android_sdk, javac):
        raise ValueError('Qt4 Java/tool/packaging inputs changed during packaging')
    if pending['signing_inputs'] != signing_inputs(root):
        raise ValueError('Qt4 signing input changed during packaging')
    packages = package_records(root, examples)
    common.write_json(root / 'apk-packages.json', packages)
    result = dict(identity(root, abi), schema_version=3, **pending,
                  packages_sha256=common.digest(root / 'apk-packages.json'))
    common.write_json(root / 'apk-manifest.json', result)
    (root / 'apk-in-progress.json').unlink()
    return result


def check_apks(root, abi):
    examples = check_examples(root, abi)
    if (root / 'apk-in-progress.json').exists():
        raise ValueError('Qt4 APK generation is incomplete; recover it before testing')
    manifest = common.read_json(root / 'apk-manifest.json')
    if (manifest.get('schema_version') != 3 or any(manifest.get(k) != v for k, v in identity(root, abi).items()) or
            manifest['generation'] != examples['generation'] or
            manifest['examples_manifest_sha256'] != common.digest(root / 'examples-manifest.json')):
        raise ValueError('Qt4 APKs belong to another native generation')
    if manifest['packages_sha256'] != common.digest(root / 'apk-packages.json'):
        raise ValueError('Qt4 APK package manifest changed after packaging')
    packages = common.read_json(root / 'apk-packages.json')
    if packages != package_records(root, examples):
        raise ValueError('Qt4 APK bytes or native generation metadata changed after packaging')
    return packages


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('begin', 'finish', 'check-examples', 'begin-apks', 'record-apks', 'check-apks'))
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--abi', choices=('x86', 'x86_64', 'arm64-v8a'), required=True)
    parser.add_argument('--sdk-image-id')
    parser.add_argument('--android-sdk', type=Path)
    parser.add_argument('--javac', type=Path)
    parser.add_argument('--artifact-lease-held', action='store_true', help='internal: reuse the caller artifact lease')
    args = parser.parse_args(argv)
    root = args.root.resolve()
    root.mkdir(parents=True, exist_ok=True)
    with common.artifact_lease(root, args.artifact_lease_held):
        if args.command in ('begin', 'finish'):
            if not args.sdk_image_id:
                parser.error('Qt4 begin/finish require --sdk-image-id')
            globals()[args.command](root, args.abi, args.sdk_image_id)
        elif args.command in ('begin-apks', 'record-apks'):
            if not args.android_sdk:
                parser.error('Qt4 APK generation requires --android-sdk')
            globals()[args.command.replace('-', '_')](root, args.abi, args.android_sdk, args.javac)
        else:
            globals()[args.command.replace('-', '_')](root, args.abi)
    print(f'Qt4 Android artifact {args.command}: {args.abi} PASS')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError, zipfile.BadZipFile) as error:
        sys.exit(f'Qt4 Android artifact validation failed: {error}')
