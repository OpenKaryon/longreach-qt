# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Compile-cache inputs must change independently from archive-only link inputs."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("qt4_cache", ROOT / "scripts/build/qt4-android/cache-inputs.py")
cache = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cache)


class CacheInputs(unittest.TestCase):
    def test_compiler_flags_mkspec_and_headers_invalidate_objects(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runtime, sdk = root / "runtime", root / "sdk"
            files = [root / "compiler", runtime / "target.sh", runtime / "bin/cxx", runtime / "bin/cc",
                     runtime / "include/c++/v1/vector", runtime / "sysroot/usr/include/stdio.h",
                     sdk / "mkspecs/android-longreach-clang/qmake.conf",
                     sdk / "mkspecs/android-longreach-clang/qplatformdefs.h", sdk / "include/QtCore/qconfig.h"]
            for file in files:
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text("old")
            with patch.object(cache.shutil, "which", return_value=str(root / "compiler")), patch.object(cache.subprocess, "check_output", return_value="clang 21.1.8"):
                def key():
                    return cache.fingerprint(cache.client_compile_inputs(sdk, runtime))
                initial = key()
                self.assertEqual(initial, key())
                for file in files:
                    file.write_text("changed")
                    self.assertNotEqual(initial, key(), str(file))
                    file.write_text("old")
                (sdk / "lib").mkdir()
                (sdk / "lib/QtCore.a").write_text("new link input")
                self.assertEqual(initial, key(), "Archive-only changes must retain compilation objects")
                saved = root / "saved"
                self.assertTrue(cache.needs_clean(saved, initial))
                saved.write_text(initial)
                self.assertFalse(cache.needs_clean(saved, initial))
                self.assertTrue(cache.needs_clean(saved, cache.fingerprint([initial, "new flags"])))


if __name__ == "__main__":
    unittest.main()
