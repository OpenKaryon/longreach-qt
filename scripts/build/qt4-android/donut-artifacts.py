# SPDX-License-Identifier: GPL-3.0-or-later
"""Provenance for the combined API4 recipe; not an installed Qt SDK receipt."""
import argparse
import hashlib
import importlib.util
from pathlib import Path
import re
import shutil
import sys
import uuid
import zipfile

_spec = importlib.util.spec_from_file_location('donut_common', Path(__file__).resolve().parents[1] / 'android-api21/artifact-manifest.py')
common = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(common)
PROFILES = ('bootstrap', 'strict', 'core', 'quick', 'selftest', 'graphics', 'network', 'painting')
ARCHIVES = {
    'downloads/qt-everywhere-opensource-src-4.8.7.tar.gz': 'e2882295097e47fe089f8ac741a95fef47e0a73a3f3cdf21b56990638f626ea0',
    'downloads/llvm-project-21.1.8.src.tar.xz': '4633a23617fa31a3ea51242586ea7fb1da7140e426bd62fc164261fe036aa142',
    'android-inputs/aosp-ndk-r7-api4-arm.tar.gz': '7049f4b170edc3415d48ff4fb36fe9b110ee7122f65051a727edb75600ad0057',
    'android-inputs/android-1.6_r03-linux.zip': 'a8c4e3b32269c6b04c2adeabd112fce42f292dab1a40ef3b08ea7d4212be0df4',
}
JAR_MEMBER = 'android-1.6_r03-linux/android.jar'
SOURCE_TREES = ('docker/qt4/android', 'scripts/build/qt4-android', 'scripts/build/android-api21', 'scripts/build/qt6-llvm-probes',
                'scripts/tests/qt6-llvm-probes', 'patches/android/donut', 'patches/qt4',
                'tests/android-donut', 'tests/common', 'tests/qt-selftest', 'tests/quick-qml-gallery',
                'tests/widgets-gallery', 'tests/graphics-gallery', 'tests/network-gui', 'tests/painting-lab')
SOURCE_FILES = ('scripts/build/qt4-android.ps1', 'scripts/build/apt-snapshot.sh', 'scripts/build/qt6-android/prepare-emulator.py')
NATIVE_PENDING = 'donut-native-in-progress.json'
NATIVE_MANIFEST = 'donut-native-manifest.json'
APK_PENDING = 'donut-apk-in-progress.json'
APK_MANIFEST = 'donut-apk-manifest.json'


def safe(path):
    # Python 3.11 lacks Path.is_junction; reject all Windows reparse entries too.
    if path.is_symlink() or getattr(path.lstat(), 'st_file_attributes', 0) & 0x400:
        raise ValueError('Linked API4 artifact/input: ' + str(path))
    return path


def inputs(repo, directory):
    source = {}
    for relative in (*SOURCE_TREES, *SOURCE_FILES):
        base = safe(repo / relative)
        paths = sorted(base.rglob('*')) if base.is_dir() else [base]
        for path in paths:
            if '__pycache__' in path.parts or path.suffix == '.pyc':
                continue
            safe(path)
            if path.is_file():
                source[path.relative_to(repo).as_posix()] = common.digest(path)
    if not source:
        raise ValueError('Missing API4 source inputs')
    archives = {}
    for label, expected in ARCHIVES.items():
        path = directory / label.split('/', 1)[1] if label.startswith('android-inputs/') else repo / label
        archives[label] = common.digest(safe(path))
        if archives[label] != expected:
            raise ValueError('Unpinned API4 archive: ' + label)
    with zipfile.ZipFile(directory / 'android-1.6_r03-linux.zip') as archive:
        jar = hashlib.sha256(archive.read(JAR_MEMBER)).hexdigest()
    return {'sources': source, 'archives': archives, 'android_jar_sha256': jar}


def validate_identity(value):
    if (value.get('schema_version') != 1 or value.get('qt_major') != 4 or value.get('api') != 4 or
            value.get('abi') != 'armeabi' or not re.fullmatch(r'[0-9a-f]{32}', value.get('generation', ''))):
        raise ValueError('Invalid API4 native generation identity')


def validate_inputs(value):
    source = value.get('sources', {})
    if (value.get('archives') != ARCHIVES or not source or
            any(not re.fullmatch(r'[0-9a-f]{64}', sha) for sha in source.values()) or
            not re.fullmatch(r'[0-9a-f]{64}', value.get('android_jar_sha256', ''))):
        raise ValueError('Incomplete API4 recipe/archive provenance')


