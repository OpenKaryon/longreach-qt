# SPDX-License-Identifier: GPL-3.0-or-later

"""Stage Qt6 shared examples with CMake metadata and Qt's Android deployer."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', required=True)
parser.add_argument('--abi', choices=('armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64'), default='armeabi-v7a')
parser.add_argument('--build', type=Path, default=Path('/work/api21/tests-qt6-android'))
parser.add_argument('--output', type=Path, default=Path('/out/deployment'))
args = parser.parse_args()
repo = Path('/repo')
sdk = Path(f'/opt/qt6-android-{args.abi}-llvm')
triple = {'armeabi-v7a': 'arm-linux-androideabi', 'arm64-v8a': 'aarch64-linux-android', 'x86': 'i686-linux-android', 'x86_64': 'x86_64-linux-android'}[args.abi]
expected = [line.strip() for line in (repo / 'tests/expected-apps.txt').read_text().splitlines()
            if line.strip() and not line.startswith('#') and line.strip() != 'smoke-runner']
if args.app not in expected:
    raise ValueError('Unknown shared application')
configuration = list(args.build.rglob(f'android-{args.app}-deployment-settings.json'))
if len(configuration) != 1:
    raise ValueError(f'Expected one generated deployment configuration: {configuration}')
settings = json.loads(configuration[0].read_text())
if settings.get('android-min-sdk-version') != '21':
    raise ValueError('Application does not target minimum API21')
if settings.get('ndk-host') != 'linux-x86_64':
    raise ValueError('External toolchain NDK host metadata is incomplete')
runtime = Path(settings['stdcpp-path']) / f'{triple}/libc++_shared.so'
if not runtime.is_file():
    raise ValueError(f'The generated configuration cannot find the LLVM21 runtime: {runtime}')
native_name = f'lib{args.app}_{args.abi}.so'
native = list((args.build / args.app).rglob(native_name))
if len(native) != 1:
    raise ValueError(f'Expected one native example: {native}')
output = args.output.resolve()
destination = output / args.app
marker = destination / '.longreach-qt6-deployment'
if destination.exists():
    if destination.resolve().parent != output or not marker.is_file():
        raise ValueError(f'Refusing to replace unowned deployment: {destination}')
    shutil.rmtree(destination)
shutil.copytree(sdk / 'src/android/templates', destination)
marker.write_text(args.app + '\n')
libraries = destination / f'libs/{args.abi}'
libraries.mkdir(parents=True, exist_ok=True)
shutil.copy2(native[0], libraries / native_name)
# Limit scanning to the resource set of this Qt generation. Qt4 and Qt5
# alternatives live beside the shared sources and must not become dependencies.
scan = args.build / 'android-qml-scan' / args.app
scan.mkdir(parents=True, exist_ok=True)
if args.app == 'qt-selftest':
    (scan / 'imports.qml').write_text('import QtQml\nQtObject {}\n')
resources = sorted((args.build / args.app).glob('*.qrc'))
if args.app == 'quick-qml-gallery':
    resources.insert(0, repo / 'tests/quick-qml-gallery/qml.qrc')
    (scan / 'quick3d.qml').write_text('import QtQuick3D\nNode {}\n')
settings['qml-root-path'] = str(scan)
settings['qrcFiles'] = ','.join(str(path) for path in resources)
configuration = destination / 'deployment-settings.json'
configuration.write_text(json.dumps(settings, indent=2) + '\n')
subprocess.run([str(Path('/opt/qt6-host-llvm21/bin/androiddeployqt')),
                '--input', str(configuration), '--output', str(destination),
                '--android-platform', 'android-35', '--aux-mode', '--verbose'], check=True)
# Keep the diagnostic fixture extracted but absent from Java's preload lists.
# QPluginLoader is its only explicit loaded owner during the opt-in control.
plugin_owner_enabled = args.app == 'qt-selftest' and (
    'SMOKE_ANDROID_PLUGIN_TLS_OWNER:BOOL=ON'
    in (args.build / 'CMakeCache.txt').read_text().splitlines())
if plugin_owner_enabled:
    probe = args.build / 'qt-selftest/tls-owner/liblongreach_tls_owner_probe.so'
    if not probe.is_file():
        raise FileNotFoundError(probe)
    shutil.copy2(probe, libraries / probe.name)
print(f'Deployed {args.app} from the generated Qt6 configuration')
