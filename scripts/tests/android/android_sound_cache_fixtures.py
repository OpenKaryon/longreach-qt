# SPDX-License-Identifier: GPL-3.0-or-later
"""Synthetic sound-series receipts only. Never executes an emulator or native code."""
import importlib.util
import json
from pathlib import Path
import uuid

import android_result_fixtures as results
import android_cpu_fixtures as cpu
import android_owned_process_fixtures as host

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('fixture_sound_series', ROOT / 'scripts/run/android/android-sound-cache-series.py')
series = importlib.util.module_from_spec(spec)
spec.loader.exec_module(series)
PHASES = ('SOUND_CACHE: protocol=1', 'SOUND_CACHE: wav=pcm-s16le-8000-mono',
          'SOUND_CACHE: ready=1', 'SOUND_CACHE: playing=1', 'SOUND_CACHE: destroyed=1', 'SOUND_CACHE: return=0')


def prepare(root, abi='x86'):
    root = Path(root)
    results.packaged(root, 5, series.legacy.artifacts, abi)
    media, tools, sdk = root.parent / 'media with spaces', root.parent / 'tools with spaces', root.parent / 'android sdk'
    for directory in (media, tools, sdk / 'platform-tools'):
        directory.mkdir(parents=True, exist_ok=True)
    for file in (media / 'system.img', media / 'userdata.img', media / 'kernel', media / 'ramdisk',
                 tools / 'already fixed emulator.exe', sdk / 'platform-tools/adb.exe'):
        file.write_text('inert sound-series fixture: ' + file.name)
    return {'root': root, 'abi': abi, 'emulator': tools / 'already fixed emulator.exe',
            'system_directory': media, 'kernel': media / 'kernel', 'ramdisk': media / 'ramdisk',
            'android_sdk': sdk, 'classic': True, 'adb_port': 5037}


def emulator_args(value, case):
    # Literal contract independent from the product helper. The raw runner's
    # actual argument generation is also covered by test-android-api10-case.ps1.
    system = value['system_directory']
    result = ['-sysdir', system, '-datadir', str(case), '-system', system + '/system.img',
              '-kernel', value['paths']['kernel'], '-ramdisk', value['paths']['ramdisk'],
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


def case(directory, index):
    directory = Path(directory)
    value = json.loads((directory / 'series-inputs.json').read_text())
    path = directory / f'run-{index:02}'
    path.mkdir()
    (path / 'files').mkdir()
    (path / 'files/selftest.stdout').write_text('\n'.join(PHASES) + '\n')
    (path / 'files/selftest-result.txt').write_text('0\n')
    (path / 'power-before.txt').write_text('mStayOnConditions=3\n')
    release = '2.3.7' if value['abi'] == 'x86' else '2.3.3'
    (path / 'guest.txt').write_text('ro.build.version.sdk=10\nro.product.cpu.abi=' + value['abi']
                                  + '\nro.build.version.release=' + release + '\n')
    arguments = emulator_args(value, path)
    record = {'schema_version': 3, 'case': None, 'completed': True, 'qualification': False, 'scope': 'single-case',
              'diagnostic': 'qt5-sound-cache-teardown', 'api': 10, 'abi': value['abi'],
              'sdk_image_id': value['sdk_image_id'], 'apk_manifest_bound': True,
              'apk_relative': 'apk/extended/qt-selftest.apk',
              'apk_manifest_sha256': value['file_sha256']['apk_manifest'], 'apk_sha256': value['file_sha256']['apk'],
              'emulator_sha256': value['file_sha256']['emulator'], 'termination_policy': 'natural',
              'adb_endpoint': value['adb_endpoint'], 'case_attempt_id': uuid.uuid4().hex,
              'launch_arguments': ['-s', 'emulator-5580', 'shell', 'am', 'start', '-n',
                  'org.longreachqt.examples.qtselftest/org.longreachqt.examples.SmokeActivity',
                  '--es', 'applicationArguments', '--sound-cache-teardown', '--es', 'qtRasterImageDepth', '32',
                  '--es', 'qtQuickBackend', 'software'],
              'emulator_arguments': arguments, 'stdout_sha256': results.digest(path / 'files/selftest.stdout'),
              'diagnostic_stdout_sha256': results.digest(path / 'files/selftest.stdout'),
              'guest_power_sha256': results.digest(path / 'power-before.txt')}
    # Same Android PID is intentional: separate fresh guests can reuse it.
    record.update(results.exit_evidence(path, 'org.longreachqt.examples.qtselftest', 'BEGIN-' + uuid.uuid4().hex, pid=1234, final=True))
    record.update(cpu.capture(path, value['abi']))
    record.update(host.capture(path, value['paths']['emulator'], arguments,
                               supervisor_pid=5000 + index, frontend_pid=6000 + index,
                               artifact_root=value['root'], adb_endpoint=value['adb_endpoint']))
    (path / 'input-receipt.json').write_text(json.dumps(record))
    return path, record
