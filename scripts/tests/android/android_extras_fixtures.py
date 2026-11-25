# SPDX-License-Identifier: GPL-3.0-or-later
"""Synthetic observer boundaries only; never an Android behavior claim."""
import importlib.util
import json
from pathlib import Path
import shutil

ROOT=Path(__file__).resolve().parents[3]
spec=importlib.util.spec_from_file_location('extras_fixture_state',ROOT/'scripts/run/android/android-extras-state.py')
state=importlib.util.module_from_spec(spec);spec.loader.exec_module(state)
PACKAGE='org.longreachqt.examples.qtselftest'
MARKERS=('BEGIN-'+'a'*32,'BEGIN-'+'b'*32)
NONCES=('c'*32,'d'*32)


def transcript():
    return '''ANDROID_EXTRAS: context-and-ui-thread=PASS
ANDROID_EXTRAS: intent-values=PASS
ANDROID_EXTRAS: activity-result=PASS
ANDROID_EXTRAS: service-round=0 pid=3010 nonce=cccccccccccccccccccccccccccccccc calls=8 callbacks=8 native_result=0 exited=1
ANDROID_EXTRAS: cross-process-service=PASS
ANDROID_EXTRAS: parcel-binder-echo=PASS
ANDROID_EXTRAS: reverse-binder-callbacks=PASS
ANDROID_EXTRAS: service-unbind-exit=PASS
ANDROID_EXTRAS: service-round=1 pid=3011 nonce=dddddddddddddddddddddddddddddddd calls=8 callbacks=8 native_result=0 exited=1
ANDROID_EXTRAS: service-restart-exit=PASS
ANDROID_EXTRAS: summary=PASS checks=8 service_processes=2 transactions=16 callbacks=16
'''


def service_log(index, marker=None):
    number=3010+index;package=PACKAGE+':longreach_extras'
    return (f'I/LongreachCase( 77): {marker or MARKERS[index]}\n'
        f'I/ActivityManager( 100): Start proc {number}:{package}/u0a20 for service\n'
        f'I/ActivityManager( 100): Process {package} (pid {number}) has died.\n')


def live_inputs(case,index,marker=None):
    case.mkdir(parents=True,exist_ok=True);stem=f'extras-{index}';number=3010+index
    (case/(stem+'-live-request.stdout')).write_text(f'{number} {NONCES[index]}\n')
    # Linux stat field22 is starttime, independently fixed at800/801 here.
    stat=f'{number} (app_process) S 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 {800+index} 0 0\n'
    for suffix in ('a','b'):(case/(stem+'-live-stat-'+suffix+'.stdout')).write_text(stat)
    (case/(stem+'-live-cmdline.stdout')).write_bytes((PACKAGE+':longreach_extras\x00').encode())
    return marker or MARKERS[index]


def exit_inputs(case,index,marker=None):
    stem=f'extras-{index}';number=3010+index
    (case/(stem+'-exit-request.stdout')).write_text(f'{number} {NONCES[index]}\n')
    for sample in (0,1):
        (case/f'{stem}-exit-log-{sample}.stdout').write_text(service_log(index,marker))
        (case/f'{stem}-exit-ps-{sample}.stdout').write_text('USER PID PPID NAME\nroot 1 0 /init\nu0a20 1234 1 '+PACKAGE+'\n')


def prepare(case,first_marker=None):
    case=Path(case);case.mkdir(parents=True,exist_ok=True)
    first_marker=first_marker or MARKERS[0]
    (case/'files').mkdir(exist_ok=True)
    for index in (0,1):
        marker=first_marker if index==0 else MARKERS[1]
        live_inputs(case,index,marker);state.observe(case,PACKAGE,index,marker)
        exit_inputs(case,index,marker);state.finish(case,PACKAGE,index)
        for phase in ('live','exit'):
            name=f'extras-service-{index}-{phase}-ack.txt';shutil.copyfile(case/name,case/'files'/name)
        service=case/'files'/f'extras-service-{3010+index}';service.mkdir()
        (service/'selftest-result.txt').write_text('0\n')
        (service/'on-destroy.txt').write_text(str(3010+index)+'\n')
        (service/'selftest.stdout').write_text(f'ANDROID_EXTRAS_SERVICE: bound pid={3010+index} nonce={NONCES[index]}\n'
            'ANDROID_EXTRAS_SERVICE: finished=0 binds=1 calls=8 callbacks=8 errors=0\n')
    state.seal(case,PACKAGE)
    (case/'extras-round1-marker.txt').write_text(MARKERS[1]+'\n')
    (case/'files/selftest.stdout').write_text(transcript())
    final=service_log(0,first_marker)+service_log(1)
    (case/'final-logcat.log').write_text(final)
    return {'log_marker':first_marker,'extras_services_sha256':state.digest(case/'extras-services.json'),
            'final_logcat_sha256':state.digest(case/'final-logcat.log')}
