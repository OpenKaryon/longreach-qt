# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Synthetic collector data only; never a native or Android qualification."""
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
from unittest.mock import patch
import zipfile
import zlib
import android_media_fixtures as media_fixtures
import android_sdk_report_fixtures as sdk_reports
import android_native_abi_fixtures as native_fixtures
import android_cpu_fixtures as cpu_fixtures
import android_owned_process_fixtures as host_fixtures

ROOT = Path(__file__).resolve().parents[3]
SDK = 'sha256:' + 'a' * 64
_spec = importlib.util.spec_from_file_location('qt4_fixture_artifacts', ROOT / 'scripts/build/qt4-android/artifact-manifest.py')
QT4_ARTIFACTS = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(QT4_ARTIFACTS)
BASELINES = json.loads((ROOT / 'scripts/run/android/android-baselines.json').read_text())['targets']
_spec = importlib.util.spec_from_file_location('fixture_baselines', ROOT / 'scripts/run/android/android-baselines.py')
NAMED_BASELINES = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(NAMED_BASELINES)
QUICK_CHECKS = ['qrc and first frame', 'Android tap updates QML and frame',
                'Android pause and resume preserve input and rendering',
                'shared Qt Quick Gallery renders and navigates',
                'shared Widgets Gallery toggles a checkbox and changes tabs']


def write(root, name, text):
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding='utf-8')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def elf(abi):
    return native_fixtures.elf(abi, b'SYNTHETIC-COLLECTOR-FIXTURE')


def stdout(qt, api, abi, case, label='fixture'):
    base = NAMED_BASELINES.policy(qt, api, abi, case)
    if case in ('strict', 'strict-cxx23', 'strict-cxx23-extended'):
        names = [name for name in (ROOT / 'tests/common/moderncpp-required.txt').read_text().splitlines()
                 if name and not name.startswith('#')]
        lines = ['__cplusplus: 202302']
    else:
        names = list(base.get('required_pass', []))
        names += [f'fixture/check-{index}' for index in range(base['min_pass'] - len(names))]
        lines = []
    lines += ['PASS: ' + name for name in names]
    if base.get('require_timed_sync_evidence'):
        for name in NAMED_BASELINES.TIMED_SYNC.CHECKS:
            acquired, elapsed = (0, 200) if name.endswith('-timeout') else (1, 250)
            lines.append(f'OBSERVE: {name} - attempt=1 ready=1 unavailable=1 armed=1 released_before_call=0 acquired={acquired} elapsed_ms={elapsed} joined=1 verdict=pass')
    lines.append(f'---- {label}: {len(names)} passed, 0 failed, 0 skipped ----')
    return '\n'.join(lines) + '\n'


def log(root, case, marker, body='Example returned 0\n'):
    write(root, f'fixture-run/{case}/log-marker.txt', marker)
    write(root, f'fixture-run/{case}/logcat.log', body)
    write(root, f'fixture-run/{case}/logcat-raw.log', f'I/LongreachCase( 123): {marker}\n' + body)


def exit_evidence(case, package, marker, pid=1234, final=False):
    case.mkdir(parents=True, exist_ok=True)
    start = f'I/ActivityManager( 100): Start proc {package} for activity {package}/.SmokeActivity: pid={pid} uid=10001'
    death = f'I/ActivityManager( 100): Process {package} (pid {pid}) has died.'
    body = (case / 'logcat.log').read_text() if (case / 'logcat.log').exists() else 'native returned zero\n'
    text = start + '\n' + body.rstrip('\n') + '\n' + death + '\n'
    (case / 'log-marker.txt').write_text(marker)
    (case / 'logcat.log').write_text(text)
    raw = f'I/LongreachCase( 100): {marker}\n' + text
    (case / 'logcat-raw.log').write_text(raw)
    (case / 'process-exit-ps.txt').write_text('USER PID PPID NAME\nroot 1 0 /init\n')
    proof = {'schema_version': 1, 'package': package, 'process_id': pid, 'log_marker': marker,
             'process_exit_confirmed': True, 'termination_policy': 'natural', 'observation_order': 'logcat-then-ps',
             'start_line': start, 'death_line': death, 'observations': 2, 'elapsed_ms': 10, 'timeout_seconds': 60,
             'logcat_sha256': digest(case / 'logcat.log'), 'raw_logcat_sha256': digest(case / 'logcat-raw.log'),
             'ps_sha256': digest(case / 'process-exit-ps.txt')}
    (case / 'process-exit.json').write_text(json.dumps(proof))
    record = {'process_exit_confirmed': True, 'process_id': pid, 'log_marker': marker,
              'process_exit_proof_sha256': digest(case / 'process-exit.json')}
    if final:
        (case / 'final-logcat.log').write_text(raw)
        record.update(package=package, emulator_exit_confirmed=True, final_logcat_sha256=digest(case / 'final-logcat.log'))
    return record


