# SPDX-License-Identifier: GPL-3.0-or-later
"""CMake option spelling must not drop an enabled plugin from Android APKs."""
import ast
import importlib.util
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("cmake_cache", ROOT / "scripts/build/cmake_cache.py")
cache = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cache)
OPTION = "SMOKE_ANDROID_PLUGIN_TLS_OWNER"


class PluginDeploymentOption(unittest.TestCase):
    def test_cmake_true_spellings(self):
        with tempfile.TemporaryDirectory() as directory:
            build = Path(directory)
            for value in ["ON", "on", "TRUE", "True", "YES", "Y", "1", "2", "-1"]:
                with self.subTest(value=value):
                    (build / "CMakeCache.txt").write_text(OPTION + ":BOOL=" + value + "\n")
                    self.assertTrue(cache.cmake_cache_bool(build, OPTION))

    def test_cmake_false_spellings(self):
        with tempfile.TemporaryDirectory() as directory:
            build = Path(directory)
            for value in ["", "OFF", "off", "FALSE", "NO", "N", "0", "IGNORE", "NOTFOUND", "probe-NOTFOUND"]:
                with self.subTest(value=value):
                    (build / "CMakeCache.txt").write_text(OPTION + ":BOOL=" + value + "\n")
                    self.assertFalse(cache.cmake_cache_bool(build, OPTION))

    def test_missing_or_different_option_is_disabled(self):
        with tempfile.TemporaryDirectory() as directory:
            build = Path(directory)
            (build / "CMakeCache.txt").write_text("OTHER:BOOL=ON\n# " + OPTION + ":BOOL=ON\n")
            self.assertFalse(cache.cmake_cache_bool(build, OPTION))

    def test_both_real_deployers_use_the_option_for_selftest_only(self):
        with tempfile.TemporaryDirectory() as directory:
            build = Path(directory)
            for major in [5, 6]:
                source = ROOT / f"scripts/build/qt{major}-android/deploy-examples.py"
                tree = ast.parse(source.read_text(encoding="utf-8"))
                assignments = [node for node in ast.walk(tree) if isinstance(node, ast.Assign)
                               and any(isinstance(target, ast.Name) and target.id == "plugin_owner_enabled"
                                       for target in node.targets)]
                self.assertEqual(len(assignments), 1)
                expression = compile(ast.Expression(assignments[0].value), str(source), "eval")
                for app in ["qt-selftest", "widgets-gallery"]:
                    for value in ["ON", "TRUE", "YES", "1", "2", "OFF", "0", "NOTFOUND"]:
                        with self.subTest(major=major, app=app, value=value):
                            (build / "CMakeCache.txt").write_text(OPTION + ":BOOL=" + value + "\n")
                            environment = {"app": app, "args": SimpleNamespace(app=app, build=build),
                                           "cmake_cache_bool": cache.cmake_cache_bool}
                            self.assertEqual(eval(expression, environment),
                                             app == "qt-selftest" and value not in ["OFF", "0", "NOTFOUND"])


if __name__ == "__main__":
    unittest.main()
