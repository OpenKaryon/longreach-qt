#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Execute pinned Qt5 ownership methods with recording JNI/Android boundaries."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

INPUTS = {
    'qandroidserviceconnection.cpp': ('qtandroidextras/src/androidextras/android/qandroidserviceconnection.cpp',
        '40f42ed9c8f9a5154f9864aa07e79a00ce5991755f36cdab7ff170bc6e769969'),
    'QtAndroidServiceConnection.java': ('qtandroidextras/src/jar/src/org/qtproject/qt5/android/extras/QtAndroidServiceConnection.java',
        '9b864f6eb1b836c8411668e9fb26ed4aea4f8fb76ae95f292f47c0a827535a0d'),
}

CPP_HEADER = r'''
#pragma once
#include <memory>
#include <stdexcept>
#include <string>
#define QT_BEGIN_NAMESPACE
#define QT_END_NAMESPACE
using jlong=long long;
using jclass=void*;
using jmethodID=void*;
struct Data { jlong id=0; bool valid=true,managed=true; int calls=0; };
inline void require(bool ok,const char* why){if(!ok)throw std::runtime_error(why);}
class QAndroidJniObject {
public:
 std::shared_ptr<Data> data=std::make_shared<Data>();
 QAndroidJniObject()=default;
 QAndroidJniObject(const char*,const char*,jlong id){data->id=id;}
 bool isValid()const{return data->valid;}
 void* object()const{return data.get();}
 template<class T> void callMethod(const char* name,const char*,jlong value)const {
  require(data->valid&&data->managed,"Unexpected method on foreign/invalid Java handle");
  require(std::string(name)=="setId","Unexpected JNI method");
  ++data->calls;data->id=value;
 }
};
struct Env {
 bool IsInstanceOf(void* object,jclass){return static_cast<Data*>(object)->managed;}
 jmethodID GetMethodID(jclass,const char* name,const char* signature){
  require(std::string(name)=="clearId"&&std::string(signature)=="(J)V","Unexpected owner method");return reinterpret_cast<void*>(2);
 }
 void CallNonvirtualVoidMethod(void* object,jclass clazz,jmethodID method,jlong expected){
  require(clazz==reinterpret_cast<void*>(1)&&method==reinterpret_cast<void*>(2),"SDK class identity lost");
  auto* data=static_cast<Data*>(object);require(data->managed,"Foreign Java method invoked");
  ++data->calls;if(data->id==expected)data->id=0;
 }
};
class QAndroidJniEnvironment {
 Env env;
public:
 Env* operator->(){return &env;}
 jclass findClass(const char* name){require(std::string(name)=="org/qtproject/qt5/android/extras/QtAndroidServiceConnection","Wrong SDK class");return reinterpret_cast<void*>(1);}
};
class QAndroidJniExceptionCleaner {};
class QAndroidServiceConnection {
 QAndroidJniObject m_handle;
public:
 QAndroidServiceConnection();
 explicit QAndroidServiceConnection(const QAndroidJniObject&);
 virtual ~QAndroidServiceConnection();
 QAndroidJniObject handle()const;
};
'''

CPP_TEST = r'''
#include "qandroidserviceconnection.h"
#include <iostream>
int main(){try {
 QAndroidJniObject retained;
 {QAndroidServiceConnection owner;retained=owner.handle();require(retained.data->id!=0,"Default owner was not registered");}
 require(retained.data->id==0,"Destroyed native owner remains registered in retained Java handle");
 require(retained.data->calls==1,"Owner cleanup must occur once");
 QAndroidJniObject other;other.data->id=101;
 {QAndroidServiceConnection borrowed(other);}
 require(other.data->id==101,"Borrowed SDK Java handle lost another native owner");
 QAndroidJniObject foreign;foreign.data->managed=false;foreign.data->id=7;
 {QAndroidServiceConnection borrowed(foreign);}
 require(foreign.data->id==7&&foreign.data->calls==0,"Foreign Java connection was modified");
 QAndroidJniObject invalid;invalid.data->valid=false;
 {QAndroidServiceConnection borrowed(invalid);}
 require(invalid.data->calls==0,"Invalid Java handle was used");
 std::cout<<"PASS actual C++ constructors/destructor: owned detach, borrowed/foreign/invalid preservation\n";
 }catch(const std::exception& error){std::cerr<<error.what()<<"\n";return 1;}
}
'''

