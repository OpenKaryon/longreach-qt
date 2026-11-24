# SPDX-License-Identifier: GPL-3.0-or-later
"""Record exactly twenty separate Qt5 API10 sound diagnostics; never a full-suite qualification."""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import stat
import sys
import uuid

REPO = Path(__file__).resolve().parents[3]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


legacy = module('sound_series_legacy', REPO / 'scripts/build/qt5-android/collect-legacy-results.py')
protocol = module('sound_series_protocol', REPO / 'scripts/tests/android/require-android-sound-cache.py')
COUNT = 20
PACKAGE = 'org.longreachqt.examples.qtselftest'
APK = 'apk/extended/qt-selftest.apk'
TOOLS = (
    'scripts/run/qt5-android-sound-cache.ps1', 'scripts/run/android/android-sound-cache-series.py',
    'scripts/run/qt5-android-gingerbread.ps1', 'scripts/run/android/android-case-state.ps1',
    'scripts/run/android/android-process-exit.py', 'scripts/run/android/android-process-exit.ps1',
    'scripts/run/android/android-owned-process.py', 'scripts/run/android/android-owned-process.ps1',
    'scripts/run/android/android-cpu.py', 'scripts/run/android/android-adb-endpoint.py',
    'scripts/run/android/android-adb-endpoint.ps1', 'scripts/tests/android/require-android-sound-cache.py',
    'scripts/build/android-api21/artifact-manifest.py',
    'scripts/build/android-api21/sdk-reports.py', 'scripts/build/android-api21/native-abi.py',
    'scripts/build/qt5-android/collect-legacy-results.py',
)


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def read(path):
    data = Path(path).read_bytes()
    return json.loads(data.decode('utf-8-sig')), hashlib.sha256(data).hexdigest()


def create(path, value):
    with Path(path).open('x', encoding='utf-8', newline='\n') as stream:
        json.dump(value, stream, sort_keys=True, indent=2)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())


def ordinary(path, directory=False):
    path = Path(path)
    info = path.lstat()
    if stat.S_ISLNK(info.st_mode) or getattr(info, 'st_file_attributes', 0) & getattr(stat, 'FILE_ATTRIBUTE_REPARSE_POINT', 0x400):
        raise ValueError('Linked series input/output is not supported: ' + str(path))
    if not (stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode)):
        raise ValueError('Expected an ordinary series file/directory: ' + str(path))
    return path.resolve()


def layout(root, directory):
    root = ordinary(root, directory=True)
    directory = Path(directory).absolute()
    if directory.parent != root / 'diagnostics' or not re.fullmatch(r'[a-z0-9][a-z0-9-]{0,63}', directory.name):
        raise ValueError('Series must be a named child of artifact-root/diagnostics')
    if directory.parent.exists():
        ordinary(directory.parent, directory=True)
    if directory.exists():
        ordinary(directory, directory=True)
    return root, directory


def endpoint(port):
    value = {'schema_version': 1, 'host': 'localhost', 'port': port, 'socket': f'tcp:localhost:{port}'}
    legacy.owned.endpoint.validate(value)
    return value


def full_generation(root, abi):
    legacy.artifacts.check_examples(root, 5, abi)
    return legacy.artifacts.check_apks(root, 5, abi)


def file_hashes(paths, optional):
    result = {}
    for name, value in paths.items():
        path = Path(value)
        if not path.exists() and name in optional:
            result[name] = None
        else:
            ordinary(path)
            result[name] = digest(path)
    return result


