# SPDX-License-Identifier: GPL-3.0-or-later
"""Collect one explicit Qt5 API21 WAV diagnostic."""
import importlib.util
from pathlib import Path

_spec = importlib.util.spec_from_file_location('api21_sound_diagnostic', Path(__file__).with_name('android-api21-diagnostic.py'))
_shared = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_shared)
base, _identity = _shared.base, _shared._identity


def validate(root, name, abi):
    return _shared.validate(root, name, abi, 'sound')


def collect(root, name, abi, artifact_lease_held=False):
    return _shared.collect(root, name, abi, 'sound', artifact_lease_held)


def main(argv=None):
    return _shared.main('sound', argv)


if __name__ == '__main__':
    main()
