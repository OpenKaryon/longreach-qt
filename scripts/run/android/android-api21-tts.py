# SPDX-License-Identifier: GPL-3.0-or-later
"""Collect one explicit Qt5/Qt6 API21 TTS behavior diagnostic."""
import argparse
import importlib.util
from pathlib import Path

_spec = importlib.util.spec_from_file_location('api21_tts_diagnostic', Path(__file__).with_name('android-api21-diagnostic.py'))
_shared = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_shared)
base, _identity = _shared.base, _shared._identity


def kind(qt_major):
    if type(qt_major) is not int or qt_major not in (5, 6):
        raise ValueError('TTS diagnostics require Qt5 or Qt6')
    return 'tts' if qt_major == 5 else 'tts6'


def validate(root, name, abi, qt_major=5):
    return _shared.validate(root, name, abi, kind(qt_major))


def collect(root, name, abi, artifact_lease_held=False, qt_major=5):
    return _shared.collect(root, name, abi, kind(qt_major), artifact_lease_held)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--run', required=True)
    parser.add_argument('--abi', choices=('armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64'), required=True)
    parser.add_argument('--qt-major', type=int, choices=(5, 6), default=5)
    parser.add_argument('--artifact-lease-held', action='store_true')
    args = parser.parse_args(argv)
    try:
        collect(args.root, args.run, args.abi, args.artifact_lease_held, args.qt_major)
    except (OSError, ValueError, RuntimeError, KeyError, TypeError, UnicodeError) as error:
        parser.exit(1, 'API21 TTS diagnostic refused: ' + str(error) + '\n')
    print(f'API21 Qt{args.qt_major} TTS diagnostic: saved evidence verified; qualification=false')


if __name__ == '__main__':
    main()