def begin(root, repo, directory):
    if (root / APK_PENDING).exists():
        raise ValueError('Recover the incomplete API4 APK generation explicitly')
    pending = dict(schema_version=1, qt_major=4, api=4, abi='armeabi', generation=uuid.uuid4().hex,
                   inputs=inputs(repo, directory))
    common.create_json(root / NATIVE_PENDING, pending)
    common.invalidate_results(root)
    # Keep previous completed receipts until promotion; the pending marker blocks consumption.
    return pending


def native_snapshot(directory):
    safe(directory)
    if {p.name for p in directory.glob('*.so')} != {p + '.so' for p in PROFILES}:
        raise ValueError('Expected exactly eight API4 native clients')
    result = {}
    for name in [p + suffix for p in PROFILES for suffix in ('.so', '-elf.txt')] + ['libQtCore.a']:
        path = safe(directory / name)
        if not path.is_file() or not path.stat().st_size:
            raise ValueError('Missing API4 native output: ' + name)
        if name.endswith('.so'):
            common.native_abi().inspect(path, 'armeabi')
        result['native/' + name] = common.digest(path)
    return result


def finish_native(root, repo, directory, stage, image):
    pending = common.read_json(root / NATIVE_PENDING)
    validate_identity(pending)
    if pending['inputs'] != inputs(repo, directory):
        raise ValueError('API4 recipe/archive inputs changed during the native build')
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', image or ''):
        raise ValueError('Missing immutable API4 tool image identity')
    safe(stage)
    if stage.resolve().parent != root.resolve() or not re.fullmatch(r'native-build-[0-9a-f]{32}', stage.name):
        raise ValueError('API4 native staging must be a fresh direct child of the artifact root')
    files = native_snapshot(stage)
    native = root / 'native'
    if native.exists():
        safe(native)
        history_root = root / 'native-history'
        history_root.mkdir(exist_ok=True)
        safe(history_root)
        history = history_root / uuid.uuid4().hex
        history.mkdir()
        # Both resolved move endpoints are inside this artifact root. Preserve old data.
        if native.resolve().parent != root.resolve() or history.resolve().parent != history_root.resolve():
            raise ValueError('Unexpected API4 native history path')
        native.rename(history / 'native')
        for name in (NATIVE_MANIFEST, APK_MANIFEST):
            if (root / name).is_file():
                shutil.copyfile(safe(root / name), history / name)
    stage.rename(native)
    result = dict(pending, tool_image_id=image, files=files)
    common.write_json(root / NATIVE_MANIFEST, result)
    (root / APK_MANIFEST).unlink(missing_ok=True)
    (root / NATIVE_PENDING).unlink()
    return result


def check_native(root):
    if (root / NATIVE_PENDING).exists():
        raise ValueError('API4 native generation is incomplete; recover it explicitly')
    receipt = common.read_json(root / NATIVE_MANIFEST)
    validate_identity(receipt)
    validate_inputs(receipt.get('inputs', {}))
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', receipt.get('tool_image_id', '')):
        raise ValueError('Invalid API4 tool image identity')
    if receipt['files'] != native_snapshot(root / 'native'):
        raise ValueError('API4 native files/reports changed after completion')
    return receipt


def packaging_inputs(native, sdk, jar, javac):
    if common.digest(jar) != native['inputs']['android_jar_sha256']:
        raise ValueError('API4 android.jar differs from its pinned input archive')
    sources = [common.REPO / 'scripts/build/qt4-android' / name
               for name in ('package.ps1', 'host.ps1', 'donut-artifacts.py')]
    sources += [common.REPO / 'scripts/build/android-api21' / name
                for name in ('packaging-host.ps1', 'host-tools.py', 'artifact-manifest.py', 'native-abi.py')]
    sources += sorted(p for p in (common.REPO / 'tests/android-donut/java').rglob('*') if p.is_file())
    return {'host': common._host_tools.snapshot(sdk, javac, android_jar=jar),
            'sources': {p.relative_to(common.REPO).as_posix(): common.digest(safe(p)) for p in sources}}


def signing(root):
    return {'local-probe.jks': common.digest(safe(root / 'local-probe.jks'))}


def begin_apks(root, sdk, jar, javac):
    native = check_native(root)
    pending = dict(generation=native['generation'], native_manifest_sha256=common.digest(root / NATIVE_MANIFEST),
                   packaging_inputs=packaging_inputs(native, sdk, jar, javac), signing_inputs=signing(root))
    common.create_json(root / APK_PENDING, pending)
    common.invalidate_results(root)
    return pending


