# SPDX-License-Identifier: GPL-3.0-or-later
"""Verify API4 resident-JNI diagnostic attempts; no guest process-exit claim."""
import argparse
import importlib.util
from pathlib import Path
import re
import sys
import zipfile


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


REPO = Path(__file__).resolve().parents[3]
artifacts = load('api4_run_artifacts', REPO / 'scripts/build/qt4-android/donut-artifacts.py')
prepared = load('api4_run_media', REPO / 'scripts/build/qt4-android/prepare-media.py')
common = artifacts.common
owned = load('api4_run_owned', Path(__file__).with_name('android-owned-process.py'))
baselines = load('api4_run_baselines', Path(__file__).with_name('android-baselines.py'))
modern = load('api4_run_modern', REPO / 'scripts/tests/require-modern-cpp.py')
atomic = load('api4_run_atomic', REPO / 'scripts/tests/android/require-armv5-atomic.py')
REPORTS = {'selftest': 'qt-selftest', 'graphics': 'graphics', 'network': 'network-gui', 'painting': 'painting-lab'}
QUICK = ('qrc and first frame', 'Android tap updates QML and frame',
         'Android pause and resume preserve input and rendering',
         'shared Qt Quick Gallery renders and navigates',
         'shared Widgets Gallery toggles a checkbox and changes tabs')
FATAL = re.compile(r'FATAL EXCEPTION|Fatal signal|exiting due to signal|terminated by signal|VM aborting|\*\*\*\s+\*\*\*\s+\*\*\*|>>>\s*org\.longreachqt\.donut(?:\.quick)?\s*<<<')


def arguments(root, run):
    base = root / 'inputs/android-1.6_r03-linux/images'
    return ['-sysdir', str(base), '-datadir', str(run), '-system', str(base / 'system.img'),
            '-kernel', str(base / 'kernel-qemu'), '-ramdisk', str(base / 'ramdisk.img'),
            '-data', str(run / 'userdata-qemu.img'), '-initdata', str(base / 'userdata.img'),
            '-no-window', '-no-audio', '-no-snapshot', '-no-snapstorage', '-no-skin', '-skin', '320x480',
            '-memory', '128', '-gpu', 'off', '-port', '5580', '-no-boot-anim', '-verbose']


def media(root):
    try:
        return prepared.verify(root / 'inputs')
    except (OSError, ValueError) as error:
        raise ValueError('API4 emulator/media changed or is unprepared: ' + str(error)) from error


def selected(root, run):
    record = common.read_json(run / 'run-inputs.json')
    if (record.get('schema_version') != 1 or record.get('qt_major') != 4 or record.get('api') != 4 or
            record.get('abi') != 'armeabi' or record.get('profile') not in artifacts.PROFILES or
            not re.fullmatch(r'[0-9a-f]{32}', record.get('run_id', '')) or
            run.name != record['profile'] + '-' + record['run_id'] or run.parent != root / 'run' or
            record.get('qualification') is not False or record.get('evidence_scope') != 'api4-jni-resident-diagnostic'):
        raise ValueError('Invalid API4 diagnostic attempt identity')
    receipt = artifacts.check_apks(root)
    if (record.get('generation') != receipt['generation'] or
            record.get('native_manifest_sha256') != common.digest(root / artifacts.NATIVE_MANIFEST) or
            record.get('apk_manifest_sha256') != common.digest(root / artifacts.APK_MANIFEST)):
        raise ValueError('API4 attempt belongs to a changed native/APK generation')
    package = next(item for item in receipt['packages'] if item['profile'] == record['profile'])
    if (record.get('apk') != package['apk'] or record.get('native_sha256') != package['native_sha256'] or
            record.get('apk_sha256') != package['sha256']):
        raise ValueError('API4 attempt APK/JNI differs from its generation')
    return record


def launch(root, run):
    value = common.read_json(run / 'emulator-launch.json')
    program = root / 'inputs/tools/emulator-arm.exe'
    if (value.get('schema_version') != 1 or value.get('abi') != 'armeabi' or
            Path(value.get('emulator', '')).resolve() != program.resolve() or value.get('arguments') != arguments(root, run)):
        raise ValueError('API4 emulator invocation differs from its diagnostic policy')
    return value


def capture(root, run):
    selected(root, run)
    launch(root, run)
    snapshot = media(root)
    native = artifacts.check_native(root)
    if snapshot['files']['inputs/android-1.6_r03-linux/android.jar'] != native['inputs']['android_jar_sha256']:
        raise ValueError('API4 run platform JAR differs from the pinned native input')
    common.write_json(run / 'emulator-media.json', snapshot)


def report_files(record):
    profile = record['profile']
    names = ['case-logcat.log']
    if profile in REPORTS:
        names.append(REPORTS[profile] + '-guest.stdout')
    elif profile == 'strict':
        names.append('strict-cxx23-guest.stdout')
    elif profile == 'quick':
        names.extend(('instrumentation.log', 'quick-smoke-guest.txt'))
    return names


