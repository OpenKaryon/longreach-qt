# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Classify recorded API21 launch options independently from case coverage."""
import hashlib
import json
from pathlib import Path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def application_arguments(qt, case, options):
    name = case['name']
    sound = options.get('diagnostic', 'none') == 'qt5-sound-cache-teardown'
    forward = options.get('diagnostic', 'none') == 'qt5-api10-on-api21'
    speech = options.get('diagnostic', 'none') == 'qt5-tts-behavior'
    extras = options.get('diagnostic', 'none') == 'qt5-android-extras'
    if forward:
        if qt != 5 or name != 'api10-selftest':
            raise ValueError('API10 forward diagnostic requires exactly its Qt5 selftest case')
        app, arguments = 'qt-selftest', '--selftest'
    elif speech:
        if qt != 5 or name != 'tts-behavior':
            raise ValueError('TTS diagnostic requires exactly its explicit Qt5 case')
        app, arguments = 'multimedia-lab', '--tts-behavior'
    elif extras:
        if qt != 5 or name != 'android-extras':
            raise ValueError('AndroidExtras requires exactly its explicit Qt5 core case')
        app, arguments = 'qt-selftest', '--android-extras'
    elif name == 'sound-cache-teardown':
        if qt != 5 or not sound:
            raise ValueError('Sound-cache case requires explicit Qt5 diagnostic mode')
        app, arguments = 'qt-selftest', '--sound-cache-teardown'
    elif sound:
        raise ValueError('Sound diagnostic cannot contain ordinary suite cases')
    elif name.startswith('strict-cxx23'):
        app, arguments = 'qt-selftest', '--modern-cpp'
    elif name == 'qt-selftest-extended':
        app, arguments = 'qt-selftest', '--selftest'
    elif name in ('widgets-gui', 'qml-gui'):
        app = 'widgets-gallery' if name == 'widgets-gui' else 'quick-qml-gallery'
        arguments = '--gallery-selftest'
    else:
        app, arguments = name, '--selftest'
    if case['app'] != app or case['arguments'] != arguments:
        raise ValueError('Unexpected API21 application/case arguments: ' + name)
    expected_apk = 'apk/' + ('extended/' if qt == 5 and (name.endswith('-extended') or name == 'sound-cache-teardown') else '') + app + '.apk'
    if case.get('apk_relative') != expected_apk:
        raise ValueError('Unexpected API21 APK for case: ' + name)
    package = ('org.longreachqt.examples.qt6.' + app.replace('-', '_') if qt == 6
               else 'org.longreachqt.examples.' + app.replace('-', ''))
    helper = (['CLASSPATH=/system/framework/am.jar', '/system/bin/app_process32',
               '/system/bin', 'com.android.commands.am.Am']
              if options.get('activity_manager_abi', 'default') == 'x86' else ['am'])
    result = ['shell', *helper, 'start', '-n', package + '/org.longreachqt.examples.SmokeActivity',
              '--es', 'applicationArguments', arguments]
    if options['debug_qt_plugins']:
        result += ['--ez', 'debugQtPlugins', 'true']
    if options['qt_quick_backend'] != 'default':
        result += ['--es', 'qtQuickBackend', options['qt_quick_backend']]
    return result