def packages(root, native):
    records = []
    for profile in PROFILES:
        path = root / (profile + '.apk')
        sha = common.apk_digest(root, path.name)
        with zipfile.ZipFile(path) as archive:
            names = archive.namelist()
            if len(names) != len(set(names)):
                raise ValueError('Duplicate API4 APK member: ' + profile)
            member = 'lib/armeabi/libdonut_probe.so'
            actual = [p for p in names if p.startswith('lib/') and p.endswith('.so')]
            if actual != [member] or not {'classes.dex', 'AndroidManifest.xml'}.issubset(names):
                raise ValueError('Unexpected API4 APK members: ' + profile)
            data = archive.read(member)
            if hashlib.sha256(data).hexdigest() != native['files'][f'native/{profile}.so']:
                raise ValueError('API4 APK JNI differs from native generation: ' + profile)
            common.native_abi().inspect_bytes(data, 'armeabi', member)
        badging = root / (path.name + '.badging.txt')
        text = badging.read_text(encoding='utf-8-sig')
        if re.findall(r"^sdkVersion:'([^']*)'\s*$", text, re.M) != ['4'] or re.findall(r"^native-code: (.+?)\s*$", text, re.M) != ["'armeabi'"]:
            raise ValueError('API4 APK badging API/ABI mismatch: ' + profile)
        records.append(dict(profile=profile, apk=path.name, sha256=sha, badging_sha256=common.digest(badging),
                            native_sha256=native['files'][f'native/{profile}.so']))
    return records


def record_apks(root, sdk, jar, javac):
    native = check_native(root)
    pending = common.read_json(root / APK_PENDING)
    if pending['generation'] != native['generation'] or pending['native_manifest_sha256'] != common.digest(root / NATIVE_MANIFEST):
        raise ValueError('API4 native generation changed during packaging')
    if pending['packaging_inputs'] != packaging_inputs(native, sdk, jar, javac) or pending['signing_inputs'] != signing(root):
        raise ValueError('API4 packaging or signing input changed during packaging')
    result = dict(pending, schema_version=1, qt_major=4, api=4, abi='armeabi', packages=packages(root, native))
    common.write_json(root / APK_MANIFEST, result)
    (root / APK_PENDING).unlink()
    return result


def check_apks(root):
    native = check_native(root)
    if (root / APK_PENDING).exists():
        raise ValueError('API4 APK generation is incomplete; recover it explicitly')
    receipt = common.read_json(root / APK_MANIFEST)
    validate_identity(receipt)
    if receipt['generation'] != native['generation'] or receipt['native_manifest_sha256'] != common.digest(root / NATIVE_MANIFEST):
        raise ValueError('API4 APKs belong to another native generation')
    packaging = receipt.get('packaging_inputs', {})
    host = packaging.get('host', {})
    tools = host.get('tool_sha256', {})
    sources = packaging.get('sources', {})
    keys = receipt.get('signing_inputs', {})
    if (host.get('schema_version') != 2 or not tools or not sources or
            tools.get('android-platform/android.jar') != native['inputs']['android_jar_sha256'] or
            set(keys) != {'local-probe.jks'} or
            any(not re.fullmatch(r'[0-9a-f]{64}', sha) for sha in (*tools.values(), *sources.values(), *keys.values()))):
        raise ValueError('Incomplete API4 packaging/tool/signing provenance')
    if receipt['packages'] != packages(root, native):
        raise ValueError('API4 packaged files changed after completion')
    return receipt


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('begin', 'finish-native', 'check-native', 'begin-apks', 'record-apks', 'check-apks'))
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument('--input-directory', type=Path)
    parser.add_argument('--native-directory', type=Path)
    parser.add_argument('--tool-image-id')
    parser.add_argument('--android-sdk', type=Path)
    parser.add_argument('--android-jar', type=Path)
    parser.add_argument('--javac', type=Path)
    parser.add_argument('--artifact-lease-held', action='store_true', help='internal: caller owns the artifact lease')
    args = parser.parse_args(argv)
    root = args.root.resolve()
    root.mkdir(parents=True, exist_ok=True)
    with common.artifact_lease(root, args.artifact_lease_held):
        if args.command in ('begin', 'finish-native'):
            if not args.input_directory or (args.command == 'finish-native' and not args.native_directory):
                parser.error('API4 native phases require --input-directory and finish requires --native-directory')
            if args.command == 'begin':
                begin(root, args.repo, args.input_directory)
            else:
                finish_native(root, args.repo, args.input_directory, args.native_directory, args.tool_image_id)
        elif args.command in ('begin-apks', 'record-apks'):
            if not args.android_sdk or not args.android_jar or not args.javac:
                parser.error('API4 APK phases require --android-sdk, --android-jar and --javac')
            globals()[args.command.replace('-', '_')](root, args.android_sdk, args.android_jar, args.javac)
        else:
            globals()[args.command.replace('-', '_')](root)
    print('API4 artifact ' + args.command + ': PASS')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError, zipfile.BadZipFile) as error:
        sys.exit('API4 artifact validation failed: ' + str(error))
