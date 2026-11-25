# SPDX-License-Identifier: GPL-3.0-or-later
"""Collect explicit Qt5 API21 diagnostics without full-suite qualification."""
import argparse
import importlib.util
import json
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


base = module('diagnostic_api21_base', REPO / 'scripts/build/android-api21/collect-results.py')
protocol = module('sound_api21_protocol', REPO / 'scripts/tests/android/require-android-sound-cache.py')
tts_protocol = module('tts_api21_protocol', REPO / 'scripts/tests/android/require-android-tts.py')
extras_protocol = module('extras_api21_protocol', REPO / 'scripts/tests/android/require-android-extras.py')
extras_state = module('extras_api21_state', Path(__file__).with_name('android-extras-state.py'))
_identity = base._identity
SPECS = {
    'extras': {'name': 'android-extras', 'app': 'qt-selftest', 'apk': 'apk/qt-selftest.apk',
               'arguments': '--android-extras', 'diagnostic': 'qt5-android-extras',
               'output': 'android-extras-result.json', 'history': 'android-extras-previous-'},
    'tts': {'name': 'tts-behavior', 'app': 'multimedia-lab', 'apk': 'apk/multimedia-lab.apk',
            'arguments': '--tts-behavior', 'diagnostic': 'qt5-tts-behavior',
            'output': 'tts-behavior-result.json', 'history': 'tts-behavior-previous-'},
    'sound': {'name': 'sound-cache-teardown', 'apk': 'apk/extended/qt-selftest.apk',
              'arguments': '--sound-cache-teardown', 'diagnostic': 'qt5-sound-cache-teardown',
              'output': 'sound-cache-result.json', 'history': 'sound-cache-previous-'},
    'forward': {'name': 'api10-selftest', 'apk': 'apk/qt-selftest.apk',
                'arguments': '--selftest', 'diagnostic': 'qt5-api10-on-api21',
                'output': 'api10-on-api21-result.json', 'history': 'api10-on-api21-previous-'},
}


def coverage_binding():
    return {'source_api': 10, 'guest_api': 21, 'coverage_api': 10,
            'coverage_case': 'qt-selftest',
            'coverage_policy_sha256': base._artifacts.digest(base._baselines.BASELINES)}


def run_path(root, name):
    root = Path(root).resolve()
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]{0,63}', name):
        raise ValueError('Invalid API21 diagnostic run name')
    run = root / name
    if run.resolve().parent != root:
        raise ValueError('API21 diagnostic must be an ordinary run inside its artifact root')
    if run.exists():
        info = run.lstat()
        if (not stat.S_ISDIR(info.st_mode) or stat.S_ISLNK(info.st_mode)
                or getattr(info, 'st_file_attributes', 0) & getattr(stat, 'FILE_ATTRIBUTE_REPARSE_POINT', 0x400)):
            raise ValueError('API21 diagnostic must be an ordinary run inside its artifact root')
    return root, run


