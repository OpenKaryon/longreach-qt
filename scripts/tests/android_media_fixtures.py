# SPDX-License-Identifier: GPL-3.0-or-later
"""Synthetic pinned media and invocation inputs; no executable is run."""
import importlib.util
import json
from pathlib import Path
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[2]


def load(name, relative):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


media = load('fixture_prepared_media', 'scripts/build/qt6-android/prepare-emulator.py')
identity = load('fixture_emulator_identity', 'scripts/run/android-api21-identity.py')


def archives(repo, abi):
    tools, prefix, roles = media.layout(abi)
    image = abi + '-21_r99.zip'
    inputs = ((image, {roles[key]: ('fixture/' + key).encode() for key in
                       ('kernel', 'ramdisk', 'system', 'userdata', 'build_properties')}),
              (tools, {**{name.removeprefix(prefix): ('fixture/' + name).encode()
                          for name in [roles['emulator'], *roles['engine_candidates']]},
                       ('emulator/lib64/fixture.dll' if abi in ('x86', 'x86_64') else 'tools/lib/fixture.dll'): b'synthetic dependency'}))
    downloads = repo / 'downloads/android-lollipop'
    downloads.mkdir(parents=True, exist_ok=True)
    records = []
    for name, files in inputs:
        path = downloads / name
        with zipfile.ZipFile(path, 'w') as package:
            for relative, data in files.items():
                package.writestr(relative, data)
        records.append({'file': name, 'sha256': media.digest(path)})
    path = repo / media.LOCK
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({'sources': records}))
    return roles


def launch(root, abi, run_name='fixture-run'):
    repo = root / 'fixture-media-repo'
    archives(repo, abi)
    ready = media.prepare(repo, root, abi)
    roles = ready['roles']
    run = root / run_name
    run.mkdir(exist_ok=True)
    shutil.copyfile(root / 'media' / roles['userdata'], run / 'userdata-qemu.img')
    gpu = 'swiftshader_indirect' if abi in ('x86', 'x86_64') else 'on'
    argv = ['-sysdir', str(root / 'media' / abi), '-datadir', str(run),
            '-system', str(root / 'media' / roles['system']), '-kernel', str(root / 'media' / roles['kernel']),
            '-ramdisk', str(root / 'media' / roles['ramdisk']), '-data', str(run / 'userdata-qemu.img'),
            '-initdata', str(root / 'media' / roles['userdata']), '-gpu', gpu]
    cpu, cores, arch = identity.CPU[abi]
    if abi == 'armeabi-v7a':
        argv += ['-qemu', '-cpu', cpu]
    else:
        argv += ['-avd', 'longreach-api21-' + abi, '-engine', 'qemu2', '-accel', 'off']
        avd = run / 'avd' / ('longreach-api21-' + abi + '.avd')
        avd.mkdir(parents=True)
        (avd.parent / ('longreach-api21-' + abi + '.ini')).write_text(f'path={avd}\ntarget=android-21\n')
        (avd / 'config.ini').write_text(f'abi.type={abi}\nhw.cpu.arch={arch}\nhw.cpu.model={cpu}\nhw.cpu.ncore={cores}\n')
        if abi in ('x86', 'x86_64'):
            argv += ['-qemu', '-cpu', cpu]
    (run / 'emulator-launch.json').write_text(json.dumps({'schema_version': 2, 'abi': abi,
        'gpu_requested': 'on', 'gpu_effective': gpu, 'arguments': argv, 'emulator': str(root / 'media' / roles['emulator'])}))
    identity.capture(root, run, abi, repo)
    return identity.validate(root, run, abi, repo)
