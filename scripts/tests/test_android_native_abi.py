# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Check ABI rejection before packaging without SDKs or native compilation."""
import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest
spec = importlib.util.spec_from_file_location('native_abi', Path(__file__).resolve().parents[1] / 'build/android-api21/native-abi.py')
abi = importlib.util.module_from_spec(spec)
spec.loader.exec_module(abi)


class NativeAbi(unittest.TestCase):
    def test_matching_and_mismatched_library_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            p = Path(directory) / 'client.so'
            for name, (bits, machine) in abi.SETTINGS.items():
                header = bytearray(20)
                header[:6] = b'\x7fELF' + bytes((bits, 1))
                struct.pack_into('<H', header, 18, machine)
                p.write_bytes(header)
                abi.inspect(p, name)
                other = 'x86' if name != 'x86' else 'arm64-v8a'
                with self.assertRaisesRegex(ValueError, 'does not match'):
                    abi.inspect(p, other)


if __name__ == '__main__':
    unittest.main()