def invalidate_exit(case, record, mutation):
    """Change synthetic evidence, rebinding digests to reach lifecycle guards."""
    proof_path = case / 'process-exit.json'
    if mutation == 'missing':
        proof_path.unlink()
        return
    if mutation == 'unconfirmed':
        record['process_exit_confirmed'] = False
        return
    proof = json.loads(proof_path.read_text())
    if mutation == 'still-present':
        with (case / 'process-exit-ps.txt').open('a') as stream:
            stream.write(f"u0_a1 {proof['process_id']} 1 {proof['package']}\n")
        proof['ps_sha256'] = digest(case / 'process-exit-ps.txt')
    elif mutation == 'debuggerd':
        for name, field in (('logcat.log', 'logcat_sha256'), ('logcat-raw.log', 'raw_logcat_sha256')):
            with (case / name).open('a') as stream:
                stream.write('I/DEBUG( 101): *** *** *** *** *** *** *** ***\n')
            proof[field] = digest(case / name)
    else:
        raise AssertionError(mutation)
    proof_path.write_text(json.dumps(proof))
    record['process_exit_proof_sha256'] = digest(proof_path)


def packaged(root, qt, artifacts, abi='x86_64'):
    runtime = elf(abi)
    for app in artifacts.APPS:
        write(root, f'deployment/{app}/res/values/libs.xml', '<resources/>')
        native = root / f'deployment/{app}/libs/{abi}/lib{app}_{abi}.so'
        native.parent.mkdir(parents=True, exist_ok=True)
        native.write_bytes(runtime)
    if qt == 5:
        write(root, 'deployment-extended/qt-selftest/res/values/libs.xml', '<resources/>')
        native = root / f'deployment-extended/qt-selftest/libs/{abi}/libqt-selftest_{abi}.so'
        native.parent.mkdir(parents=True, exist_ok=True)
        native.write_bytes(runtime)
    packaging = 'sdk' if qt == 5 else 'sdk-packaging'
    for name in ('jar/QtAndroid.jar', 'src/android/java/src/Fixture.java', 'src/android/java/res/values/strings.xml'):
        write(root, packaging + '/' + name, 'synthetic packaging input')
    runtime_path = root / ('native/libc++_shared.so' if qt == 5 else 'libc++_shared.so')
    runtime_path.parent.mkdir(parents=True, exist_ok=True)
    runtime_path.write_bytes(runtime)
    write(root, 'sdk-modules.txt', 'fixture-module\n')
    write(root, 'sdk-api21-elf.json', json.dumps({'libraries': [{'fixture': True}]}))
    sdk_reports.export(root, qt, abi, SDK, runtime)
    artifacts.begin(root, qt, abi, SDK)
    artifacts.finish(root, qt, abi, SDK)
    for name in artifacts.apk_paths(qt):
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr(f'lib/{abi}/libc++_shared.so', runtime)
            archive.writestr(f'lib/{abi}/libfixture.so', runtime)
    for name in ('apk/local-examples.jks', *(['apk/extended/local-examples.jks'] if qt == 5 else [])):
        (root / name).write_text('fixture initial key')
    with patch.object(artifacts, 'packaging_inputs', return_value={'fixture': 'no host tools'}):
        artifacts.begin_apks(root, qt, abi, 'fixture-sdk')
        artifacts.record_apks(root, qt, abi, 'fixture-sdk')


