# SPDX-License-Identifier: GPL-3.0-or-later
"""Collect an API10 Qt5 selftest on API21 without SDK qualification."""
import importlib.util
from pathlib import Path

_spec = importlib.util.spec_from_file_location('api21_forward_diagnostic', Path(__file__).with_name('android-api21-diagnostic.py'))
_shared = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_shared)
base, _identity = _shared.base, _shared._identity


def validate(root, name, abi):
    return _shared.validate(root, name, abi, 'forward')


def collect(root, name, abi, artifact_lease_held=False):
    return _shared.collect(root, name, abi, 'forward', artifact_lease_held)


def main(argv=None):
    return _shared.main('forward', argv)


if __name__ == '__main__':
    main()
