#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Execute patched Qt6 TTS Java and real QtCore callback queue contracts.

Android/JNI interfaces are recording substitutes. No Android engine or audio
is exercised. With --qmake use a Qt6 host installation for native contracts.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

UPSTREAM_HASHES = {
    'QtTextToSpeech.java': '4f0316a4c03423d14832dd35ed6adb8a36225df74b73abe6754cc474d64716a8',
    'qtexttospeech_android.cpp': '9f8d425af9f692003ecf6187a4d42485d845856590e639c38ebf0fb2be7c6960',
    'qtexttospeech_android.h': '2a18f7f07c7a425dad9a9303acd598d08127ef991f264a5a5ecfb69bac14a83f',
}
JAVA = 'qtspeech/src/plugins/tts/android/jar/src/org/qtproject/qt/android/speech/QtTextToSpeech.java'
NATIVE = 'qtspeech/src/plugins/tts/android/src/'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--qmake')
    parser.add_argument('--jobs', type=int, default=2)
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    root = here.parents[2]
    fixtures = here / 'fixtures/qt6-tts'
    spec = importlib.util.spec_from_file_location('qt5_tts_contracts', here / 'qt5-android-tts.py')
    shared = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(shared)
    run = shared.run
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    prepared = output / 'source'
    for name, expected in UPSTREAM_HASHES.items():
        data = (fixtures / name).read_bytes().split(b'\n', 1)[1]
        if hashlib.sha256(data).hexdigest() != expected:
            raise RuntimeError(f'Upstream fixture changed: {name}')
        path = prepared / (JAVA if name.endswith('.java') else NATIVE + name)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    patch_hashes = {}
    for name in ('08-android-api21-legacy-tts.patch',
                 '12-android-tts-callback-registration.patch',
                 '13-android-tts-error-state.patch',
                 '14-android-tts-request-generation.patch',
                 '15-android-tts-input-length.patch'):
        patch = root / 'patches/qt6/android' / name
        patch_hashes[name] = hashlib.sha256(patch.read_bytes()).hexdigest()
        environment = dict(os.environ, GIT_CEILING_DIRECTORIES=str(output))
        for arguments in (['--check'], []):
            subprocess.run(['git', 'apply', *arguments, str(patch)], cwd=prepared,
                           env=environment, check=True, capture_output=True)
    java_root = output / 'java'
    adapter = java_root / 'org/qtproject/qt/android/speech/QtTextToSpeech.java'
    adapter.parent.mkdir(parents=True)
    shutil.copyfile(prepared / JAVA, adapter)
    shutil.copyfile(fixtures / 'TtsGenerationFixture.java', adapter.with_name('TtsGenerationFixture.java'))
    stubs = dict(shared.ANDROID_STUBS)
    stubs.update(json.loads((fixtures / 'android-stubs.json').read_text()))
    for name, body in stubs.items():
        if name == 'SPDX-License-Identifier':
            continue
        path = java_root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(body + '\n', encoding='utf-8')
    javac, java, javap = (shutil.which(name) for name in ('javac', 'java', 'javap'))
    if not all((javac, java, javap)):
        raise RuntimeError('JDK javac, java and javap are required')
    classes = output / 'classes'
    classes.mkdir()
    run([javac, '-J-Xmx128m', '-source', '8', '-target', '8', '-d', str(classes),
         *map(str, sorted(java_root.rglob('*.java')))], output, output / 'javac.log')
    print(run([java, '-Xmx64m', '-cp', str(classes),
               'org.qtproject.qt.android.speech.TtsGenerationFixture'], output,
              output / 'java.stdout'), end='')
    descriptors = run([javap, '-p', '-s', '-classpath', str(classes),
                       'org.qtproject.qt.android.speech.QtTextToSpeech'], output,
                      output / 'jni-signatures.txt').splitlines()
    actual = {}
    for index, line in enumerate(descriptors):
        match = re.search(r'native void (\w+)\(', line)
        if match:
            actual[match[1]] = descriptors[index + 1].strip().removeprefix('descriptor: ')
    source = (prepared / NATIVE / 'qtexttospeech_android.cpp').read_text()
    expected = {}
    types = {'jlong': 'J', 'jint': 'I', 'int': 'I', 'jbyteArray': '[B'}
    for name in actual:
        signature = re.search(r'static void ' + name + r'\(([^)]*)\)', source)
        if not signature:
            raise RuntimeError(f'Missing C++ JNI callback: {name}')
        expected[name] = '(' + ''.join(types[re.search(r'\b(jlong|jint|int|jbyteArray)\b', p)[1]]
                                      for p in signature[1].split(',')[2:]) + ')V'
    if len(actual) != 7 or actual != expected:
        raise RuntimeError(f'Java/C++ callback descriptor mismatch: {actual} != {expected}')
    native_executed = False
    if args.qmake:
        native = output / 'native'
        native.mkdir()
        first = source.index('static jclass g_qtSpeechClass')
        jni = source.index('Q_DECL_EXPORT jint JNICALL JNI_OnLoad')
        constructor = source.index('QTextToSpeechEngineAndroid::QTextToSpeechEngineAndroid')
        capability = source.index('QTextToSpeech::Capabilities QTextToSpeechEngineAndroid::capabilities()')
        generation = source.index('bool QTextToSpeechEngineAndroid::acceptRequestGeneration')
        end = source.index("// Android API's pitch")
        implementation = source[first:jni] + source[constructor:capability] + source[generation:end]
        fixture = (fixtures / 'native.cpp').read_text()
        if fixture.count('// ENGINE_IMPLEMENTATION') != 1:
            raise RuntimeError('Native fixture marker changed')
        (native / 'native.cpp').write_text(fixture.replace('// ENGINE_IMPLEMENTATION', implementation))
        (native / 'test.pro').write_text('QT = core\nCONFIG += console c++17\nCONFIG -= app_bundle\n'
                                        'TARGET = tts-contract\nSOURCES += native.cpp\n')
        run([args.qmake, 'test.pro'], native, output / 'qmake.log')
        run(['make', '-j' + str(args.jobs)], native, output / 'native-build.log')
        print(run([str(native / 'tts-contract')], native, output / 'native.stdout'), end='')
        native_executed = True
    receipt = {
        'scope': 'host Qt6 TTS adapter contracts', 'android_guest_qualified': False,
        'android_tts_engine_executed': False, 'audible_speech_qualified': False,
        'actual_java_adapter_executed': True, 'actual_cpp_state_methods_executed': native_executed,
        'native_substitutes': 'Android/JNI calls, audio format and speech base; real Qt6 Core with --qmake',
        'native_descriptors': actual, 'patches': patch_hashes,
        'prepared_sources': {str(p.relative_to(prepared)): hashlib.sha256(p.read_bytes()).hexdigest()
                             for p in sorted(prepared.rglob('*')) if p.is_file()},
    }
    (output / 'result.json').write_text(json.dumps(receipt, sort_keys=True, indent=2) + '\n')


if __name__ == '__main__':
    main()
