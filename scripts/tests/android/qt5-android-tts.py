#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Execute patched Qt5 speech adapter contracts (host only, not Android audio).

With --qmake, also execute production dispatch/state/lifetime methods against
real QtCore queued delivery. JNI/Android calls and the speech base are replaced.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

UPSTREAM_HASHES = {'QtTextToSpeech.java': '66960bb2649cacd2e8a04b7c287b762d8b3ee1d6717cdae106079746b8f03de4',
 'qtexttospeech_android.cpp': '016505de9f946cc3c26e9f74c6b2d2e845c95c4d20bbab0618a3ed2fdaf84bd7',
 'qtexttospeech_android.h': '5fb54d0782383d50fa64157e1a1be6976d57b36701d097df7a8f2f719f028a56'}
ANDROID_STUBS = {'android/content/ContentResolver.java': 'package android.content; public class ContentResolver {}',
 'android/content/Context.java': 'package android.content; public class Context { public '
                                 'ContentResolver getContentResolver(){return new '
                                 'ContentResolver();} }',
 'android/os/Build.java': 'package android.os; public class Build { public static class VERSION { '
                          'public static int SDK_INT=10; } public static class VERSION_CODES { '
                          'public static final int LOLLIPOP=21; } }',
 'android/os/Bundle.java': 'package android.os; public class Bundle {}',
 'android/provider/Settings.java': 'package android.provider; public class Settings { public '
                                   'static class Secure { public static final String '
                                   'TTS_DEFAULT_PITCH="pitch",TTS_DEFAULT_RATE="rate"; public '
                                   'static String getString(android.content.ContentResolver '
                                   'r,String n){return null;} } }',
 'android/speech/tts/TextToSpeech.java': 'package android.speech.tts;\n'
                                         'import java.util.*;\n'
                                         'public class TextToSpeech {\n'
                                         ' public static final int '
                                         'SUCCESS=0,ERROR=-1,QUEUE_FLUSH=0,LANG_AVAILABLE=0,LANG_COUNTRY_AVAILABLE=1,LANG_COUNTRY_VAR_AVAILABLE=2,LANG_NOT_SUPPORTED=-2,LANG_MISSING_DATA=-1;\n'
                                         ' public static class Engine { public static final String '
                                         'KEY_PARAM_UTTERANCE_ID="utterance",KEY_PARAM_VOLUME="volume"; '
                                         '}\n'
                                         ' public interface OnInitListener { void onInit(int s); '
                                         '}\n'
                                         ' public interface OnUtteranceCompletedListener { void '
                                         'onUtteranceCompleted(String s); }\n'
                                         ' public static TextToSpeech last;\n'
                                         ' public OnUtteranceCompletedListener completed; public '
                                         'UtteranceProgressListener progress; public '
                                         'OnInitListener init;\n'
                                         ' public final List<String> ids=new ArrayList<String>(); '
                                         'public boolean throwOnSpeak=false; public boolean '
                                         'fast=false; public int result=SUCCESS;\n'
                                         ' public TextToSpeech(android.content.Context '
                                         'c,OnInitListener l){last=this;init=l;}\n'
                                         ' public int '
                                         'setOnUtteranceCompletedListener(OnUtteranceCompletedListener '
                                         'l){completed=l;return SUCCESS;}\n'
                                         ' public int '
                                         'setOnUtteranceProgressListener(UtteranceProgressListener '
                                         'l){progress=l;return SUCCESS;}\n'
                                         ' public int speak(String s,int q,HashMap<String,String> '
                                         'm){if(throwOnSpeak)throw new '
                                         'IllegalStateException("fixture");final String '
                                         'id=m.get(Engine.KEY_PARAM_UTTERANCE_ID);ids.add(id);if(fast '
                                         '&& result==SUCCESS) binder(new Runnable(){public void '
                                         'run(){completed.onUtteranceCompleted(id);}});return '
                                         'result;}\n'
                                         ' public static void binder(Runnable action){Thread t=new '
                                         'Thread(action,"fixture-Binder");t.start();try{t.join(3000);}catch(InterruptedException '
                                         'e){throw new RuntimeException(e);}if(t.isAlive())throw '
                                         'new RuntimeException("callback blocked");}\n'
                                         ' public void complete(final String id){binder(new '
                                         'Runnable(){public void '
                                         'run(){completed.onUtteranceCompleted(id);}});}\n'
                                         ' public int stop(){return SUCCESS;} public void '
                                         'shutdown(){}\n'
                                         ' public int setPitch(float x){return SUCCESS;} public '
                                         'int setSpeechRate(float x){return SUCCESS;} public int '
                                         'setLanguage(Locale l){return SUCCESS;}\n'
                                         ' public int isLanguageAvailable(Locale l){return '
                                         'LANG_COUNTRY_VAR_AVAILABLE;} public Set<Voice> '
                                         'getVoices(){return new HashSet<Voice>();}\n'
                                         ' public Set<Locale> getAvailableLanguages(){return new '
                                         'HashSet<Locale>();} public Locale getLanguage(){return '
                                         'Locale.US;}\n'
                                         ' public Voice getVoice(){return new Voice();} public int '
                                         'setVoice(Voice v){return SUCCESS;}\n'
                                         '}',
 'android/speech/tts/UtteranceProgressListener.java': 'package android.speech.tts; public abstract '
                                                      'class UtteranceProgressListener { public '
                                                      'abstract void onDone(String s); public '
                                                      'abstract void onError(String s); public '
                                                      'abstract void onStart(String s); }',
 'android/speech/tts/Voice.java': 'package android.speech.tts; public class Voice { public String '
                                  'getName(){return "fixture";} }',
 'android/util/Log.java': 'package android.util; public class Log { public static int w(String '
                          'a,String b){return 0;} public static int w(String a,String b,Throwable '
                          't){return 0;} }'}