def begin(root, directory, abi, emulator, system_directory, kernel, ramdisk, android_sdk, classic, adb_port):
    root, directory = layout(root, directory)
    if directory.exists():
        raise ValueError('Series directory already exists; preserve it and choose a new run name')
    apks = full_generation(root, abi)
    system = ordinary(system_directory, directory=True)
    sdk = ordinary(android_sdk, directory=True)
    paths = {
        'apk': str(root / APK), 'apk_manifest': str(root / 'apk-manifest.json'),
        'examples_manifest': str(root / 'examples-manifest.json'),
        'sdk_image_id': str(root / 'sdk-image-id.txt'),
        'emulator': str(ordinary(emulator)), 'kernel': str(ordinary(kernel)),
        'ramdisk': str(ordinary(ramdisk)), 'system': str(system / 'system.img'),
        'userdata': str(system / 'userdata.img'), 'adb': str(sdk / 'platform-tools/adb.exe'),
        'adb_api_dll': str(sdk / 'platform-tools/AdbWinApi.dll'),
        'adb_usb_dll': str(sdk / 'platform-tools/AdbWinUsbApi.dll'),
    }
    paths.update({'tool:' + name: str(REPO / name) for name in TOOLS})
    optional = ['adb_api_dll', 'adb_usb_dll']
    hashes = file_hashes(paths, optional)
    if hashes['apk'] != apks['files'][APK]:
        raise ValueError('Selected sound APK is outside its packaged generation')
    value = {
        'schema_version': 1, 'series_id': uuid.uuid4().hex, 'qualification': False,
        'scope': 'qt5-api10-sound-cache-twenty-processes', 'required_processes': COUNT,
        'root': str(root), 'directory': str(directory), 'qt_major': 5, 'api': 10, 'abi': abi,
        'sdk_image_id': apks['sdk_image_id'], 'generation': apks['generation'],
        'apk_relative': APK, 'system_directory': str(system), 'android_sdk': str(sdk),
        'classic_emulator': bool(classic), 'adb_endpoint': endpoint(adb_port),
        'paths': paths, 'optional_files': optional, 'file_sha256': hashes,
        'created_utc': datetime.now(timezone.utc).isoformat(),
    }
    # No case or protected SDK/media input may sit below this output directory.
    for path in paths.values():
        if Path(path).resolve().is_relative_to(directory):
            raise ValueError('Series output contains a protected input')
    directory.parent.mkdir(exist_ok=True)
    directory.mkdir()
    create(directory / 'series-inputs.json', value)
    create(directory / 'series.pending.json', {'schema_version': 1, 'series_id': value['series_id'],
           'inputs_sha256': digest(directory / 'series-inputs.json'), 'required_processes': COUNT})
    return value


def inputs(directory, full=False, pending=True):
    value, sha = read(Path(directory) / 'series-inputs.json')
    root, directory = layout(Path(value['root']), directory)
    if (value.get('schema_version') != 1 or value.get('scope') != 'qt5-api10-sound-cache-twenty-processes'
            or value.get('qualification') is not False or value.get('required_processes') != COUNT
            or value.get('qt_major') != 5 or value.get('api') != 10 or value.get('abi') not in ('x86', 'armeabi-v7a')
            or value.get('directory') != str(directory) or value.get('apk_relative') != APK
            or not re.fullmatch(r'[0-9a-f]{32}', value.get('series_id', ''))):
        raise ValueError('Invalid sound series input receipt')
    legacy.owned.endpoint.validate(value['adb_endpoint'])
    if file_hashes(value['paths'], value['optional_files']) != value['file_sha256']:
        raise ValueError('Sound series inputs changed')
    if any((root / name).exists() for name in ('examples-in-progress.json', 'apk-in-progress.json')):
        raise ValueError('Sound series generation became incomplete')
    if (directory / 'series-failure.json').exists():
        raise ValueError('Sound series contains a failed attempt; do not resume it')
    if pending:
        marker, _ = read(directory / 'series.pending.json')
        if marker != {'schema_version': 1, 'series_id': value['series_id'], 'inputs_sha256': sha,
                      'required_processes': COUNT}:
            raise ValueError('Series pending receipt differs from its inputs')
    if full:
        apks = full_generation(root, value['abi'])
        if apks['generation'] != value['generation'] or apks['sdk_image_id'] != value['sdk_image_id']:
            raise ValueError('Sound series belongs to another packaged generation')
    return value, sha


