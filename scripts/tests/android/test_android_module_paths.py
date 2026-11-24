# SPDX-License-Identifier: GPL-3.0-or-later
"""Load nested runtime helpers through their real collector entry points."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]


class AndroidModulePaths(unittest.TestCase):
    def test_qt4_collector_loads_final_capture_from_the_android_subdirectory(self):
        path = ROOT / 'scripts/build/qt4-android/collect-api21-results.py'
        spec = importlib.util.spec_from_file_location('layout_qt4_collector', path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.assertEqual(Path(module._final.common.__file__).resolve(),
                         ROOT / 'scripts/build/android-api21/artifact-manifest.py')
        self.assertTrue(callable(module._final.capture))
