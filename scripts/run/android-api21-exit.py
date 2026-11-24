# SPDX-License-Identifier: GPL-3.0-or-later
"""Recheck API21 natural-exit evidence after each case cleanup and final host capture."""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import sys

REPO = Path(__file__).resolve().parents[2]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


process_exit = module('api21_exit_process', REPO / 'scripts/run/android-process-exit.py')
owned = module('api21_exit_owned', REPO / 'scripts/run/android-owned-process.py')
launch = module('api21_exit_launch', REPO / 'scripts/run/android-api21-launch.py')
artifacts = module('api21_exit_artifacts', REPO / 'scripts/build/android-api21/artifact-manifest.py')


def package(qt, app):
    return ('org.longreachqt.examples.qt6.' + app.replace('-', '_') if qt == 6
            else 'org.longreachqt.examples.' + app.replace('-', ''))


def validate(root, run, qt, abi, records, host_evidence=None):
    root, run = Path(root).resolve(), Path(run).resolve()
    if run.parent != root or qt not in (5, 6):
        raise ValueError('Invalid API21 natural-exit run/Qt generation')
    if not isinstance(records, list):
        records = [records]
    if not records or any(not isinstance(record, dict) for record in records):
        raise ValueError('API21 exit evidence requires at least one recorded case')
    names = [record.get('name', '') for record in records]
    if (any(not isinstance(name, str) or not re.fullmatch(r'[a-z0-9-]+', name) for name in names)
            or len(set(names)) != len(names)):
        raise ValueError('Invalid or duplicate API21 exit case names')
    # This checks arguments and diagnostic mode, not the full suite's coverage.
    launch.validate(run, qt, abi, records)
    host = host_evidence if host_evidence is not None else owned.validate_emulator(run, artifact_root=root)
    observations = []
    for record in records:
        if any(record.get(key) != value for key, value in host.items()):
            raise ValueError('API21 case belongs to another owned process tree')
        case = run / record['name']
        if (type(record.get('result')) is not int or record['result'] != 0
                or record.get('stdout_sha256') != process_exit.digest(case / 'files/selftest.stdout')
                or (case / 'files/selftest-result.txt').read_text().strip() != '0'):
            raise ValueError('API21 case stdout or native return changed after validation')
        if case.resolve().parent != run:
            raise ValueError('API21 exit case leaves its run directory')
        result = process_exit.require_case_cleanup(case, package(qt, record['app']), record)
        observations.append(dict(name=record['name'], **result))
    # The runner clears logs between cases. Only the last marker is required in
    # the final run capture; earlier cases have their own sealed cleanup logs.
    last = records[-1]
    final = process_exit.require_final_exit(run, run / last['name'], package(qt, last['app']), last, host)
    for record in records:
        if any(record.get(key) != value for key, value in final.items()):
            raise ValueError('API21 case belongs to another final capture')
    return dict(final, case_cleanup_evidence=observations, all_observed_exits_clean=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--run', required=True)
    parser.add_argument('--qt-major', type=int, choices=(5, 6), required=True)
    parser.add_argument('--abi', choices=('armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64'), required=True)
    parser.add_argument('--artifact-lease-held', action='store_true')
    args = parser.parse_args(argv)
    try:
        root = args.root.resolve()
        # Match the existing starter's case-insensitive run-name validation.
        if not re.fullmatch(r'[a-zA-Z0-9-]+', args.run):
            raise ValueError('Invalid API21 exit run name')
        run = root / args.run
        if run.resolve().parent != root:
            raise ValueError('API21 exit run leaves its artifact root')
        with artifacts.artifact_lease(root, args.artifact_lease_held):
            records = json.loads((run / 'results.json').read_text(encoding='utf-8-sig'))
            validate(root, run, args.qt_major, args.abi, records)
    except (OSError, ValueError, RuntimeError, TypeError, KeyError, UnicodeError) as error:
        parser.exit(1, 'API21 termination evidence refused: ' + str(error) + '\n')
    print('API21 termination evidence verified; this does not qualify full-suite coverage')


if __name__ == '__main__':
    main()