JAVA = 'qtspeech/src/plugins/tts/android/jar/src/org/qtproject/qt5/android/speech/QtTextToSpeech.java'
NATIVE = 'qtspeech/src/plugins/tts/android/src/'


def run(command, cwd, log):
    result = subprocess.run(command, cwd=cwd, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=180,
                            creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    log.write_text(result.stdout, encoding='utf-8')
    if result.returncode:
        raise RuntimeError(f'{command[0]} exited {result.returncode}; see {log}')
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--qmake')
    parser.add_argument('--jobs', type=int, default=2)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    fixtures = Path(__file__).resolve().parent / 'fixtures/qt5-tts'
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
    patch_names = ('21-api10-text-to-speech.patch', '26-android-tts-voice-enumeration.patch',
                   '30-android-tts-utterance-generation.patch')
    patch_hashes = {}
    environment = dict(os.environ, GIT_CEILING_DIRECTORIES=str(output))
    for name in patch_names:
        patch = root / 'patches/qt5/android' / name
        patch_hashes[name] = hashlib.sha256(patch.read_bytes()).hexdigest()
        subprocess.run(['git', 'apply', '--check', str(patch)], cwd=prepared,
                       env=environment, check=True, capture_output=True)
        subprocess.run(['git', 'apply', str(patch)], cwd=prepared,
                       env=environment, check=True, capture_output=True)
    java_root = output / 'java'
    adapter = java_root / 'org/qtproject/qt5/android/speech/QtTextToSpeech.java'
    adapter.parent.mkdir(parents=True)
    shutil.copyfile(prepared / JAVA, adapter)
    shutil.copyfile(fixtures / 'TtsGenerationFixture.java', adapter.with_name('TtsGenerationFixture.java'))
    for name, body in ANDROID_STUBS.items():
        path = java_root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(body + '\n', encoding='utf-8')
    javac, java = shutil.which('javac'), shutil.which('java')
    if not javac or not java:
        raise RuntimeError('JDK javac and java are required')
    classes = output / 'classes'
    classes.mkdir()
    run([javac, '-J-Xmx128m', '-source', '8', '-target', '8', '-d', str(classes),
         *map(str, sorted(java_root.rglob('*.java')))], output, output / 'javac.log')
    print(run([java, '-Xmx64m', '-cp', str(classes),
               'org.qtproject.qt5.android.speech.TtsGenerationFixture'], output,
              output / 'java.stdout'), end='')
    native_executed = False
    if args.qmake:
        native = output / 'native'
        native.mkdir()
        source = (prepared / NATIVE / 'qtexttospeech_android.cpp').read_text()
        first = source.index('static jclass g_qtSpeechClass')
        jni = source.index('Q_DECL_EXPORT jint JNICALL JNI_OnLoad')
        constructor = source.index('QTextToSpeechEngineAndroid::QTextToSpeechEngineAndroid')
        end = source.index('double QTextToSpeechEngineAndroid::pitch()')
        implementation = source[first:jni] + source[constructor:end]
        fixture = (fixtures / 'native.cpp').read_text()
        (native / 'native.cpp').write_text(fixture.replace('// ENGINE_IMPLEMENTATION', implementation))
        shutil.copyfile(prepared / NATIVE / 'qandroidttsutterance_p.h', native / 'qandroidttsutterance_p.h')
        (native / 'test.pro').write_text('QT = core\nCONFIG += console c++17\nCONFIG -= app_bundle\n'
                                        'TARGET = tts-contract\nSOURCES += native.cpp\n')
        run([args.qmake, 'test.pro'], native, output / 'qmake.log')
        run(['make', '-j' + str(args.jobs)], native, output / 'native-build.log')
        print(run([str(native / 'tts-contract')], native, output / 'native.stdout'), end='')
        native_executed = True
    receipt = {
        'scope': 'host Qt5 TTS adapter contracts', 'android_guest_qualified': False,
        'android_tts_engine_executed': False, 'audible_speech_qualified': False,
        'actual_java_adapter_executed': True, 'actual_cpp_state_methods_executed': native_executed,
        'native_substitutes': 'Android/JNI calls and speech base; real QtCore only with --qmake',
        'patches': patch_hashes,
        'prepared_sources': {str(p.relative_to(prepared)): hashlib.sha256(p.read_bytes()).hexdigest()
                             for p in sorted(prepared.rglob('*')) if p.is_file()},
    }
    (output / 'result.json').write_text(json.dumps(receipt, sort_keys=True, indent=2) + '\n')


if __name__ == '__main__':
    main()
