# SPDX-License-Identifier: GPL-3.0-or-later
"""Verify all split-profile call sites retain their implementations and C++23."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
DIRECTORY = ROOT / "tests/qt-selftest"
CMAKE = (DIRECTORY / "CMakeLists.txt").read_text(encoding="utf-8")
MAIN = (DIRECTORY / "main.cpp").read_text(encoding="utf-8")


def cmake_list(name):
    match = re.search(r"set\(" + name + r"\s+(.*?)\)", CMAKE, re.S)
    if not match:
        raise AssertionError("Missing source partition: " + name)
    return set(match.group(1).split())


class AndroidSelftestProfiles(unittest.TestCase):
    def test_source_partition_covers_every_called_check(self):
        original = set(re.findall(r"^        (checks_\w+\.cpp)$", CMAKE, re.M))
        extended_only = cmake_list("smoke_android_extended_only_sources")
        shared = cmake_list("smoke_android_shared_sources")
        self.assertTrue(extended_only <= original)
        self.assertTrue(shared <= original)
        self.assertFalse(extended_only & shared)
        profiles = {"core": original - extended_only,
                    "extended": extended_only | shared}
        self.assertEqual(set.union(*profiles.values()), original)
        calls_by_profile = {}
        for profile, sources in profiles.items():
            function = "runCoreChecks" if profile == "core" else "runExtendedChecks"
            body = MAIN.split("void " + function, 1)[1].split("#endif", 1)[0]
            calls = set(re.findall(r"\b(check\w+)\(r\)", body))
            self.assertTrue(calls)
            calls_by_profile[profile] = calls
            definitions = set()
            for name in sources:
                text = (DIRECTORY / name).read_text(encoding="utf-8")
                definitions.update(re.findall(r"void\s+(check\w+)\s*\(SmokeReporter\s*&\s*r\)", text))
            self.assertFalse(calls - definitions, (profile, calls - definitions))
            self.assertIn("checks_modern_cpp.cpp", sources)
            self.assertIn("checks_wayland_live.cpp", sources)
            self.assertIn("checkModernCpp(r);", MAIN)
        self.assertFalse(calls_by_profile["core"] & calls_by_profile["extended"])
        self.assertEqual(len(set.union(*calls_by_profile.values())), 74)


if __name__ == "__main__":
    unittest.main()
