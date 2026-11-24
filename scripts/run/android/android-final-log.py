# SPDX-License-Identifier: GPL-3.0-or-later
"""Validate resident-JNI cleanup observations and the final host-bound capture."""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import sys


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


HERE = Path(__file__).resolve().parent
owned = load('final_log_owned', HERE / 'android-owned-process.py')
common = load('final_log_artifacts', HERE.parents[1] / 'build/android-api21/artifact-manifest.py')
FATAL = re.compile(r'FATAL EXCEPTION|Fatal signal|exiting due to signal|terminated by signal|VM aborting|\*\*\*\s+\*\*\*\s+\*\*\*|>>>\s*org\.longreachqt\.donut(?:\.quick)?\s*<<<')
CASE_FIELDS = ('case_cleanup_raw_logcat_sha256', 'case_cleanup_logcat_sha256')
FINAL_FIELDS = ('final_logcat_sha256', 'final_logcat_capture_sha256')


def no_fatal(text):
    if FATAL.search(text):
        raise ValueError('Fatal cleanup error in captured Android log')


def case_cleanup(case, marker, bindings=None):
    raw_path, scoped_path = case / 'logcat-after-cleanup-raw.log', case / 'logcat-after-cleanup.log'
    raw = raw_path.read_text(encoding='utf-8-sig').splitlines()
    scoped = scoped_path.read_text(encoding='utf-8-sig').splitlines()
    if not re.fullmatch(r'BEGIN-[0-9a-f]{32}', marker):
        raise ValueError('Invalid case cleanup marker')
    pattern = r'^[VDIWEF]/LongreachCase\s*\(\s*\d+\):\s*' + re.escape(marker) + r'\s*$'
    indices = [index for index, line in enumerate(raw) if re.fullmatch(pattern, line)]
    previous = (case / 'logcat.log').read_text(encoding='utf-8-sig').splitlines()
    if len(indices) != 1 or raw[indices[0]+1:] != scoped or scoped[:len(previous)] != previous:
        raise ValueError('Case cleanup log lost its original launch observation')
    no_fatal('\n'.join(scoped))
    result = dict(zip(CASE_FIELDS, (owned.digest(raw_path), owned.digest(scoped_path))))
    if bindings is not None and any(bindings.get(key) != value for key, value in result.items()):
        raise ValueError('Case belongs to different cleanup log evidence')
    return result


def capture(directory, serial, host, bindings=None, last_case=None):
    path = directory / 'final-logcat.log'
    text = path.read_text(encoding='utf-8-sig')
    value, proof_sha = owned.read(directory / 'final-logcat-capture.json')
    log_sha = owned.digest(path)
    if (not text.strip() or text.startswith('Owned tree exited before final log capture.') or
            value.get('schema_version') != 1 or value.get('captured') is not True or
            value.get('serial') != serial or value.get('logcat_sha256') != log_sha or
            any(value.get(key) != host[key] for key in ('host_process_owner_sha256', 'host_process_request_sha256'))):
        raise ValueError('Missing or mismatched final Android log capture')
    no_fatal(text)
    if last_case is not None:
        previous = (last_case / 'logcat-after-cleanup-raw.log').read_text(encoding='utf-8-sig').splitlines()
        if text.splitlines()[:len(previous)] != previous:
            raise ValueError('Final Android log lost the last case cleanup observation')
    result = dict(zip(FINAL_FIELDS, (log_sha, proof_sha)))
    if bindings is not None and any(bindings.get(key) != value for key, value in result.items()):
        raise ValueError('Case belongs to different final log capture evidence')
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('case-cleanup', 'capture'))
    parser.add_argument('--root', required=True, type=Path)
    parser.add_argument('--directory', type=Path)
    parser.add_argument('--serial')
    parser.add_argument('--case', type=Path)
    parser.add_argument('--marker')
    parser.add_argument('--artifact-lease-held', action='store_true', help='internal: caller owns the root lease')
    args = parser.parse_args(argv)
    root = args.root.resolve()
    with common.artifact_lease(root, args.artifact_lease_held):
        if args.action == 'case-cleanup':
            if not args.case or not args.marker:
                parser.error('case-cleanup requires --case and --marker')
            result = case_cleanup(args.case, args.marker)
        else:
            if not args.directory or not args.serial:
                parser.error('capture requires --directory and --serial')
            host = owned.validate_emulator(args.directory, artifact_root=root)
            result = capture(args.directory, args.serial, host, last_case=args.case)
    print(json.dumps(result, sort_keys=True))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        sys.exit('Android final log validation failed: ' + str(error))
