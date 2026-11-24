# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Recheck observed app termination; a native return marker is not process exit."""
import hashlib
import json
import re

FATAL = re.compile(r'FATAL EXCEPTION|Fatal signal|exiting due to signal|terminated by signal|VM aborting|\*\*\*\s+\*\*\*\s+\*\*\*', re.I)
AM = r'^[VDIWEF]/ActivityManager\s*\(\s*\d+\):\s*'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def lifecycle(lines, package):
    pkg = re.escape(package)
    starts, deaths = [], []
    for index, line in enumerate(lines):
        if FATAL.search(line) or re.search(r'>>>\s*' + pkg + r'\s*<<<', line, re.I):
            raise ValueError('Fatal cleanup error: ' + line)
        start = (re.search(AM + r'Start proc ' + pkg + r'(?:\s+.*)?:\s*pid=(\d+)(?:\s|$)', line, re.I) or
                 re.search(AM + r'Start proc (\d+):' + pkg + r'(?:/|\s|$)', line, re.I))
        if start:
            starts.append((int(start[1]), index, line))
        death = re.search(AM + r'Process ' + pkg + r' \(pid (\d+)\) has died\b', line, re.I)
        if death:
            deaths.append((int(death[1]), index, line))
    if not starts:
        return None
    if len(starts) != 1 or starts[0][0] <= 0:
        raise ValueError('Ambiguous application process launch')
    pid, start_index, start_line = starts[0]
    matching = [item for item in deaths if item[0] == pid and item[1] > start_index]
    if len(matching) > 1:
        raise ValueError('Ambiguous application process death')
    end = matching[0][1] if matching else len(lines) - 1
    control = re.compile(AM + r'(?:Force stopping(?: package)? ' + pkg + r'(?:\s|:|$)|Killing (?:\d+:)?' + pkg + r'(?:/|\s|$))', re.I)
    if any(control.search(line) for line in lines[start_index:end + 1]):
        raise ValueError('Application was killed or force-stopped during the case')
    return {'process_id': pid, 'start_line': start_line, 'death_line': matching[0][2] if matching else None}


def present(lines, package, pid):
    lines = [line.strip() for line in lines if line.strip()]
    if not lines:
        raise ValueError('Empty Android ps observation')
    header = lines[0].split()
    if 'PID' not in header or header[-1] not in ('NAME', 'CMD', 'COMMAND', 'ARGS'):
        raise ValueError('Unrecognized Android ps header')
    column = header.index('PID')
    rows = 0
    for line in lines[1:]:
        values = line.split()
        if len(values) < len(header) or not values[column].isdigit() or int(values[column]) <= 0:
            raise ValueError('Unrecognized Android ps row')
        rows += 1
        if int(values[column]) == pid or values[-1] == package or values[-1].startswith(package + ':'):
            return True
    if not rows:
        raise ValueError('Android ps observation contains no processes')
    return False


def scoped(raw, marker):
    if not re.fullmatch(r'BEGIN-[0-9a-f]{32}', marker):
        raise ValueError('Invalid Android process-exit log marker')
    pattern = re.compile(r'^[VDIWEF]/LongreachCase\s*\(\s*\d+\):\s*' + re.escape(marker) + r'\s*$')
    indices = [index for index, line in enumerate(raw) if pattern.fullmatch(line)]
    if len(indices) != 1:
        raise ValueError('Expected exactly one current Android process-exit marker')
    return raw[indices[0] + 1:]