def api21(root, qt, artifacts, abi='x86_64'):
    packaged(root, qt, artifacts, abi)
    manifest = digest(root / 'apk-manifest.json')
    cases = [('strict-cxx23', 'qt-selftest', False)]
    cases += [(app, app, False) for app in artifacts.APPS]
    if qt == 5:
        cases += [('strict-cxx23-extended', 'qt-selftest', True), ('qt-selftest-extended', 'qt-selftest', True)]
    cases += [('widgets-gui', 'widgets-gallery', False), ('qml-gui', 'quick-qml-gallery', False)]
    gpu = 'swiftshader_indirect' if abi in ('x86', 'x86_64') else 'on'
    identity = media_fixtures.launch(root, abi)
    launch = json.loads((root / 'fixture-run/emulator-launch.json').read_text())
    host_evidence = host_fixtures.capture(root / 'fixture-run', launch['emulator'], launch['arguments'], artifact_root=root)
    write(root, 'fixture-run/run-options.json', json.dumps({'schema_version': 1, 'qt_major': qt, 'abi': abi,
          'gpu_requested': 'on', 'debug_qt_plugins': False, 'qt_quick_backend': 'default'}))
    options_sha, emulator_sha = digest(root / 'fixture-run/run-options.json'), digest(root / 'fixture-run/emulator-launch.json')
    cpu_evidence = cpu_fixtures.capture(root / 'fixture-run', abi)
    records = []
    for index, (case, app, extended) in enumerate(cases):
        text = stdout(qt, 21, abi, case)
        write(root, f'fixture-run/{case}/files/selftest.stdout', text)
        write(root, f'fixture-run/{case}/files/selftest-result.txt', '0')
        marker = f'BEGIN-{index:032x}'
        log(root, case, marker)
        relative = f'apk/{"extended/" if extended else ""}{app}.apk'
        arguments = '--modern-cpp' if case.startswith('strict-cxx23') else ('--gallery-selftest' if case in ('widgets-gui', 'qml-gui') else '--selftest')
        package = ('org.longreachqt.examples.qt6.' + app.replace('-', '_') if qt == 6
                   else 'org.longreachqt.examples.' + app.replace('-', ''))
        launch_argv = ['shell', 'am', 'start', '-n', package + '/org.longreachqt.examples.SmokeActivity',
                       '--es', 'applicationArguments', arguments]
        exit_record = exit_evidence(root / 'fixture-run' / case, package, marker, 2000 + index)
        records.append({'name': case, 'app': app, 'arguments': arguments, 'result': 0, **exit_record, **cpu_evidence, **host_evidence,
                        'launch_arguments': launch_argv, 'gpu': gpu,
                        'run_options_sha256': options_sha, 'emulator_launch_sha256': emulator_sha,
                        'emulator_identity_sha256': identity['emulator_identity_sha256'], 'emulator_media_sha256': identity['emulator_media_sha256'],
                        'apk_relative': relative, 'apk_sha256': digest(root / relative),
                        'apk_manifest_sha256': manifest, 'summary': [text.splitlines()[-1]], 'log_marker': marker})
    api21_cleanup_evidence(root, records)
    write(root, 'fixture-run/results.json', json.dumps(records))
    write(root, 'fixture-run/guest-properties.txt', f'[ro.build.version.release]: [5.0.2]\n[ro.build.version.sdk]: [21]\n[ro.product.cpu.abi]: [{abi}]\n')
    return records


