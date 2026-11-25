# SPDX-License-Identifier: GPL-3.0-or-later
"""Bind an API21 invocation to its prepared emulator, media and CPU inputs."""
import argparse
import importlib.util
import json
from pathlib import Path
import shutil

REPO = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('android_prepared_media', REPO / 'scripts/build/qt6-android/prepare-emulator.py')
media = importlib.util.module_from_spec(spec)
spec.loader.exec_module(media)
CPU = {'armeabi-v7a': ('cortex-a8', 1, 'arm'), 'arm64-v8a': ('cortex-a57', 2, 'arm64'),
       'x86': ('Conroe', 1, 'x86'), 'x86_64': ('Nehalem', 2, 'x86_64')}


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def same_path(left, right):
    return Path(left).resolve() == Path(right).resolve()


def check_launch(root, run, abi, launch, ready, config, avd_index):
    if run.resolve().parent != root.resolve():
        raise ValueError('API21 run must be a direct artifact-root child')
    if launch.get('schema_version') != 2 or launch.get('abi') != abi:
        raise ValueError('Missing API21 identity-aware launch receipt')
    if not same_path(launch.get('emulator', ''), root / 'media' / ready['roles']['emulator']):
        raise ValueError('API21 launch did not use the prepared emulator')
    argv = launch.get('arguments')
    if not isinstance(argv, list) or not all(isinstance(item, str) for item in argv):
        raise ValueError('Invalid API21 emulator argv')

    def argument(flag):
        if argv.count(flag) != 1 or argv[-1] == flag:
            raise ValueError('Missing or duplicate API21 emulator argument: ' + flag)
        return argv[argv.index(flag) + 1]

    roles = ready['roles']
    paths = {'-sysdir': root / 'media' / abi, '-datadir': run,
             '-system': root / 'media' / roles['system'], '-kernel': root / 'media' / roles['kernel'],
             '-ramdisk': root / 'media' / roles['ramdisk'], '-initdata': root / 'media' / roles['userdata'],
             '-data': run / 'userdata-qemu.img'}
    for flag, path in paths.items():
        if not same_path(argument(flag), path):
            raise ValueError('API21 emulator uses unexpected media argument: ' + flag)
    cpu, cores, arch = CPU[abi]
    if argument('-avd') != 'longreach-api21-' + abi:
        raise ValueError('Unexpected API21 AVD name')
    index = dict(line.split('=', 1) for line in avd_index.splitlines() if '=' in line)
    if not same_path(index.get('path', ''), run / 'avd' / ('longreach-api21-' + abi + '.avd')) or index.get('target') != 'android-21':
        raise ValueError('Unexpected API21 AVD index path/target')
    values = dict(line.split('=', 1) for line in config.splitlines() if '=' in line)
    if any(values.get(key) != str(value) for key, value in
           [('abi.type', abi), ('hw.cpu.model', cpu), ('hw.cpu.ncore', cores), ('hw.cpu.arch', arch)]):
        raise ValueError('Unexpected API21 AVD CPU configuration')
    if abi == 'armeabi-v7a':
        if argument('-cpu') != cpu or '-qemu' not in argv or '-engine' in argv:
            raise ValueError('Unexpected API21 classic CPU/engine')
    else:
        if argument('-engine') != 'qemu2' or argument('-accel') != 'off' or argument('-avd') != 'longreach-api21-' + abi:
            raise ValueError('Unexpected API21 engine or acceleration')
        if abi in ('x86', 'x86_64') and (argument('-cpu') != cpu or '-qemu' not in argv):
            raise ValueError('Unexpected API21 Intel CPU arguments')
    return cpu, cores


