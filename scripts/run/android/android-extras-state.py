# SPDX-License-Identifier: GPL-3.0-or-later
"""Bind live service identities, natural exits and app-private AndroidExtras reports."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


HERE = Path(__file__).resolve().parent
exit_state = module('extras_process_exit', HERE / 'android-process-exit.py')
protocol = module('extras_protocol', HERE.parents[2] / 'scripts/tests/android/require-android-extras.py')
digest = exit_state.digest
read = lambda p: json.loads(p.read_text(encoding='utf-8-sig'))
text = lambda p: p.read_text(encoding='utf-8-sig')


def save(path, value):
    with path.open('x', encoding='utf-8', newline='\n') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')


def request(path):
    found = re.fullmatch(r'([1-9][0-9]*) ([0-9a-f]{32})\s*', text(path))
    if not found:
        raise ValueError('Invalid service rendezvous request')
    return {'pid': int(found[1]), 'nonce': found[2]}


def identity(path):
    value = text(path).strip()
    prefix, rest = value.rsplit(') ', 1)
    fields = rest.split()
    pid = prefix.split(' (', 1)[0]
    if not pid.isdigit() or len(fields) < 20 or not fields[19].isdigit() or fields[0] in ('Z', 'X', 'x'):
        raise ValueError('Service proc stat is not a live identity')
    return {'pid': int(pid), 'start_ticks': int(fields[19])}


def prefix(index):
    if type(index) is not int or index not in (0, 1):
        raise ValueError('Invalid service round')
    return f'extras-{index}'


def live_files(index):
    stem = prefix(index)
    return [stem + suffix for suffix in ('-live-request.stdout', '-live-stat-a.stdout',
                                         '-live-cmdline.stdout', '-live-stat-b.stdout')]


def parse_live(case, package, index, marker):
    if not re.fullmatch(r'BEGIN-[0-9a-f]{32}', marker):
        raise ValueError('Invalid service launch boundary')
    names = live_files(index)
    expected = request(case / names[0])
    before, after = identity(case / names[1]), identity(case / names[3])
    command = text(case / names[2]).rstrip('\x00\r\n ')
    if before != after or before['pid'] != expected['pid'] or command != package + ':longreach_extras':
        raise ValueError('Live service PID, birth identity or command changed')
    return dict(schema_version=1, round=index, package=package + ':longreach_extras',
                log_marker=marker, **expected, start_ticks=before['start_ticks'],
                files={name: digest(case / name) for name in names})


def observe(case, package, index, marker):
    value = parse_live(case, package, index, marker)
    save(case / (prefix(index) + '-live.json'), value)
    ack = case / f'extras-service-{index}-live-ack.txt'
    with ack.open('x', encoding='ascii') as stream:
        stream.write(value['nonce'] + '\n')
    return value


def parse_exit(case, package, index, final=False, receipt=None):
    stem = prefix(index)
    live = read(case / (stem + '-live.json'))
    if live != parse_live(case, package, index, live['log_marker']):
        raise ValueError('Live service observation changed after acknowledgement')
    if request(case / (stem + '-exit-request.stdout')) != {key: live[key] for key in ('pid', 'nonce')}:
        raise ValueError('Service completion belongs to another live process')
    names = live_files(index) + [stem + '-live.json', stem + '-exit-request.stdout',
                               f'extras-service-{index}-live-ack.txt']
    if text(case / names[-1]).strip() != live['nonce']:
        raise ValueError('Live service acknowledgement changed')
    lifecycles = []
    for sample in (0, 1):
        log_name = f'{stem}-exit-log-{sample}'
        raw_path = case / (log_name + '.stdout')
        ps_path = case / f'{stem}-exit-ps-{sample}.stdout'
        lifecycle = exit_state.lifecycle(exit_state.scoped(text(raw_path).splitlines(), live['log_marker']), live['package'])
        if (not lifecycle or lifecycle['process_id'] != live['pid'] or not lifecycle['death_line']
                or exit_state.present(text(ps_path).splitlines(), live['package'], live['pid'])):
            raise ValueError('Independent host service exit was not observed')
        lifecycles.append(lifecycle)
        names += [raw_path.name, ps_path.name]
        capture = case / (log_name + '-file-capture.json')
        if capture.exists(): names.append(capture.name)
        if final:
            exit_state.require_capture(case, receipt, raw_path, log_name, digest(capture) if capture.exists() else None)
    if lifecycles[0] != lifecycles[1]:
        raise ValueError('Service exit observations refer to different lifecycles')
    return dict(schema_version=1, round=index, package=live['package'], pid=live['pid'], nonce=live['nonce'],
                log_marker=live['log_marker'], start_ticks=live['start_ticks'], lifecycle=lifecycles[0],
                natural_exit=True, observations=2, observation_order='logcat-then-ps',
                files={name: digest(case / name) for name in names})


def finish(case, package, index):
    value = parse_exit(case, package, index)
    save(case / (prefix(index) + '-exit.json'), value)
    with (case / f'extras-service-{index}-exit-ack.txt').open('x', encoding='ascii') as stream:
        stream.write(value['nonce'] + '\n')
    return value


def seal(case, package):
    rows=[]
    for index in (0, 1):
        path = case / (prefix(index) + '-exit.json')
        if read(path) != parse_exit(case, package, index):
            raise ValueError('Service exit receipt changed')
        rows.append({'round': index, 'exit_sha256': digest(path)})
    value={'schema_version': 1, 'package': package, 'qualification': False, 'rounds': rows}
    save(case / 'extras-services.json', value)
    return value


def validate(case, package, receipt, final_run=None):
    path=case/'extras-services.json'; sealed=read(path)
    if (sealed.get('schema_version') != 1 or sealed.get('package') != package or sealed.get('qualification') is not False
            or receipt.get('extras_services_sha256') != digest(path)):
        raise ValueError('Missing or mismatched host service evidence')
    rows=protocol.validate(text(case/'files/selftest.stdout'))
    if read(case/'extras-0-live.json')['log_marker'] != receipt.get('log_marker'):
        raise ValueError('First service launch is outside the parent launch boundary')
    if read(case/'extras-1-live.json')['log_marker'] != text(case/'extras-round1-marker.txt').strip():
        raise ValueError('Second service launch boundary changed')
    if len(sealed.get('rounds', [])) != 2: raise ValueError('Expected two service exits')
    final_run=final_run or case
    final_path=final_run/'final-logcat.log'
    if receipt.get('final_logcat_sha256') != digest(final_path): raise ValueError('Final owned log is unbound')
    raw=text(final_path).splitlines()
    for index, row in enumerate(rows):
        path=case/(prefix(index)+'-exit.json'); value=read(path)
        if sealed['rounds'][index] != {'round':index,'exit_sha256':digest(path)} or value != parse_exit(case,package,index,True,receipt):
            raise ValueError('Service exit evidence changed after collection')
        if any(row[key] != value[key] for key in ('round','pid','nonce')): raise ValueError('Service stdout differs from observed host identity')
        for phase in ('live','exit'):
            ack=f'extras-service-{index}-{phase}-ack.txt'
            if text(case/ack).strip()!=row['nonce'] or (case/'files'/ack).read_bytes()!=(case/ack).read_bytes():
                raise ValueError('Service host acknowledgement was not delivered unchanged')
        service=case/'files'/f'extras-service-{row["pid"]}'
        if text(service/'selftest-result.txt').strip()!='0' or text(service/'on-destroy.txt').strip()!=str(row['pid']):
            raise ValueError('Missing service native0 or onDestroy receipt')
        expected=f'ANDROID_EXTRAS_SERVICE: bound pid={row["pid"]} nonce={row["nonce"]}'
        lines=text(service/'selftest.stdout').splitlines()
        observations=[line for line in lines if re.fullmatch(r'OBSERVE: extras/service-transaction code=[0-9]+ flags=[0-9]+',line)]
        if observations:
            modes=[tuple(map(int,re.findall(r'[0-9]+',line))) for line in observations]
            if len(modes)!=8 or any(code!=0x5145 or flags & 1 for code,flags in modes):
                raise ValueError('Service transaction observations differ from eight synchronous calls')
            lines=[line for line in lines if line not in observations]
        if lines != [expected, 'ANDROID_EXTRAS_SERVICE: finished=0 binds=1 calls=8 callbacks=8 errors=0']:
            raise ValueError('Service native transcript does not match this binding')
        scoped=exit_state.scoped(raw,value['log_marker'])
        if index==0:
            next_marker=read(case/'extras-1-live.json')['log_marker']
            indices=[n for n,line in enumerate(scoped) if re.fullmatch(r'^[VDIWEF]/LongreachCase\s*\(\s*\d+\):\s*'+next_marker+r'\s*',line)]
            if len(indices)!=1: raise ValueError('Missing second service launch boundary')
            scoped=scoped[:indices[0]]
        if exit_state.lifecycle(scoped,value['package']) != value['lifecycle']:
            raise ValueError('Final owned log changed the service exit lifecycle')
    return {'service_processes':2,'service_exits_confirmed':True,'extras_services_sha256':digest(case/'extras-services.json')}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=('observe','exit','seal','validate'))
    parser.add_argument('--case',type=Path,required=True);parser.add_argument('--package',required=True)
    parser.add_argument('--round',type=int,choices=(0,1));parser.add_argument('--marker');parser.add_argument('--receipt',type=Path);parser.add_argument('--final-run',type=Path)
    args=parser.parse_args()
    try:
        if args.action=='observe':observe(args.case,args.package,args.round,args.marker)
        elif args.action=='exit':finish(args.case,args.package,args.round)
        elif args.action=='seal':seal(args.case,args.package)
        else:validate(args.case,args.package,read(args.receipt),args.final_run)
    except (OSError,ValueError,KeyError,TypeError,RuntimeError) as error:parser.exit(1,'AndroidExtras host evidence refused: '+str(error)+'\n')
    print('AndroidExtras host evidence '+args.action+': PASS; no full-suite qualification')


if __name__=='__main__':main()
