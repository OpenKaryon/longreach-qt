# SPDX-License-Identifier: GPL-3.0-or-later
"""Build the shared Qt4 projects as JNI clients of an installed Android SDK."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--prefix', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--profiles', default=os.environ.get('QT4_EXAMPLE_PROFILES', ''))
args = parser.parse_args()
prefix = args.prefix
repo = Path('/repo')
runtime = Path('/opt/longreach-android' if os.environ['ANDROID_ABI'] == 'x86' else '/opt/longreach-android-api21')
cxx = runtime / 'bin/cxx'
work = Path('/work/qt4-android-' + os.environ['ANDROID_ABI']) / 'clients'
args.output.mkdir(parents=True, exist_ok=True)
work.mkdir(parents=True, exist_ok=True)
qmake = prefix / 'bin/qmake'
spec = prefix / 'mkspecs/android-longreach-clang'
modules = sorted((prefix / 'lib').glob('libQt*.a'))
if len(modules) != 14:
    raise RuntimeError('The installed Qt4 SDK must include all fourteen selected modules, including Qt3Support')
plugins = [prefix / 'plugins/platforms/libqminimal.a', prefix / 'plugins/imageformats/libqsvg.a']
qml_plugins = sorted((prefix / 'imports/Qt/labs').glob('*/libqml*.a'))
assert len(qml_plugins) == 4
for path in plugins:
    assert path.is_file(), path
libs = ['-Wl,--start-group'] + list(map(str, plugins + qml_plugins + modules)) + ['-Wl,--end-group', '-lEGL', '-lGLESv2', '-ldl']
records = []
link_inputs = hashlib.sha256((prefix / 'longreach-reports/sdk-static-elf.json').read_bytes()).hexdigest()
module = importlib.util.spec_from_file_location('qt4_cache', Path(__file__).with_name('cache-inputs.py'))
cache = importlib.util.module_from_spec(module)
module.loader.exec_module(cache)
compile_inputs = cache.fingerprint(cache.client_compile_inputs(prefix, runtime))


def write_if_changed(path, text):
    if not path.exists() or path.read_text() != text:
        path.write_text(text)

def command(arguments, directory):
    subprocess.run(list(map(str, arguments)), cwd=directory, check=True)

def build(profile, project, extra=(), definitions=()):
    directory = work / profile
    directory.mkdir(parents=True, exist_ok=True)
    options = ['TEMPLATE=lib', 'TARGET=' + profile, 'CONFIG+=dll release', 'CONFIG-=staticlib app_bundle',
               'QMAKE_CXXFLAGS+=-std=gnu++23 -fexperimental-library',
               'QMAKE_LFLAGS_SONAME=', 'QMAKE_LFLAGS+=-Wl,--exclude-libs,ALL,-soname,libdonut_probe.so',
               'LIBS+=' + ' '.join(libs)]
    if extra:
        options.append('SOURCES+=' + ' '.join(map(str, extra)))
    if definitions:
        options.append('DEFINES+=' + ' '.join(definitions))
    compile_key = cache.fingerprint([compile_inputs, options])
    saved_compile = directory / '.longreach-sdk-compile-inputs'
    if cache.needs_clean(saved_compile, compile_key) and (directory / 'Makefile').exists():
        command(['make', 'clean'], directory)
    command([qmake, '-spec', spec, project, '-after'] + options, directory)
    saved_inputs = directory / '.longreach-sdk-link-inputs'
    if not saved_inputs.exists() or saved_inputs.read_text().strip() != link_inputs:
        # A retained client cache may have newer output timestamps than a new
        # SDK's archives. Relink against their actual contents, retaining objects.
        for output in directory.glob('lib' + profile + '.so*'):
            output.unlink()
    command(['make', '-j2'], directory)
    write_if_changed(saved_inputs, link_inputs + '\n')
    write_if_changed(saved_compile, compile_key + '\n')
    source = directory / ('lib' + profile + '.so')
    target = args.output / (profile + '.so')
    shutil.copyfile(source, target)
    records.append({'profile': profile, 'native': target.name,
                    'sha256': hashlib.sha256(target.read_bytes()).hexdigest()})
    print('Built installed-SDK JNI client: ' + profile, flush=True)

applications = {
    'selftest': ('qt-selftest', '--qt-checks-only'),
    'widgets': ('widgets-gallery', '--selftest'),
    'graphics': ('graphics-gallery', '--selftest'),
    'painting': ('painting-lab', '--selftest'),
    'multimedia': ('multimedia-lab', '--selftest'),
    'gl': ('gl-heavy-gallery', '--selftest'),
    'qml': ('quick-qml-gallery', '--selftest'),
    'network': ('network-gui', '--selftest'),
}
expected_apps = {line.strip() for line in (repo / 'tests/expected-apps.txt').read_text().splitlines()
                 if line.strip() and not line.startswith('#') and line.strip() != 'smoke-runner'}
if {app for app, _ in applications.values()} != expected_apps:
    raise RuntimeError('Qt4 Android must build exactly all eight shared applications')
profiles = args.profiles.split(',') if args.profiles else ['bootstrap', 'strict', 'core'] + list(applications) + ['quick']
if len(set(profiles)) != len(profiles) or set(profiles) - (set(applications) | {'bootstrap', 'strict', 'core', 'quick'}):
    raise RuntimeError('Invalid or duplicate Qt4 example profile')
for profile in profiles:
    directory = work / profile
    directory.mkdir(parents=True, exist_ok=True)
    if profile in ('strict', 'bootstrap'):
        source = repo / 'tests/android-donut' / ('strict-jni.cpp' if profile == 'strict' else 'bootstrap.cpp')
        target = args.output / (profile + '.so')
        command([cxx, '-O2', '-std=c++23', '-fexperimental-library', '-shared',
                 '-Wl,-soname,libdonut_probe.so', '-I/repo/scripts/tests/qt6-llvm-probes', source, '-o', target], directory)
        records.append({'profile': profile, 'native': target.name, 'sha256': hashlib.sha256(target.read_bytes()).hexdigest()})
    elif profile == 'core':
        project = directory / 'core.pro'
        write_if_changed(project, 'QT = core\nSOURCES = /repo/tests/android-donut/qtcore-jni.cpp\n')
        build(profile, project)
    elif profile == 'quick':
        project = directory / 'quick.pro'
        write_if_changed(project, 'QT = core gui declarative script network sql xml svg opengl xmlpatterns\n'
                           'SOURCES = /repo/tests/android-donut/quick-jni.cpp /repo/tests/widgets-gallery/gallery.cpp\n'
                           'RESOURCES = /repo/tests/quick-qml-gallery/qml_qt4.qrc\n'
                           'DEFINES += QT_VERSION_MAJOR=4 QT_VERSION_MINOR=8\n')
        build(profile, project)
    else:
        app, option = applications[profile]
        bridge = directory / 'suite-wrapper.cpp'
        write_if_changed(bridge, '#include <QtPlugin>\nQ_IMPORT_PLUGIN(qsvg)\n'
                          '#define DONUT_SUITE_NAME "' + app + '"\n'
                          '#define DONUT_SUITE_OPTION "' + option + '"\n'
                          '#include "/repo/tests/android-donut/suite-jni.cpp"\n')
        project = repo / 'tests' / app / (app + '.pro')
        build(profile, project, [bridge], ['main=longreachSuiteMain', 'LONGREACH_DONUT_JNI'])
shutil.copyfile(runtime / 'lib/libc++_shared.so', args.output / 'libc++_shared.so')
manifest = {'schema_version': 2, 'abi': os.environ['ANDROID_ABI'],
            'api': 10 if os.environ['ANDROID_ABI'] == 'x86' else 21,
            'sdk_image_id': os.environ.get('LONGREACH_SDK_IMAGE_ID'),
            'runtime_sha256': hashlib.sha256((runtime / 'lib/libc++_shared.so').read_bytes()).hexdigest(),
            'clients': records}
(args.output / 'examples-build.json').write_text(json.dumps(manifest, indent=2) + '\n')
