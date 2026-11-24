# SPDX-License-Identifier: GPL-3.0-or-later
"""Synthetic SDK report files, never actual SDK validation or a build."""
import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('fixture_sdk_reports', ROOT / 'scripts/build/android-api21/sdk-reports.py')
reports = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reports)
SDK = 'sha256:' + 'a' * 64
FIXTURE_SOURCE = '.sdk-report-input-fixture-source'


def producer(directory, qt, abi, runtime=b'fixture runtime'):
    directory.mkdir(parents=True, exist_ok=True)
    for name in reports.required(qt, abi):
        path = directory / name
        if name.startswith('sdk-api'):
            text = json.dumps({'libraries': [{'fixture': True}]})
        elif name == 'runtime-sha256.txt':
            text = hashlib.sha256(runtime).hexdigest() + ' libc++_shared.so\n'
        else:
            text = 'synthetic SDK producer report: ' + name + '\n'
        path.write_text(text)
    if qt == 6:
        audit = directory / 'sdk-java-audit'
        audit.mkdir(exist_ok=True)
        for index in range(10):
            (audit / f'Fixture{index}.jar').write_text('synthetic SDK Java snapshot')
    reports.seal(directory, qt, abi)
    return directory


def export(root, qt, abi, sdk=SDK, runtime=b'fixture runtime'):
    source = producer(root / FIXTURE_SOURCE, qt, abi, runtime)
    return reports.export(source, root, qt, abi, sdk)