def require_exit(case, package, record):
    proof_path = case / 'process-exit.json'
    proof = json.loads(proof_path.read_text(encoding='utf-8-sig'))
    marker = record.get('log_marker', '')
    if (record.get('process_exit_confirmed') is not True or
            record.get('process_exit_proof_sha256') != digest(proof_path) or
            proof.get('schema_version') != 1 or proof.get('package') != package or type(proof.get('process_id')) is not int or
            proof.get('process_exit_confirmed') is not True or proof.get('log_marker') != marker or
            proof.get('termination_policy') != 'natural' or proof.get('observation_order') != 'logcat-then-ps'):
        raise ValueError('Missing or mismatched application process-exit receipt')
    if (type(proof.get('observations')) is not int or proof['observations'] < 2 or
            type(proof.get('timeout_seconds')) is not int or not 1 <= proof['timeout_seconds'] <= 60 or
            type(proof.get('elapsed_ms')) is not int or not 0 <= proof['elapsed_ms'] < proof['timeout_seconds'] * 1000):
        raise ValueError('Invalid process-exit observation bounds')
    raw_path, log_path, ps_path = case / 'logcat-raw.log', case / 'logcat.log', case / 'process-exit-ps.txt'
    for key, path in (('raw_logcat_sha256', raw_path), ('logcat_sha256', log_path), ('ps_sha256', ps_path)):
        if proof.get(key) != digest(path):
            raise ValueError('Process-exit evidence changed: ' + path.name)
    raw = raw_path.read_text(encoding='utf-8-sig').splitlines()
    log = log_path.read_text(encoding='utf-8-sig').splitlines()
    if (case / 'log-marker.txt').read_text(encoding='utf-8-sig').strip() != marker or scoped(raw, marker) != log:
        raise ValueError('Process-exit log differs from its launch boundary')
    actual = lifecycle(log, package)
    if (not actual or not actual['death_line'] or
            any(proof.get(key) != value for key, value in actual.items()) or
            type(record.get('process_id')) is not int or record['process_id'] != actual['process_id']):
        raise ValueError('Matching application PID launch/death was not confirmed')
    if present(ps_path.read_text(encoding='utf-8-sig').splitlines(), package, actual['process_id']):
        raise ValueError('Application remained in the process-exit ps snapshot')
    return proof


def require_final_exit(run, case, package, record, host_evidence, serial='emulator-5582'):
    """Recheck natural termination against a final capture bound to the host owner."""
    proof = require_exit(case, package, record)
    log_path, capture_path = run / 'final-logcat.log', run / 'final-logcat-capture.json'
    capture = json.loads(capture_path.read_text(encoding='utf-8-sig'))
    log_sha, capture_sha = digest(log_path), digest(capture_path)
    if (capture.get('schema_version') != 1 or capture.get('captured') is not True
            or capture.get('serial') != serial or capture.get('logcat_sha256') != log_sha
            or record.get('final_logcat_sha256') != log_sha
            or record.get('final_logcat_capture_sha256') != capture_sha):
        raise ValueError('Missing or mismatched final application log capture')
    for key in ('host_process_owner_sha256', 'host_process_request_sha256'):
        if capture.get(key) != host_evidence.get(key) or capture.get(key) != record.get(key):
            raise ValueError('Final application log capture belongs to another owned run')
    actual = lifecycle(scoped(log_path.read_text(encoding='utf-8-sig').splitlines(), record['log_marker']), package)
    if actual != {key: proof[key] for key in ('process_id', 'start_line', 'death_line')}:
        raise ValueError('Final capture lost the same application process exit')
    return {'final_logcat_sha256': log_sha, 'final_logcat_capture_sha256': capture_sha}


def require_case_cleanup(case, package, record):
    """Recheck a natural app exit observed after APK release, before log reset."""
    proof = require_exit(case, package, record)
    raw_path = case / 'logcat-after-cleanup-raw.log'
    log_path = case / 'logcat-after-cleanup.log'
    fields = {'case_cleanup_raw_logcat_sha256': digest(raw_path),
              'case_cleanup_logcat_sha256': digest(log_path)}
    if any(record.get(key) != value for key, value in fields.items()):
        raise ValueError('API21 case cleanup log changed or is unbound')
    raw = raw_path.read_text(encoding='utf-8-sig').splitlines()
    log = log_path.read_text(encoding='utf-8-sig').splitlines()
    if scoped(raw, record['log_marker']) != log:
        raise ValueError('API21 case cleanup lost its launch boundary')
    actual = lifecycle(log, package)
    if actual != {key: proof[key] for key in ('process_id', 'start_line', 'death_line')}:
        raise ValueError('API21 case cleanup lost the same application process exit')
    return fields