def check_outputs(run, record):
    expected = record.get('case_outputs', {})
    names = report_files(record)
    if set(expected) != set(names) or any(expected[name] != common.digest(run / name) for name in names):
        raise ValueError('API4 case output changed after execution')
    logs = (run / 'case-logcat.log').read_text(encoding='utf-8-sig') + '\n' + (run / 'final-logcat.log').read_text(encoding='utf-8-sig')
    if FATAL.search(logs):
        raise ValueError('Fatal API4 application cleanup error')
    profile = record['profile']
    if profile == 'quick':
        instrumentation = (run / 'instrumentation.log').read_text(encoding='utf-8-sig')
        if re.findall(r'^INSTRUMENTATION_CODE: (-?\d+)\s*$', instrumentation, re.M) != ['-1']:
            raise ValueError('API4 instrumentation did not complete successfully')
        outcomes = re.findall(r'^(PASS|FAIL|SKIP): (.+?)\s*$', (run / 'quick-smoke-guest.txt').read_text(encoding='utf-8-sig'), re.M)
        if any(status == 'FAIL' for status, _ in outcomes) or any([item for item in outcomes if item[1] == name] != [('PASS', name)] for name in QUICK):
            raise ValueError('API4 Quick required behavior did not pass exactly once')
    else:
        case_log = (run / 'case-logcat.log').read_text(encoding='utf-8-sig')
        code = '42' if profile == 'bootstrap' else '0'
        if re.findall(r'LongreachDonut.*Native probe returned (-?\d+)\s*$', case_log, re.M) != [code]:
            raise ValueError('API4 native return marker is missing or ambiguous')
        if profile == 'core' and 'QtCore 4.8.7 PASS' not in case_log:
            raise ValueError('API4 QtCore result is missing')
        if profile in REPORTS:
            text = (run / (REPORTS[profile] + '-guest.stdout')).read_text(encoding='utf-8-sig')
            baselines.require(4, 4, 'armeabi', profile, text)
            if re.search(r'^FAIL: ', text, re.M):
                raise ValueError('API4 suite contains a failed named check')
        elif profile == 'strict':
            if 'Classic locale check passed' not in case_log:
                raise ValueError('API4 classic locale result is missing')
            modern.require_modern_cpp((run / 'strict-cxx23-guest.stdout').read_text(encoding='utf-8-sig'))
            if 'installed_sdk' in artifacts.check_native(run.parent.parent):
                atomic.validate((run / 'strict-cxx23-guest.stdout').read_text(encoding='utf-8-sig'))


def verify(root, run, completing=False):
    record = selected(root, run)
    value = launch(root, run)
    if (record.get('emulator_launch_sha256') != common.digest(run / 'emulator-launch.json') or
            record.get('emulator_media_sha256') != common.digest(run / 'emulator-media.json') or
            common.read_json(run / 'emulator-media.json') != media(root)):
        raise ValueError('API4 emulator/media changed during the attempt')
    owned.validate_emulator(run, launch=value, bindings=record, artifact_root=root)
    check_outputs(run, record)
    final_hash = common.digest(run / 'final-logcat.log')
    capture_path = run / 'final-logcat-capture.json'
    capture_proof = common.read_json(capture_path)
    if (capture_proof.get('schema_version') != 1 or capture_proof.get('captured') is not True or
            capture_proof.get('serial') != 'emulator-5580' or capture_proof.get('logcat_sha256') != final_hash or
            any(capture_proof.get(key) != record[key] for key in ('host_process_owner_sha256', 'host_process_request_sha256'))):
        raise ValueError('API4 final log capture is missing or mismatched')
    if completing:
        record.update(completed=True, host_tree_exit_verified=True, final_logcat_sha256=final_hash,
                      final_logcat_capture_sha256=common.digest(capture_path))
        common.write_json(run / 'run-inputs.json', record)
    elif record.get('completed') is not True or record.get('host_tree_exit_verified') is not True or record.get('final_logcat_sha256') != final_hash or record.get('final_logcat_capture_sha256') != common.digest(capture_path):
        raise ValueError('API4 attempt has no unchanged completed diagnostic evidence')
    return record


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('capture', 'complete', 'verify'))
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--run', type=Path, required=True)
    parser.add_argument('--artifact-lease-held', action='store_true', help='internal: caller owns the artifact lease')
    args = parser.parse_args(argv)
    root, run = args.root.resolve(), args.run.resolve()
    with common.artifact_lease(root, args.artifact_lease_held):
        if args.action == 'capture':
            capture(root, run)
        else:
            verify(root, run, args.action == 'complete')
    print('API4 diagnostic ' + args.action + ': PASS (no full-suite qualification)')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError, zipfile.BadZipFile) as error:
        sys.exit('API4 diagnostic validation failed: ' + str(error))