def api21_cleanup_evidence(root, records, run='fixture-run', rewrite_case=True):
    """Synthetic natural-exit captures; Qt4's resident JNI contract is separate."""
    directory = root / run
    if rewrite_case:
        for record in records:
            case = directory / record['name']
            record['stdout_sha256'] = digest(case / 'files/selftest.stdout')
            for original, final in (('logcat-raw.log', 'logcat-after-cleanup-raw.log'),
                                    ('logcat.log', 'logcat-after-cleanup.log')):
                (case / final).write_bytes((case / original).read_bytes())
            record['case_cleanup_raw_logcat_sha256'] = digest(case / 'logcat-after-cleanup-raw.log')
            record['case_cleanup_logcat_sha256'] = digest(case / 'logcat-after-cleanup.log')
    last = directory / records[-1]['name'] / 'logcat-after-cleanup-raw.log'
    (directory / 'final-logcat.log').write_bytes(last.read_bytes())
    capture = {'schema_version': 1, 'captured': True, 'serial': 'emulator-5582',
               'logcat_sha256': digest(directory / 'final-logcat.log'),
               **{key: records[0][key] for key in ('host_process_owner_sha256', 'host_process_request_sha256')}}
    write(root, run + '/final-logcat-capture.json', json.dumps(capture))
    for record in records:
        record.update(final_logcat_sha256=capture['logcat_sha256'],
                      final_logcat_capture_sha256=digest(directory / 'final-logcat-capture.json'))


def png():
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    raw = (b'\0' + b'\xff\xff\xff' * 256) * 256
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 256, 256, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')


def qt4_cleanup_evidence(root, records, run='fixture-run', serial='emulator-5582'):
    directory = root / run
    for record in records:
        case = directory / record['profile']
        for original, final in (('logcat-raw.log', 'logcat-after-cleanup-raw.log'),
                                ('logcat.log', 'logcat-after-cleanup.log')):
            (case / final).write_bytes((case / original).read_bytes())
        record['case_cleanup_raw_logcat_sha256'] = digest(case / 'logcat-after-cleanup-raw.log')
        record['case_cleanup_logcat_sha256'] = digest(case / 'logcat-after-cleanup.log')
    last = directory / records[-1]['profile'] / 'logcat-after-cleanup-raw.log'
    (directory / 'final-logcat.log').write_bytes(last.read_bytes())
    capture = {'schema_version': 1, 'captured': True, 'serial': serial,
               'logcat_sha256': digest(directory / 'final-logcat.log'),
               **{key: records[0][key] for key in ('host_process_owner_sha256', 'host_process_request_sha256')}}
    write(root, run + '/final-logcat-capture.json', json.dumps(capture))
    for record in records:
        record.update(final_logcat_sha256=capture['logcat_sha256'],
                      final_logcat_capture_sha256=digest(directory / 'final-logcat-capture.json'))


