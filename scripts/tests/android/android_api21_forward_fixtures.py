# SPDX-License-Identifier: GPL-3.0-or-later
"""Synthetic API10 APK on API21 metadata; no target code or emulator runs."""
import importlib.util
import json
from pathlib import Path

import android_api21_sound_cache_fixtures as common

data = common.data
ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('api21_forward_fixture', ROOT / 'scripts/run/android/android-api21-forward.py')
forward = importlib.util.module_from_spec(spec)
spec.loader.exec_module(forward)


def prepare(root, abi='x86', name='fixture-run'):
    record = common.prepare(root, abi, name)
    run = Path(root) / name
    original, case = run / 'sound-cache-teardown', run / 'api10-selftest'
    assert original.resolve().parent == run.resolve() == case.resolve().parent
    original.rename(case)
    text = data.stdout(5, 10, abi, 'qt-selftest')
    (case / 'files/selftest.stdout').write_text(text)
    coverage = forward._shared.coverage_binding()
    options = json.loads((run / 'run-options.json').read_text())
    options.update(coverage, diagnostic='qt5-api10-on-api21')
    (run / 'run-options.json').write_text(json.dumps(options))
    record.update(coverage, name='api10-selftest', arguments='--selftest', apk_relative='apk/qt-selftest.apk',
                  diagnostic='qt5-api10-on-api21', summary=[line for line in text.splitlines() if line.startswith('---- ')],
                  apk_sha256=data.digest(Path(root) / 'apk/qt-selftest.apk'),
                  run_options_sha256=data.digest(run / 'run-options.json'))
    record['launch_arguments'][-1] = '--selftest'
    rebind_stdout(run, record)
    data.api21_cleanup_evidence(Path(root), [record], run=name)
    save(run, record)
    return record


def save(run, record):
    (Path(run) / 'results.json').write_text(json.dumps([record]))


def rebind_stdout(run, record):
    path = Path(run) / 'api10-selftest/files/selftest.stdout'
    record['stdout_sha256'] = record['diagnostic_stdout_sha256'] = data.digest(path)


def rebind_options(run, record, **changes):
    path = Path(run) / 'run-options.json'
    options = json.loads(path.read_text())
    options.update(changes)
    path.write_text(json.dumps(options))
    record['run_options_sha256'] = data.digest(path)
    save(run, record)