def emulator_arguments(value, case):
    paths, system = value['paths'], value['system_directory']
    result = ['-sysdir', system, '-datadir', str(case), '-system', system + '/system.img',
              '-kernel', paths['kernel'], '-ramdisk', paths['ramdisk'],
              '-data', str(case / 'userdata-qemu.img'), '-initdata', system + '/userdata.img',
              '-no-window', '-no-audio', '-no-snapshot', '-no-snapstorage', '-skin', '480x320',
              '-partition-size', '512', '-memory', '256', '-gpu', 'off', '-port', '5580',
              '-no-boot-anim', '-verbose', '-show-kernel']
    if value['abi'] == 'x86':
        result += (['-qemu', '-disable-hax', '-cpu', 'qemu32'] if value['classic_emulator']
                   else ['-no-accel', '-qemu', '-cpu', 'core2duo'])
    else:
        result += ['-qemu', '-cpu', 'cortex-a8']
    return result


def launch_arguments():
    return ['-s', 'emulator-5580', 'shell', 'am', 'start', '-n',
            PACKAGE + '/org.longreachqt.examples.SmokeActivity', '--es', 'applicationArguments',
            '--sound-cache-teardown', '--es', 'qtRasterImageDepth', '32', '--es', 'qtQuickBackend', 'software']


def validate_case(value, inputs_sha, index):
    case = ordinary(Path(value['directory']) / f'run-{index:02}', directory=True)
    if list(case.glob('attempt-*.pending.json')):
        raise ValueError('Sound case retains an incomplete attempt')
    receipt, receipt_sha = read(case / 'input-receipt.json')
    expected = {'schema_version': 3, 'completed': True, 'qualification': False, 'scope': 'single-case',
                'diagnostic': 'qt5-sound-cache-teardown', 'api': 10, 'abi': value['abi'],
                'sdk_image_id': value['sdk_image_id'], 'apk_manifest_bound': True, 'apk_relative': APK,
                'apk_manifest_sha256': value['file_sha256']['apk_manifest'], 'apk_sha256': value['file_sha256']['apk'],
                'emulator_sha256': value['file_sha256']['emulator'], 'termination_policy': 'natural',
                'package': PACKAGE, 'emulator_exit_confirmed': True, 'adb_endpoint': value['adb_endpoint'],
                'launch_arguments': launch_arguments(), 'emulator_arguments': emulator_arguments(value, case)}
    if (any(type(receipt.get(k)) is not type(v) or receipt[k] != v for k, v in expected.items())
            or receipt.get('case') not in (None, '')
            or not re.fullmatch(r'[0-9a-f]{32}', receipt.get('case_attempt_id', ''))):
        raise ValueError('Sound case differs from the frozen diagnostic invocation')
    stdout = case / 'files/selftest.stdout'
    stdout_sha = digest(stdout)
    if (receipt.get('stdout_sha256') != stdout_sha or receipt.get('diagnostic_stdout_sha256') != stdout_sha
            or (case / 'files/selftest-result.txt').read_text().strip() != '0'):
        raise ValueError('Sound case stdout or native return changed')
    protocol.validate(stdout.read_text(encoding='utf-8-sig'))
    exit_proof = legacy.process_exit.require_exit(case, PACKAGE, receipt)
    final = case / 'final-logcat.log'
    if digest(final) != receipt.get('final_logcat_sha256'):
        raise ValueError('Final sound cleanup log changed')
    observed = legacy.process_exit.lifecycle(legacy.process_exit.scoped(
        final.read_text(encoding='utf-8-sig').splitlines(), receipt['log_marker']), PACKAGE)
    if observed != {k: exit_proof[k] for k in ('process_id', 'start_line', 'death_line')}:
        raise ValueError('Final sound cleanup lost the same process exit')
    host = legacy.owned.validate_emulator(case, bindings=receipt, program_sha256=value['file_sha256']['emulator'],
                                         arguments=expected['emulator_arguments'], artifact_root=Path(value['root']))
    request, _ = legacy.owned.request(case)
    owner, _ = legacy.owned.read(case / 'host-process-owner.json')
    if (Path(request['program']).resolve() != Path(value['paths']['emulator']).resolve()
            or Path(request['cwd']).resolve() != case or request['adb_endpoint'] != value['adb_endpoint']):
        raise ValueError('Sound case used another frontend, directory or ADB endpoint')
    power = case / 'power-before.txt'
    if (digest(power) != receipt.get('guest_power_sha256')
            or not re.search(r'\bmStayOn(?:Conditions|Setting)=(?:3|7)\b', power.read_text(encoding='utf-8-sig'))):
        raise ValueError('Sound case has no verified guest power policy')
    cpu = legacy.cpu.validate(case, value['abi'], receipt)
    guest = (case / 'guest.txt').read_text(encoding='utf-8-sig').splitlines()
    for key, val in (('ro.build.version.sdk', '10'), ('ro.product.cpu.abi', value['abi']),
                     ('ro.build.version.release', '2.3.7' if value['abi'] == 'x86' else '2.3.3')):
        if key + '=' + val not in guest:
            raise ValueError('Sound case ran on another guest: ' + key)
    return dict(host, schema_version=1, index=index, case_relative=case.name, series_id=value['series_id'],
                inputs_sha256=inputs_sha, input_receipt_sha256=receipt_sha, case_attempt_id=receipt['case_attempt_id'],
                stdout_sha256=stdout_sha, process_exit_proof_sha256=receipt['process_exit_proof_sha256'],
                final_logcat_sha256=receipt['final_logcat_sha256'], guest_power_sha256=receipt['guest_power_sha256'],
                guest_cpuinfo_sha256=cpu['guest_cpuinfo_sha256'], guest_cpu_baseline_sha256=cpu['guest_cpu_baseline_sha256'],
                process_id=exit_proof['process_id'], log_marker=receipt['log_marker'], host_run_id=request['run_id'],
                supervisor_birth=[owner['supervisor_pid'], owner['supervisor_creation_filetime']],
                frontend_birth=[owner['frontend_pid'], owner['frontend_creation_filetime']], qualification=False)