def validate(root, name, abi, kind):
    spec = SPECS[kind]
    if kind == 'forward' and abi not in ('x86', 'armeabi-v7a'):
        raise ValueError('API10 forward diagnostic supports only Qt5 ARMv7/x86 SDKs')
    coverage = coverage_binding() if kind == 'forward' else None
    root, run = run_path(root, name)
    base._artifacts.check_examples(root, 5, abi)
    manifest = base._artifacts.check_apks(root, 5, abi)
    records = json.loads((run / 'results.json').read_text(encoding='utf-8-sig'))
    if not isinstance(records, list):
        records = [records]
    if len(records) != 1:
        raise ValueError('API21 diagnostic requires exactly one case')
    record = records[0]
    required = {'name': spec['name'], 'app': spec.get('app', 'qt-selftest'), 'arguments': spec['arguments'],
                'apk_relative': spec['apk'], 'result': 0, 'scope': 'single-case', 'completed': True,
                'diagnostic': spec['diagnostic'], 'qualification': False}
    required.update(coverage if kind == 'forward' else {'summary': []})
    if any(type(record.get(key)) is not type(value) or record[key] != value for key, value in required.items()):
        raise ValueError('Unexpected API21 diagnostic case/qualification')
    launch = base._launch.validate(run, 5, abi, records)
    if launch['qualification'] or launch['launch_options'].get('diagnostic') != spec['diagnostic']:
        raise ValueError('API21 diagnostic must be explicitly classified without qualification')
    identity = _identity.validate(root, run, abi)
    cpu = base._cpu.validate(run, abi, record)
    host = base._owned.validate_emulator(run, bindings=record, artifact_root=root)
    if any(record.get(key) != identity[key] for key in ('emulator_identity_sha256', 'emulator_media_sha256')):
        raise ValueError('API21 diagnostic case belongs to another API21 emulator/media')
    properties = (run / 'guest-properties.txt').read_text(encoding='utf-8-sig').splitlines()
    for key, value in (('ro.build.version.release', '5.0.2'), ('ro.build.version.sdk', '21'), ('ro.product.cpu.abi', abi)):
        if f'[{key}]: [{value}]' not in properties:
            raise ValueError('Wrong API21 diagnostic guest: ' + key)
    if (record.get('apk_manifest_sha256') != base._artifacts.digest(root / 'apk-manifest.json')
            or record.get('apk_sha256') != manifest['files'][spec['apk']]):
        raise ValueError('API21 diagnostic case APK/manifest changed')
    case = run / spec['name']
    stdout = case / 'files/selftest.stdout'
    sha = base._artifacts.digest(stdout)
    if (record.get('stdout_sha256') != sha or record.get('diagnostic_stdout_sha256') != sha
            or (case / 'files/selftest-result.txt').read_text().strip() != '0'):
        raise ValueError('API21 diagnostic stdout or native return changed')
    text = stdout.read_text(encoding='utf-8-sig')
    if kind == 'sound':
        protocol.validate(text)
    elif kind == 'tts':
        tts_protocol.validate(text)
    elif kind == 'extras':
        extras_protocol.validate(text)
    else:
        base._baselines.require(5, 10, abi, 'qt-selftest', text)
        summaries = [line for line in text.splitlines() if re.fullmatch(r'---- [^\n:]+: \d+ passed, \d+ failed, \d+ skipped ----\s*', line)]
        if record.get('summary') != summaries:
            raise ValueError('Forward diagnostic summary differs from its bound stdout')
        expected = coverage
        if any(launch['launch_options'].get(key) != value for key, value in expected.items()):
            raise ValueError('Forward diagnostic source coverage policy changed')
    final = base._exit_evidence.validate(root, run, 5, abi, records, host_evidence=host)
    report = {'schema_version': 1, 'diagnostic': spec['diagnostic'], 'scope': 'single-case',
              'completed': True, 'qualification': False, 'qt_major': 5, 'api': 21, 'abi': abi, 'run': name,
              'sdk_image_id': manifest['sdk_image_id'], 'generation': manifest['generation'],
              'apk_manifest_sha256': base._artifacts.digest(root / 'apk-manifest.json'),
              'examples_manifest_sha256': base._artifacts.digest(root / 'examples-manifest.json'),
              'results_sha256': base._artifacts.digest(run / 'results.json'), 'cases': records,
              'all_observed_exits_clean': True}
    if kind == 'forward':
        if coverage_binding() != coverage:
            raise ValueError('Forward diagnostic source coverage policy changed during collection')
        report.update(coverage)
    report.update(launch)
    report.update(identity)
    report.update(cpu)
    report.update(host)
    report.update(final)
    if kind == 'extras':
        package = 'org.longreachqt.examples.qtselftest'
        report.update(extras_state.validate(case, package, record, run))
    return report


def collect(root, name, abi, kind, artifact_lease_held=False):
    spec = SPECS[kind]
    root, run = run_path(root, name)
    with base._artifacts.artifact_lease(root, artifact_lease_held):
        output = run / spec['output']
        # A failed recheck cannot leave the former diagnostic at its current name.
        # Preserve the old bytes, rather than silently deleting historical evidence.
        if output.exists():
            info = output.lstat()
            if (not stat.S_ISREG(info.st_mode) or stat.S_ISLNK(info.st_mode)
                    or getattr(info, 'st_file_attributes', 0) & getattr(stat, 'FILE_ATTRIBUTE_REPARSE_POINT', 0x400)):
                raise ValueError('Expected an ordinary report file before diagnostic recheck')
            history = run / (spec['history'] + uuid.uuid4().hex + '.json')
            if history.exists():
                raise ValueError('Refusing to overwrite diagnostic history')
            output.rename(history)
        report = validate(root, name, abi, kind)
        base._artifacts.write_json(output, report)
        return report


def main(kind, argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--run', required=True)
    parser.add_argument('--abi', choices=('armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64'), required=True)
    parser.add_argument('--artifact-lease-held', action='store_true')
    args = parser.parse_args(argv)
    try:
        collect(args.root, args.run, args.abi, kind, args.artifact_lease_held)
    except (OSError, ValueError, RuntimeError, KeyError, TypeError, UnicodeError) as error:
        parser.exit(1, 'API21 ' + kind + ' diagnostic refused: ' + str(error) + '\n')
    print('API21 ' + kind + ' diagnostic: saved evidence verified; qualification=false')


if __name__ == '__main__':
    raise SystemExit('Use the sound-cache or API10-forward diagnostic entry point')