JAVA_TEST = r'''
package org.qtproject.qt5.android.extras;
import android.content.ComponentName;
class QtNative {
 static long observed=-1;
 static void onServiceConnected(long id,String name,android.os.IBinder binder){observed=id;}
 static void onServiceDisconnected(long id,String name){observed=id;}
}
public class OwnerFixture {
 static void require(boolean ok,String why){if(!ok)throw new AssertionError(why);}
 public static void main(String[] args){
  QtAndroidServiceConnection receiver=new QtAndroidServiceConnection(41);
  ComponentName name=new ComponentName();
  receiver.clearId(40);receiver.onServiceConnected(name,null);
  require(QtNative.observed==41,"wrong owner cleared connection");
  receiver.clearId(41);receiver.onServiceConnected(name,null);
  require(QtNative.observed==0,"connected callback retained deleted owner id");
  receiver.setId(88);receiver.clearId(41);receiver.onServiceDisconnected(name);
  require(QtNative.observed==88,"replacement owner was cleared");
  receiver.clearId(88);receiver.onServiceDisconnected(name);
  require(QtNative.observed==0,"disconnected callback retained deleted owner id");
  System.out.println("PASS actual Java owner-checked clear and callback ids; native dispatch is recorded only");
 }
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--baseline', action='store_true', help='Original ownership methods; expected assertion failure')
    parser.add_argument('--compiler', default='g++')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[3]
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    prepared = output / 'source'
    fixtures = Path(__file__).parent / 'fixtures/qt5-service-connection'
    for name, (relative, expected) in INPUTS.items():
        data = (fixtures / name).read_bytes().split(b'\n', 1)[1]
        if hashlib.sha256(data).hexdigest() != expected:
            raise ValueError('Upstream ownership input changed: ' + name)
        path = prepared / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    patch = repo / 'patches/qt5/android/32-service-connection-owner-cleanup.patch'
    if not args.baseline:
        environment = dict(os.environ, GIT_CEILING_DIRECTORIES=str(output))
        for options in (['--check'], []):
            subprocess.run(['git', 'apply', *options, str(patch)], cwd=prepared, env=environment,
                           check=True, capture_output=True)
    include = output / 'include'
    include.mkdir()
    (include / 'qandroidserviceconnection.h').write_text(CPP_HEADER)
    for name in ('qandroidjniobject.h', 'QAndroidJniEnvironment'):
        (include / name).write_text('#include "qandroidserviceconnection.h"\n')
    cpp = output / 'ownership.cpp'
    cpp.write_text(CPP_TEST)
    native = output / ('ownership.exe' if os.name == 'nt' else 'ownership')
    commands = [([args.compiler, '-std=c++17', '-I', str(include), str(cpp),
                  str(prepared / INPUTS['qandroidserviceconnection.cpp'][0]), '-o', str(native)], 'compile.log'),
                ([str(native)], 'cpp.stdout')]
    java = output / 'java'
    java.mkdir()
    (java / 'QtAndroidServiceConnection.java').write_bytes((prepared / INPUTS['QtAndroidServiceConnection.java'][0]).read_bytes())
    (java / 'OwnerFixture.java').write_text(JAVA_TEST)
    stubs = {
        'android/content/ComponentName.java': 'package android.content;public class ComponentName{public String flattenToString(){return "fixture/service";}}',
        'android/content/ServiceConnection.java': 'package android.content;public interface ServiceConnection{void onServiceConnected(ComponentName name,android.os.IBinder binder);void onServiceDisconnected(ComponentName name);}',
        'android/os/IBinder.java': 'package android.os;public interface IBinder{}',
    }
    for name, content in stubs.items():
        path = java / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content + '\n')
    classes = output / 'classes'
    classes.mkdir()
    javac, runtime = shutil.which('javac'), shutil.which('java')
    if not javac or not runtime:
        raise RuntimeError('JDK javac/java required')
    commands += [([javac, '-J-Xmx128m', '-source', '8', '-target', '8', '-d', str(classes),
                   *map(str, java.rglob('*.java'))], 'javac.log'),
                 ([runtime, '-Xmx64m', '-cp', str(classes), 'org.qtproject.qt5.android.extras.OwnerFixture'], 'java.stdout')]
    for command, log in commands:
        run = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60,
                             creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        (output / log).write_text(run.stdout)
        if run.returncode:
            raise RuntimeError(f'{command[0]} exited {run.returncode}; see {output / log}')
    receipt = {'scope': 'Host actual Qt5 ownership C++/Java methods with recorded JNI/Android boundaries',
               'android_guest_qualified': False, 'actual_native_abi_tested': False,
               'upstream_inputs': {name: expected for name, (_, expected) in INPUTS.items()},
               'patch_sha256': hashlib.sha256(patch.read_bytes()).hexdigest(),
               'limits': ['Fresh SDK and real JNI retained-handle control still required',
                          'No arbitrary concurrent derived-object destruction guarantee']}
    (output / 'result.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print((output / 'cpp.stdout').read_text(), end='')
    print((output / 'java.stdout').read_text(), end='')


if __name__ == '__main__':
    main()
