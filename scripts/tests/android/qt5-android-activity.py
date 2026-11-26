#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Execute actual Qt5 Activity shutdown methods with recorded Android boundaries.

No guest, native Qt engine, process cleanup or lifecycle qualification is claimed.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

HASHES = {
    'QtNative.java': 'e9e144196fbdd3fd7e513e0875e8a422221c64d8dcf536d2272b87efa459cdc1',
    'QtActivityDelegate.java': 'bc1ac007bd1b2c76baa1677457982c0251a5700b907d9b850005242729b3b128',
}
PREFIX = 'qtbase/src/android/jar/src/org/qtproject/qt5/android/'


def method(source, signature):
    start = source.index(signature)
    first = source.index('{', start)
    depth = 1
    end = first + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


FIXTURE = r'''
package org.qtproject.qt5.android;
import java.util.*;
import android.os.*;
class Boundary {
    static boolean ui;
    static final List<String> events=new ArrayList<String>();
    static void require(boolean value,String why){if(!value)throw new AssertionError(why+": "+events);}
    static void event(String value){require(ui,"cleanup must run on UI delivery");events.add(value);}
    static void exit(int code){event("system-exit:"+code);}
    static void onUi(Runnable action){ui=true;try{action.run();}finally{ui=false;}}
}
class Activity {
    boolean finishing;
    void finish(){Boundary.event("activity-finish");finishing=true;}
    boolean isFinishing(){return finishing;}
}
class Service {void stopSelf(){Boundary.event("service-stop");}}
class QtThread {void exit(){Boundary.event("qtthread-exit");}}
class QtNative {
    static Activity m_activity;
    static Service m_service;
    static QtActivityDelegate m_activityDelegate;
    static boolean m_activityPaused,m_started;
    static final Object m_mainActivityMutex=new Object();
    static final List<Runnable> m_lostActions=new ArrayList<Runnable>();
    static final QtThread m_qtThread=new QtThread();
    static void quitQtAndroidPlugin(){Boundary.event("plugin-stop");}
    static void terminateQt(){Boundary.event("native-terminate");}
    static void setActivity(Activity activity,QtActivityDelegate delegate){Boundary.event("native-clear");m_activity=activity;m_activityDelegate=delegate;}
    // NATIVE_METHODS
}
class QtActivityDelegate {
    boolean m_quitApp=true,m_applicationTerminating;
    // DELEGATE_METHODS
}
public class ActivityQuitFixture {
    static void reset(int api,boolean paused){Build.VERSION.SDK_INT=api;Boundary.events.clear();Looper.queue.clear();QtNative.m_lostActions.clear();QtNative.m_activity=new Activity();QtNative.m_activityDelegate=new QtActivityDelegate();QtNative.m_service=null;QtNative.m_activityPaused=paused;QtNative.m_started=true;}
    static void delivered(){Boundary.onUi(new Runnable(){public void run(){while(!Looper.queue.isEmpty())Looper.queue.remove(0).run();}});}
    public static void main(String[] ignored){
        List<String> complete=Arrays.asList("plugin-stop","activity-finish","native-terminate","native-clear","qtthread-exit","system-exit:0");
        for(int api:new int[]{10,21}){
            reset(api,false);final QtActivityDelegate finishing=QtNative.m_activityDelegate;
            QtNative.quitApp();Boundary.require(Boundary.events.isEmpty(),"native caller must not perform UI cleanup inline");delivered();
            Boundary.require(Boundary.events.equals(complete),"API"+api+" main return must complete existing cleanup without onDestroy");
            Boundary.onUi(new Runnable(){public void run(){finishing.onDestroy();}});
            Boundary.require(Boundary.events.equals(complete),"late onDestroy must not clean up twice onAPI"+api);
        }
        System.out.println("PASS API10/API21 explicit main return, UI delivery and late callback idempotence");
        for(int api:new int[]{11,20,22,35}){
            reset(api,false);final QtActivityDelegate modern=QtNative.m_activityDelegate;
            QtNative.quitApp();delivered();Boundary.require(Boundary.events.equals(Arrays.asList("plugin-stop","activity-finish")),"other API lifecycle must retain onDestroy boundary");
            Boundary.onUi(new Runnable(){public void run(){modern.onDestroy();}});Boundary.require(Boundary.events.equals(complete),"other API cleanup order");
        }
        System.out.println("PASS API11/API20/API22/API35 existing onDestroy cleanup ordering");
        reset(10,false);final QtActivityDelegate retained=QtNative.m_activityDelegate;retained.m_quitApp=false;
        Boundary.onUi(new Runnable(){public void run(){retained.onDestroy();}});Boundary.require(Boundary.events.isEmpty(),"configuration retention must not terminate native app");
        System.out.println("PASS retained configuration callback");
        for(int api:new int[]{10,21}){
            reset(api,true);QtNative.quitApp();delivered();Boundary.require(Boundary.events.isEmpty()&&QtNative.m_lostActions.size()==1,"paused-action path remains separately deferred, not qualified by this fix");
            reset(api,false);QtNative.m_activity=null;QtNative.m_activityDelegate=null;QtNative.m_service=new Service();QtNative.quitApp();delivered();
            Boundary.require(Boundary.events.isEmpty()&&QtNative.m_lostActions.size()==1,"service-only dispatch unchanged");
        }
        System.out.println("PASS explicit paused/service scope boundaries; no Android guest claim");
    }
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--baseline', action='store_true', help='Execute original methods; expected legacy regression fails')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[3]
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    prepared = output / 'source'
    for name, expected in HASHES.items():
        data = (Path(__file__).parent / 'fixtures/qt5-activity' / name).read_bytes().split(b'\n', 1)[1]
        if hashlib.sha256(data).hexdigest() != expected:
            raise ValueError('Upstream Activity fixture changed: ' + name)
        path = prepared / (PREFIX + name)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    patches = ['02-api10-java.patch', '19-api10-touch-events.patch']
    if not args.baseline:
        patches.append('31-api10-main-return-shutdown.patch')
    environment = dict(os.environ, GIT_CEILING_DIRECTORIES=str(output))
    patch_hashes = {}
    for name in patches:
        path = repo / 'patches/qt5/android' / name
        patch_hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()
        options = ['--include=' + PREFIX + n for n in HASHES]
        subprocess.run(['git', 'apply', '--check', *options, str(path)], cwd=prepared, env=environment, check=True, capture_output=True)
        subprocess.run(['git', 'apply', *options, str(path)], cwd=prepared, env=environment, check=True, capture_output=True)
    native = (prepared / (PREFIX + 'QtNative.java')).read_text()
    delegate = (prepared / (PREFIX + 'QtActivityDelegate.java')).read_text()
    methods = {
        'dispatch': method(native, 'private static void runAction(Runnable action)'),
        'quit': method(native, 'public static void quitApp()'),
        'destroy': method(delegate, 'public void onDestroy()'),
    }
    if not args.baseline:
        methods['terminate'] = method(delegate, 'public void terminateApplication()')
    text = FIXTURE.replace('// NATIVE_METHODS', methods['dispatch'] + '\n' + methods['quit'])
    # System.exit is the host boundary; executing it would exit before assertions.
    text = text.replace('// DELEGATE_METHODS', (methods['destroy'] + '\n' + methods.get('terminate', '')).replace('System.exit(0)', 'Boundary.exit(0)'))
    java = output / 'java'
    java.mkdir()
    (java / 'ActivityQuitFixture.java').write_text(text)
    stubs = {
        'android/os/Build.java': 'package android.os;public class Build{public static class VERSION{public static int SDK_INT;}}',
        'android/os/Looper.java': 'package android.os;import java.util.*;public class Looper{public static final List<Runnable> queue=new ArrayList<Runnable>();public static Looper getMainLooper(){return new Looper();}}',
        'android/os/Handler.java': 'package android.os;public class Handler{public Handler(Looper loop){}public boolean post(Runnable action){Looper.queue.add(action);return true;}}',
    }
    for name, body in stubs.items():
        path = java / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(body + '\n')
    classes = output / 'classes'
    classes.mkdir()
    javac, runtime = shutil.which('javac'), shutil.which('java')
    if not javac or not runtime:
        raise RuntimeError('JDK javac/java required')
    commands = [([javac, '-J-Xmx128m', '-source', '8', '-target', '8', '-d', str(classes), *map(str, java.rglob('*.java'))], 'javac.log'),
                ([runtime, '-Xmx64m', '-cp', str(classes), 'org.qtproject.qt5.android.ActivityQuitFixture'], 'java.stdout')]
    for command, log in commands:
        run = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60,
                             creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        (output / log).write_text(run.stdout)
        if run.returncode:
            raise RuntimeError(f'{command[0]} exited {run.returncode}; see {output / log}')
    receipt = {'scope': 'host actual Qt5 Java main-return shutdown methods with recording Android/native boundaries',
               'android_guest_qualified': False, 'actual_native_cleanup_executed': False,
               'patches': patch_hashes, 'production_method_sha256': {n: hashlib.sha256(v.encode()).hexdigest() for n, v in methods.items()},
               'limits': ['Paused action delivery and physical lifecycle are not qualified', 'Real fresh SDK/APK/guest exit checks remain required']}
    (output / 'result.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print((output / 'java.stdout').read_text(), end='')


if __name__ == '__main__':
    main()
