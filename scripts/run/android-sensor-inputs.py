#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Apply ordinary, recorded sensor inputs to this run's owned emulator console."""
import argparse
import datetime
import hashlib
import json
import math
from pathlib import Path
import re
import socket

parser=argparse.ArgumentParser()
parser.add_argument('--directory',type=Path,required=True)
parser.add_argument('--request-sha256',required=True)
args=parser.parse_args()
directory=args.directory.resolve()
raw=(directory/'host-process-request.json').read_bytes()
request_sha=hashlib.sha256(raw).hexdigest()
request=json.loads(raw)
owner=json.loads((directory/'host-process-owner.json').read_text())
if (request_sha!=args.request_sha256 or owner['request_sha256']!=request_sha
        or owner['run_id']!=request['run_id'] or not owner['contained_before_start']):
    raise ValueError('Sensor inputs do not match the owned launch')
if any((directory/name).exists() for name in ('host-process-exit.json','host-process-stop.json')):
    raise ValueError('The owned emulator is no longer an active run')
arguments=request['arguments']
if arguments.count('-port')!=1:
    raise ValueError('Expected one explicit emulator console port')
port=int(arguments[arguments.index('-port')+1])
if port!=5580:
    raise ValueError('This API10 fixture requires the owned port5580')

record={'schema_version':1,'fixture':'nonparallel-compass-v1','host':'127.0.0.1','port':port,
        'host_process_request_sha256':request_sha,'applied_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'settings':[],'transcript':[]}
def reply(stream):
    lines=[]
    for _ in range(128):
        line=stream.readline(4097)
        if not line or len(line)>4096:
            raise ValueError('Incomplete emulator console response')
        text=line.decode('utf-8',errors='replace').strip()
        lines.append(text)
        if text=='OK': return lines
        if text.startswith('KO'): raise ValueError('Emulator console rejected command: '+text)
    raise ValueError('Emulator console response exceeded128 lines')

def command(stream,text):
    stream.write((text+'\n').encode('ascii'))
    stream.flush()
    lines=reply(stream)
    record['transcript'].append({'command':text,'response':lines})
    return lines

def vector(lines,name):
    found=[re.fullmatch(r'\s*'+re.escape(name)+r'\s*=\s*(.*?)\s*',line) for line in lines]
    found=[match.group(1) for match in found if match]
    if len(found)!=1: raise ValueError('Missing sensor readback for '+name+': '+repr(lines))
    values=[float(value) for value in found[0].split(':')]
    if len(values)!=3 or not all(math.isfinite(value) for value in values):
        raise ValueError('Invalid sensor vector: '+name)
    return values

try:
    with socket.create_connection(('127.0.0.1',port),timeout=3) as connection:
        connection.settimeout(3)
        with connection.makefile('rwb') as stream:
            banner=reply(stream)
            if not any('Android Console' in line for line in banner):
                raise ValueError('The owned port did not identify an Android console')
            if any('authentication required' in line.lower() for line in banner):
                raise ValueError('This legacy console fixture does not handle an authenticated console')
            record['banner']=banner
            for name,chosen in [('acceleration',[0.0,0.0,9.81]),('magnetic-field',[-20.0,20.0,-40.0])]:
                before=vector(command(stream,'sensor get '+name),name)
                command(stream,'sensor set '+name+' '+':'.join(map(str,chosen)))
                after=vector(command(stream,'sensor get '+name),name)
                if any(abs(actual-wanted)>0.001 for actual,wanted in zip(after,chosen)):
                    raise ValueError('Sensor input readback differs: '+name)
                record['settings'].append({'sensor':name,'before':before,'chosen':chosen,'after':after})
    record['status']='applied-and-readback-verified'
    (directory/'native-sensor-inputs.json').write_text(json.dumps(record,indent=2)+'\n')
    print('Native sensor inputs verified: acceleration0:0:9.81; magnetic-field-20:20:-40')
except Exception as error:
    record['status']='failed'
    record['error']=str(error)
    (directory/'native-sensor-console-failed.json').write_text(json.dumps(record,indent=2)+'\n')
    raise