def validate(run, qt, abi, records):
    options_path, emulator_path = run / 'run-options.json', run / 'emulator-launch.json'
    options = json.loads(options_path.read_text(encoding='utf-8-sig'))
    emulator = json.loads(emulator_path.read_text(encoding='utf-8-sig'))
    if (options.get('schema_version') != 1 or options.get('qt_major') != qt or options.get('abi') != abi or
            options.get('gpu_requested') not in ('on', 'mesa') or
            type(options.get('debug_qt_plugins')) is not bool or
            options.get('qt_quick_backend') not in ('default', 'software')):
        raise ValueError('Missing or invalid API21 run launch options')
    activity_manager = options.get('activity_manager_abi', 'default')
    if activity_manager not in ('default', 'x86') or (activity_manager == 'x86' and abi != 'x86_64'):
        raise ValueError('Invalid Activity Manager helper ABI')
    if activity_manager == 'x86':
        helper_path = run / 'activity-manager-helper.elf'
        helper = helper_path.read_bytes()
        if (len(helper) < 52 or helper[:7] != b'\x7fELF\x01\x01\x01' or helper[18:20] != b'\x03\x00' or
                options.get('activity_manager_helper_sha256') != digest(helper_path)):
            raise ValueError('Activity Manager helper bytes or ABI differ from the run')
    elif 'activity_manager_helper_sha256' in options:
        raise ValueError('Default Activity Manager cannot claim an explicit helper witness')
    diagnostic = options.get('diagnostic', 'none')
    if diagnostic not in ('none', 'qt5-sound-cache-teardown', 'qt5-api10-on-api21', 'qt5-tts-behavior', 'qt5-android-extras'):
        raise ValueError('Invalid API21 diagnostic mode')
    if diagnostic == 'qt5-sound-cache-teardown' and (qt != 5 or len(records) != 1 or records[0].get('name') != 'sound-cache-teardown'):
        raise ValueError('Sound diagnostic requires exactly one explicit Qt5 case')
    if diagnostic == 'qt5-tts-behavior' and (qt != 5 or len(records) != 1 or records[0].get('name') != 'tts-behavior'):
        raise ValueError('TTS diagnostic requires exactly one explicit Qt5 case')
    if diagnostic == 'qt5-android-extras' and (qt != 5 or len(records) != 1 or records[0].get('name') != 'android-extras'):
        raise ValueError('AndroidExtras requires exactly one explicit Qt5 diagnostic case')
    if diagnostic == 'qt5-api10-on-api21':
        if qt != 5 or abi not in ('x86', 'armeabi-v7a') or len(records) != 1 or records[0].get('name') != 'api10-selftest':
            raise ValueError('API10 forward diagnostic requires one Qt5 ARMv7/x86 selftest')
        expected = {'source_api': 10, 'guest_api': 21, 'coverage_api': 10,
                    'coverage_case': 'qt-selftest',
                    'coverage_policy_sha256': digest(Path(__file__).with_name('android-baselines.json'))}
        if any(type(options.get(key)) is not type(value) or options[key] != value for key, value in expected.items()):
            raise ValueError('API10 forward diagnostic source coverage binding differs')
    gpu = 'swiftshader_indirect' if abi in ('x86', 'x86_64') else options['gpu_requested']
    if (emulator.get('schema_version') != 2 or emulator.get('abi') != abi or
            emulator.get('gpu_requested') != options['gpu_requested'] or emulator.get('gpu_effective') != gpu):
        raise ValueError('API21 emulator GPU receipt differs from run options')
    argv = emulator.get('arguments')
    if (not isinstance(argv, list) or not all(isinstance(value, str) for value in argv) or
            argv.count('-gpu') != 1 or argv[-1] == '-gpu' or argv[argv.index('-gpu') + 1] != gpu):
        raise ValueError('API21 emulator GPU does not match its recorded launch arguments')
    options_sha, emulator_sha = digest(options_path), digest(emulator_path)
    for case in records:
        if case.get('run_options_sha256') != options_sha or case.get('emulator_launch_sha256') != emulator_sha:
            raise ValueError('Case belongs to different API21 launch options: ' + case.get('name', '?'))
        if case.get('gpu') != gpu or case.get('launch_arguments') != application_arguments(qt, case, options):
            raise ValueError('Recorded API21 application launch differs from its options: ' + case['name'])
    reasons = []
    if diagnostic == 'qt5-sound-cache-teardown':
        reasons.append('Qt5 sound-cache diagnostic; no full-suite qualification')
    if diagnostic == 'qt5-tts-behavior':
        reasons.append('Qt5 TTS behavior diagnostic; no full-suite or audible-output qualification')
    if diagnostic == 'qt5-android-extras':
        reasons.append('Qt5 AndroidExtras diagnostic; no full-suite qualification')
    if diagnostic == 'qt5-api10-on-api21':
        reasons.append('API10 APK on API21 diagnostic; no SDK or full-suite qualification')
    if options['debug_qt_plugins']:
        reasons.append('Qt plugin diagnostics enabled')
    if options['qt_quick_backend'] != 'default':
        reasons.append('Qt Quick software backend requested')
    if options['gpu_requested'] != 'on':
        reasons.append('Nondefault GPU option requested')
    return {'qualification': not reasons, 'diagnostic_reasons': reasons,
            'launch_options': options, 'gpu_effective': gpu,
            'run_options_sha256': options_sha, 'emulator_launch_sha256': emulator_sha}
