# SPDX-License-Identifier: GPL-3.0-or-later
"""Synthetic API21 sound records; no emulator, WAV writer or native code executes."""
import importlib.util
import json
from pathlib import Path
import uuid

import android_result_fixtures as data
import android_cpu_fixtures as cpu

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('api21_sound_fixture_collector', ROOT / 'scripts/run/android/android-api21-sound-cache.py')
sound = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sound)
PHASES = ('SOUND_CACHE: protocol=1', 'SOUND_CACHE: wav=pcm-s16le-8000-mono',
          'SOUND_CACHE: ready=1', 'SOUND_CACHE: playing=1', 'SOUND_CACHE: destroyed=1', 'SOUND_CACHE: return=0')


def prepare(root, abi='x86_64', name='fixture-run', *, kind='sound'):
    selected = sound._shared.SPECS[kind]
    qt = selected.get('qt_major', 5)
    profile = selected['name']
    app = selected.get('app', 'qt-selftest')
    package = ('org.longreachqt.examples.qt6.' + app.replace('-', '_') if qt == 6
               else 'org.longreachqt.examples.' + app.replace('-', ''))
    root = Path(root)
    data.packaged(root, qt, sound.base._artifacts, abi)
    identity = data.media_fixtures.launch(root, abi, name)
    run = root / name
    launch = json.loads((run / 'emulator-launch.json').read_text())
    host = data.host_fixtures.capture(run, launch['emulator'], launch['arguments'], artifact_root=root)
    cpu_fields = cpu.capture(run, abi)
    options = {'schema_version': 1, 'qt_major': qt, 'abi': abi, 'gpu_requested': 'on',
               'debug_qt_plugins': False, 'qt_quick_backend': 'default', 'diagnostic': selected['diagnostic']}
    (run / 'run-options.json').write_text(json.dumps(options))
    (run / 'guest-properties.txt').write_text('[ro.build.version.release]: [5.0.2]\n[ro.build.version.sdk]: [21]\n[ro.product.cpu.abi]: [' + abi + ']\n')
    case = run / profile
    case.mkdir()
    (case / 'files').mkdir()
    text = '\n'.join(PHASES) + '\n'
    if kind in ('tts', 'tts6'):
        from test_android_tts_protocol import fixture
        text = fixture()
    (case / 'files/selftest.stdout').write_text(text)
    (case / 'files/selftest-result.txt').write_text('0\n')
    process = data.exit_evidence(case, package, 'BEGIN-' + uuid.uuid4().hex)
    record = {'name': profile, 'app': app, 'arguments': selected['arguments'],
              'apk_relative': selected['apk'], 'result': 0, 'summary': [], 'scope': 'single-case',
              'diagnostic': selected['diagnostic'], 'qualification': False, 'completed': True,
              'apk_sha256': data.digest(root / selected['apk']),
              'apk_manifest_sha256': data.digest(root / 'apk-manifest.json'),
              'stdout_sha256': data.digest(case / 'files/selftest.stdout'),
              'diagnostic_stdout_sha256': data.digest(case / 'files/selftest.stdout'),
              'gpu': launch['gpu_effective'], 'run_options_sha256': data.digest(run / 'run-options.json'),
              'emulator_launch_sha256': data.digest(run / 'emulator-launch.json'),
              'emulator_identity_sha256': identity['emulator_identity_sha256'],
              'emulator_media_sha256': identity['emulator_media_sha256'],
              'launch_arguments': ['shell', 'am', 'start', '-n',
                  package + '/org.longreachqt.examples.SmokeActivity',
                  '--es', 'applicationArguments', selected['arguments']], **host, **cpu_fields, **process}
    data.api21_cleanup_evidence(root, [record], run=name)
    rebind_final(run, record)
    save(run, record)
    return record


def save(run, record):
    (Path(run) / 'results.json').write_text(json.dumps([record]))


def rebind_stdout(run, record):
    record['stdout_sha256'] = record['diagnostic_stdout_sha256'] = data.digest(Path(run) / record['name'] / 'files/selftest.stdout')


def rebind_final(run, record, **changed):
    run = Path(run)
    capture = {'schema_version': 1, 'captured': True, 'serial': 'emulator-5582',
               'logcat_sha256': data.digest(run / 'final-logcat.log'),
               'host_process_owner_sha256': record['host_process_owner_sha256'],
               'host_process_request_sha256': record['host_process_request_sha256']}
    capture.update(changed)
    (run / 'final-logcat-capture.json').write_text(json.dumps(capture))
    record['final_logcat_sha256'] = data.digest(run / 'final-logcat.log')
    record['final_logcat_capture_sha256'] = data.digest(run / 'final-logcat-capture.json')