def qt4(root, abi='x86_64'):
    api, release = (10, '2.3.7') if abi == 'x86' else (21, '5.0.2')
    runtime = elf(abi)
    write(root, 'sdk-image-id.txt', SDK)
    write(root, 'examples-sdk-image-id.txt', SDK)
    write(root, 'sdk-reports/runtime-sha256.txt', hashlib.sha256(runtime).hexdigest() + ' runtime\n')
    (root / 'native').mkdir(exist_ok=True)
    (root / 'native/libc++_shared.so').write_bytes(runtime)
    labels = {'selftest': 'qt-selftest', 'widgets': 'widgets-gallery', 'graphics': 'graphics', 'painting': 'painting-lab',
              'multimedia': 'multimedia-lab', 'gl': 'gl-heavy', 'qml': 'quick-qml', 'network': 'network-gui'}
    names = ['bootstrap', 'strict', 'core', 'quick', *labels]
    clients = []
    for name in names:
        path = root / f'native/{name}.so'
        path.write_bytes(runtime + name.encode())
        clients.append({'profile': name, 'native': name + '.so', 'sha256': digest(path)})
    write(root, 'native/examples-build.json', json.dumps({'schema_version': 2, 'abi': abi, 'api': api,
          'sdk_image_id': SDK, 'runtime_sha256': digest(root / 'native/libc++_shared.so'), 'clients': clients}))
    sdk_reports.export(root / 'sdk-reports', 4, abi, SDK, runtime)
    QT4_ARTIFACTS.begin(root, abi, SDK)
    QT4_ARTIFACTS.finish(root, abi, SDK)
    write(root, 'local-probe.jks', 'synthetic signing key, no cryptography')
    for name in names:
        with zipfile.ZipFile(root / f'{name}.apk', 'w') as archive:
            archive.writestr(f'lib/{abi}/libc++_shared.so', runtime)
            archive.writestr(f'lib/{abi}/libdonut_probe.so', (root / f'native/{name}.so').read_bytes())
    with patch.object(QT4_ARTIFACTS.common, 'packaging_inputs', return_value={'fixture': 'no host tools'}):
        QT4_ARTIFACTS.begin_apks(root, abi, 'fixture-sdk')
        QT4_ARTIFACTS.record_apks(root, abi, 'fixture-sdk')
    manifest = digest(root / 'apk-packages.json')
    apk_generation = digest(root / 'apk-manifest.json')
    native_generation = digest(root / 'examples-manifest.json')
    cpu_evidence = cpu_fixtures.capture(root / 'fixture-run', abi)
    records = []
    for index, name in enumerate(names):
        marker = f'BEGIN-{index:032x}'
        log(root, name, marker, 'QtCore 4.8.7 PASS\n' if name == 'core' else 'native completed\n')
        native_return = 42 if name == 'bootstrap' else 0
        write(root, f'fixture-run/{name}/files/probe-result.txt', str(native_return))
        summary = []
        if name in labels or name == 'strict':
            text = stdout(4, api, abi, name, labels.get(name, 'fixture'))
            file_name = 'strict-cxx23.log' if name == 'strict' else 'suite.log'
            write(root, f'fixture-run/{name}/files/{file_name}', text)
            summary = [text.splitlines()[-1]]
            passed = 25 if name == 'strict' else BASELINES[f'4/{api}/{abi}'][name]['min_pass']
        elif name == 'quick':
            write(root, f'fixture-run/{name}/files/quick-smoke.txt', '\n'.join('PASS: ' + value for value in QUICK_CHECKS))
            write(root, f'fixture-run/{name}/instrumentation.log', 'INSTRUMENTATION_CODE: -1\n')
            for filename in ('qml-gallery.png', 'widgets-gallery.png'):
                (root / f'fixture-run/{name}/files/{filename}').write_bytes(png())
            passed, native_return = 5, None
        else:
            passed = 1
        records.append({'profile': name, 'sdk_image_id': SDK, 'apk_sha256': digest(root / f'{name}.apk'), **cpu_evidence,
                        'apk_manifest_sha256': manifest, 'apk_generation_manifest_sha256': apk_generation,
                        'examples_manifest_sha256': native_generation, 'log_marker': marker, 'native_return': native_return,
                        'instrumentation_code': -1 if name == 'quick' else None,
                        'passed': passed, 'failed': 0, 'skipped': 0, 'summary': summary})
    if api == 21:
        identity = media_fixtures.launch(root, abi)
        for record in records:
            record.update({key: identity[key] for key in ('emulator_identity_sha256', 'emulator_media_sha256')})
    if api == 10:
        program = root / 'media/tools/emulator-x86.exe'
        program.parent.mkdir(parents=True, exist_ok=True)
        program.write_text('synthetic legacy emulator, not executable')
        write(root, 'fixture-run/emulator-launch.json', json.dumps({'schema_version': 1,
              'emulator': str(program), 'arguments': ['-datadir', str(root / 'fixture-run'), '-port', '5580']}))
    launch = json.loads((root / 'fixture-run/emulator-launch.json').read_text())
    host_evidence = host_fixtures.capture(root / 'fixture-run', launch['emulator'], launch['arguments'], artifact_root=root)
    for record in records:
        record.update(host_evidence)
    qt4_cleanup_evidence(root, records, serial='emulator-5580' if api == 10 else 'emulator-5582')
    write(root, 'fixture-run/results.json', json.dumps(records))
    write(root, 'fixture-run/guest-properties.txt', f'[ro.build.version.release]: [{release}]\n[ro.build.version.sdk]: [{api}]\n[ro.product.cpu.abi]: [{abi}]\n')
    return records