def capture(root, run, abi, repo=None):
    repo = repo or REPO
    root, run = root.resolve(), run.resolve()
    ready = media.verify_ready(root, abi, repo)
    launch_path = run / 'emulator-launch.json'
    launch = read(launch_path)
    config, avd_index = '', ''
    inputs = {}
    # AVD files can be normalized by the emulator after launch. Preserve the
    # exact inputs read before Start-Process, rather than hash later output.
    source = run / 'avd' / ('longreach-api21-' + abi + '.avd/config.ini')
    snapshot = run / 'emulator-config-input.ini'
    shutil.copyfile(source, snapshot)
    config = snapshot.read_text(encoding='utf-8-sig')
    inputs[snapshot.name] = media.digest(snapshot)
    index_snapshot = run / 'emulator-avd-input.ini'
    shutil.copyfile(run / 'avd' / ('longreach-api21-' + abi + '.ini'), index_snapshot)
    avd_index = index_snapshot.read_text(encoding='utf-8-sig')
    inputs[index_snapshot.name] = media.digest(index_snapshot)
    cpu, cores = check_launch(root, run, abi, launch, ready, config, avd_index)
    # The disposable data image must start from the recorded pinned userdata.
    if media.digest(run / 'userdata-qemu.img') != ready['files'][ready['roles']['userdata']]:
        raise ValueError('API21 initial userdata differs from prepared media')
    snapshot = run / 'emulator-media.json'
    media.write_json(snapshot, ready)
    identity = {'schema_version': 1, 'abi': abi, 'arguments': launch['arguments'],
                'emulator_media_sha256': media.digest(snapshot), 'cpu_model': cpu, 'cpu_cores': cores,
                'launch_input_sha256': inputs, 'initial_userdata_sha256': media.digest(run / 'userdata-qemu.img')}
    media.write_json(run / 'emulator-identity.json', identity)
    launch['emulator_identity_sha256'] = media.digest(run / 'emulator-identity.json')
    media.write_json(launch_path, launch)
    return identity


def validate(root, run, abi, repo=None, verify_files=True):
    repo = repo or REPO
    root, run = root.resolve(), run.resolve()
    launch = read(run / 'emulator-launch.json')
    path = run / 'emulator-identity.json'
    identity = read(path)
    snapshot = run / 'emulator-media.json'
    if (identity.get('schema_version') != 1 or identity.get('abi') != abi or
            launch.get('emulator_identity_sha256') != media.digest(path) or
            identity.get('emulator_media_sha256') != media.digest(snapshot) or identity.get('arguments') != launch.get('arguments')):
        raise ValueError('API21 emulator identity receipt changed or differs from launch')
    ready = media.validate_ready(read(snapshot), root, abi, repo, verify_files)
    names = {'emulator-config-input.ini', 'emulator-avd-input.ini'}
    inputs = identity.get('launch_input_sha256', {})
    if set(inputs) != set(names) or any(media.digest(run / name) != sha for name, sha in inputs.items()):
        raise ValueError('API21 launch input snapshot changed')
    config = (run / 'emulator-config-input.ini').read_text(encoding='utf-8-sig') if names else ''
    avd_index = (run / 'emulator-avd-input.ini').read_text(encoding='utf-8-sig') if names else ''
    cpu, cores = check_launch(root, run, abi, launch, ready, config, avd_index)
    if (identity.get('cpu_model') != cpu or identity.get('cpu_cores') != cores or
            identity.get('initial_userdata_sha256') != ready['files'][ready['roles']['userdata']]):
        raise ValueError('API21 CPU or initial userdata receipt differs')
    roles = ready['roles']
    return {'emulator_identity_sha256': media.digest(path), 'emulator_media_sha256': media.digest(snapshot),
            'emulator_identity': {'cpu_model': cpu, 'cpu_cores': cores, 'archives': ready['archives'],
                                  'files': {name: ready['files'][name] for name in
                                            [roles['emulator'], *roles['engine_candidates'], roles['kernel'], roles['ramdisk'], roles['system'], roles['userdata']]}}}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('capture', 'verify'))
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--run', type=Path, required=True)
    parser.add_argument('--abi', choices=media.ABIS, required=True)
    args = parser.parse_args(argv)
    (capture if args.action == 'capture' else validate)(args.root, args.run, args.abi)


if __name__ == '__main__':
    main()