def accepted(directory, value, sha, count):
    records = []
    expected_files = {f'accepted-{i:02}.json' for i in range(1, count + 1)}
    if {p.name for p in directory.glob('accepted-*.json')} != expected_files:
        raise ValueError('Sound series accepted attempts are missing, unordered or unexpected')
    for index in range(1, count + 1):
        record = validate_case(value, sha, index)
        if read(directory / f'accepted-{index:02}.json')[0] != record:
            raise ValueError('Previously accepted sound attempt changed')
        records.append(record)
    unique(records)
    return records


def unique(records):
    for key in ('case_attempt_id', 'log_marker', 'host_run_id', 'supervisor_birth', 'frontend_birth'):
        values = [json.dumps(r[key], sort_keys=True) for r in records]
        if len(values) != len(set(values)):
            raise ValueError('Sound series reused a process/attempt identity: ' + key)


def checkpoint(directory, index):
    if not 1 <= index <= COUNT:
        raise ValueError('Sound series index is outside 1..20')
    value, sha = inputs(directory)
    accepted(directory, value, sha, index - 1)
    if (directory / f'run-{index:02}').exists():
        raise ValueError('Sound case directory already exists; do not retry this series')


def record(directory, index):
    if not 1 <= index <= COUNT:
        raise ValueError('Sound series index is outside 1..20')
    value, sha = inputs(directory)
    records = accepted(directory, value, sha, index - 1)
    current = validate_case(value, sha, index)
    unique(records + [current])
    create(directory / f'accepted-{index:02}.json', current)


