# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon

"""PE loader cases that could make a target export audit falsely pass."""

import contextlib
import io
import struct
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from qt4_win95_imports import PEError, PEImage, SystemExports, inspect, inspect_exports, main


def fixture(path, exports=(), imports=(), machine=0x14C, ordinal_base=10):
    """Write a small PE with export holes, aliases and optional forwarders."""
    data = bytearray(0xA00)

    def word(offset, value):
        struct.pack_into("<H", data, offset, value)

    def dword(offset, value):
        struct.pack_into("<I", data, offset, value)

    data[:2] = b"MZ"
    dword(0x3C, 0x80)
    data[0x80:0x84] = b"PE\0\0"
    word(0x84, machine)
    word(0x86, 1)
    word(0x94, 224)
    opt = 0x98
    word(opt, 0x10B)
    word(opt + 48, 4)
    word(opt + 68, 2)
    dword(opt + 60, 0x200)
    dword(opt + 92, 16)
    section = opt + 224
    dword(section + 8, 0x800)
    dword(section + 12, 0x1000)
    dword(section + 16, 0x800)
    dword(section + 20, 0x200)

    def rva(offset):
        return offset - 0x200 + 0x1000

    strings = 0x2C0

    def string(value):
        nonlocal strings
        encoded = value.encode("ascii") + b"\0"
        start = strings
        data[start:start + len(encoded)] = encoded
        strings += len(encoded)
        return rva(start)

    if exports:
        dword(opt + 96, 0x1000)
        dword(opt + 100, 0x400)
        dword(0x210, ordinal_base)
        dword(0x214, len(exports))
        names = [(index, entry) for index, entry in enumerate(exports) if entry and entry[0]]
        dword(0x218, len(names))
        dword(0x21C, rva(0x240))
        dword(0x220, rva(0x280))
        dword(0x224, rva(0x2A0))
        for index, entry in enumerate(exports):
            if entry:
                dword(0x240 + index * 4, string(entry[1]) if entry[1] else 0x1700)
        for index, (function_index, entry) in enumerate(names):
            dword(0x280 + index * 4, string(entry[0]))
            word(0x2A0 + index * 2, function_index)

    if imports:
        dword(opt + 104, rva(0x600))
        dword(opt + 108, 40)
        dword(0x600, rva(0x680))
        dword(0x60C, rva(0x640))
        dword(0x610, rva(0x680))
        data[0x640:0x640 + len(imports[0]) + 1] = imports[0].encode() + b"\0"
        strings = 0x700
        for index, name in enumerate(imports[1:]):
            if name.startswith("#"):
                value = 0x80000000 | int(name[1:])
            else:
                hint = strings
                strings += 2
                string(name)
                value = rva(hint)
            dword(0x680 + index * 4, value)
    path.write_bytes(data)
    return data


class TargetExportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def test_names_ordinals_and_holes(self):
        path = self.root / "KERNEL32.DLL"
        fixture(path, [("Sleep", None), None, (None, None)])
        exports = inspect_exports(path)
        self.assertEqual(exports.symbols, {"Sleep", "#10", "#12"})
        system = SystemExports([self.root])
        self.assertIsNone(system.resolve("kernel32.dll", "Sleep", 0x14C))
        self.assertIsNone(system.resolve("kernel32.dll", "#12", 0x14C))
        self.assertIn("missing export", system.resolve("kernel32.dll", "#11", 0x14C))
        self.assertIn("missing export", system.resolve("kernel32.dll", "sleep", 0x14C))

    def test_missing_dll_and_machine_mismatch(self):
        fixture(self.root / "kernel32.dll", [("Sleep", None)], machine=0x8664)
        system = SystemExports([self.root])
        self.assertIn("wrong machine", system.resolve("kernel32.dll", "Sleep", 0x14C))
        self.assertIn("missing DLL", system.resolve("ws2_32.dll", "WSAAsyncSelect", 0x14C))

    def test_forwarded_name_and_ordinal(self):
        fixture(self.root / "kernel32.dll", [("Sleep", "NTDLL.Yield"), ("Wake", "NTDLL.#10")])
        fixture(self.root / "ntdll.dll", [("Yield", None)])
        system = SystemExports([self.root])
        self.assertIsNone(system.resolve("kernel32.dll", "Sleep", 0x14C))
        self.assertIsNone(system.resolve("kernel32.dll", "Wake", 0x14C))

    def test_forwarded_missing_export_and_cycle(self):
        fixture(self.root / "kernel32.dll", [("Sleep", "NTDLL.Absent"), ("Wake", "NTDLL.Wake")])
        fixture(self.root / "ntdll.dll", [("Wake", "KERNEL32.Wake")])
        system = SystemExports([self.root])
        self.assertIn("missing export: ntdll.dll!Absent", system.resolve("kernel32.dll", "Sleep", 0x14C))
        self.assertIn("forwarder cycle", system.resolve("kernel32.dll", "Wake", 0x14C))

    def test_invalid_export_ordinal(self):
        path = self.root / "broken.dll"
        data = fixture(path, [("Sleep", None)])
        struct.pack_into("<H", data, 0x2A0, 9)
        path.write_bytes(data)
        with self.assertRaises(PEError):
            inspect_exports(path)

    def test_direct_named_and_ordinal_imports(self):
        path = self.root / "probe.exe"
        fixture(path, imports=("KERNEL32.DLL", "Sleep", "#12"))
        machine, subsystem, version, imports, delay = inspect(path)
        self.assertEqual((machine, subsystem, version, delay), (0x14C, 2, (4, 0), False))
        self.assertEqual(imports, {"kernel32.dll": ["Sleep", "#12"]})

    def test_unbacked_section_and_truncated_header(self):
        path = self.root / "broken.dll"
        data = fixture(path)
        struct.pack_into("<I", data, 0x178 + 8, 0x1000)
        path.write_bytes(data)
        with self.assertRaises(PEError):
            PEImage(path).offset(0x1900)
        path.write_bytes(data[:0x100])
        with self.assertRaises(PEError):
            inspect(path)

    def test_ambiguous_snapshots_are_rejected(self):
        second = self.root / "other"
        second.mkdir()
        fixture(self.root / "KERNEL32.DLL")
        fixture(second / "kernel32.dll")
        with self.assertRaisesRegex(PEError, "ambiguous"):
            SystemExports([self.root, second])

    def test_cli_exit_status_for_missing_and_delay_imports(self):
        exe = self.root / "probe.exe"
        fixture(self.root / "kernel32.dll", [("Sleep", None)])
        data = fixture(exe, imports=("KERNEL32.DLL", "Sleep"))
        args = ["audit", "--system-dir", str(self.root), str(exe)]
        with patch.object(sys, "argv", args), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(main(), 0)
        fixture(self.root / "kernel32.dll", [("Other", None)])
        with patch.object(sys, "argv", args), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(main(), 1)
        fixture(self.root / "kernel32.dll", [("Sleep", None)])
        struct.pack_into("<I", data, 0x98 + 96 + 13 * 8, 0x1600)
        exe.write_bytes(data)
        with patch.object(sys, "argv", args), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(main(), 1)


if __name__ == "__main__":
    unittest.main()