def result(directory, full, pending):
    value, sha = inputs(directory, full=full, pending=pending)
    records = accepted(directory, value, sha, COUNT)
    if {p.name for p in directory.glob('run-*')} != {f'run-{i:02}' for i in range(1, COUNT + 1)}:
        raise ValueError('Sound series has an unexpected or failed extra case directory')
    return {'schema_version': 1, 'series_id': value['series_id'], 'inputs_sha256': sha,
            'scope': value['scope'], 'qualification': False, 'required_processes': COUNT,
            'completed_processes': COUNT, 'completed': True, 'all_observed_exits_clean': True,
            'sdk_image_id': value['sdk_image_id'], 'generation': value['generation'],
            'abi': value['abi'], 'api': 10, 'cases': records}


def finish(directory):
    report = result(directory, full=True, pending=True)
    if (directory / 'series-result.json').exists():
        raise ValueError('Sound series result already exists')
    legacy.artifacts.write_json(directory / 'series-result.json', report)
    (directory / 'series.pending.json').unlink()
    return report


def verify(directory):
    if (directory / 'series.pending.json').exists():
        raise ValueError('Sound series is still pending')
    expected = result(directory, full=True, pending=False)
    if read(directory / 'series-result.json')[0] != expected:
        raise ValueError('Sound series summary differs from its current case evidence')
    return expected


def failure(directory, index, phase, message):
    value, sha = read(directory / 'series-inputs.json')
    layout(Path(value['root']), directory)
    create(directory / 'series-failure.json', {'schema_version': 1, 'series_id': value['series_id'],
           'inputs_sha256': sha, 'qualification': False, 'completed': False,
           'failed_at_index': index, 'phase': phase, 'message': message,
           'failed_utc': datetime.now(timezone.utc).isoformat()})
    result_path = directory / 'series-result.json'
    if result_path.exists():
        archive = directory / 'series-result-before-failure.json'
        if archive.exists():
            raise ValueError('Refusing to overwrite an earlier series result history')
        result_path.rename(archive)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('begin', 'checkpoint', 'record', 'finish', 'verify', 'fail'))
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--root', type=Path)
    parser.add_argument('--abi', choices=('x86', 'armeabi-v7a'))
    for name in ('emulator', 'system-directory', 'kernel', 'ramdisk', 'android-sdk'):
        parser.add_argument('--' + name, type=Path)
    parser.add_argument('--classic-emulator', action='store_true')
    parser.add_argument('--adb-port', type=int)
    parser.add_argument('--index', type=int)
    parser.add_argument('--phase')
    parser.add_argument('--message')
    parser.add_argument('--artifact-lease-held', action='store_true')
    args = parser.parse_args()
    directory = args.directory.absolute()
    try:
        root = args.root if args.action == 'begin' else Path(read(directory / 'series-inputs.json')[0]['root'])
        root, directory = layout(root, directory)
        with legacy.artifacts.artifact_lease(root, args.artifact_lease_held):
            if args.action == 'begin':
                required = (args.root, args.abi, args.emulator, args.system_directory, args.kernel,
                            args.ramdisk, args.android_sdk, args.adb_port)
                if any(x is None for x in required):
                    raise ValueError('All frozen begin inputs are required')
                begin(root, directory, args.abi, args.emulator, args.system_directory, args.kernel,
                      args.ramdisk, args.android_sdk, args.classic_emulator, args.adb_port)
            elif args.action in ('checkpoint', 'record'):
                if args.index is None:
                    raise ValueError('Attempt index is required')
                (checkpoint if args.action == 'checkpoint' else record)(directory, args.index)
            elif args.action == 'fail':
                failure(directory, args.index, args.phase, args.message)
            else:
                {'finish': finish, 'verify': verify}[args.action](directory)
        print('Sound series metadata ' + args.action + ': PASS (diagnostic only)')
    except (OSError, ValueError, KeyError, TypeError, UnicodeError, RuntimeError) as error:
        parser.exit(1, 'Sound series refused: ' + str(error) + '\n')


if __name__ == '__main__':
    main()
