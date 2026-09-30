#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Report PE imports relevant to a Qt 4 Windows 95 compatibility build.

This is a static triage tool, not a claim that the executable runs on Win95.
The loader may reject other imports, and an imported W function may exist as a
stub that fails only when Qt calls it.
"""

from __future__ import annotations

import argparse
import struct
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path


# Direct imports already observed in the kit's Qt 4.8.7/Qt 5 smoke binaries.
# This list is intentionally a triage list, not a complete Win95 export table.
KNOWN_POST_WIN95 = {
    "AddVectoredExceptionHandler",
    "CancelIo",
    "CheckRemoteDebuggerPresent",
    "GetFileAttributesExW",
    "GetFileSizeEx",
    "GetNativeSystemInfo",
    "InterlockedCompareExchange",
    "SetFilePointerEx",
    "SwitchToThread",
    "SystemTimeToTzSpecificLocalTime",
    "TryEnterCriticalSection",
}


class PEError(ValueError):
    pass


def u16(data: bytes, offset: int) -> int:
    if offset < 0 or offset + 2 > len(data):
        raise PEError("truncated PE header")
    return struct.unpack_from("<H", data, offset)[0]


def u32(data: bytes, offset: int) -> int:
    if offset < 0 or offset + 4 > len(data):
        raise PEError("truncated PE header")
    return struct.unpack_from("<I", data, offset)[0]


def u64(data: bytes, offset: int) -> int:
    if offset < 0 or offset + 8 > len(data):
        raise PEError("truncated PE header")
    return struct.unpack_from("<Q", data, offset)[0]


def cstring(data: bytes, offset: int) -> str:
    if offset < 0 or offset >= len(data):
        raise PEError("string address lies outside the file")
    end = data.find(b"\0", offset, min(len(data), offset + 4096))
    if end < 0:
        raise PEError("unterminated import name")
    return data[offset:end].decode("ascii", errors="replace")


class PEImage:
    def __init__(self, path: Path):
        self.data = path.read_bytes()
        data = self.data
        if data[:2] != b"MZ":
            raise PEError("missing MZ header")
        pe = u32(data, 0x3C)
        if data[pe:pe + 4] != b"PE\0\0":
            raise PEError("missing PE signature")
        coff = pe + 4
        self.machine = u16(data, coff)
        section_count = u16(data, coff + 2)
        optional_size = u16(data, coff + 16)
        opt = coff + 20
        magic = u16(data, opt)
        if magic == 0x10B:
            self.directory_offset = opt + 96
            self.pointer_size = 4
        elif magic == 0x20B:
            self.directory_offset = opt + 112
            self.pointer_size = 8
        else:
            raise PEError(f"unsupported optional header: {magic:#x}")
        self.optional_end = opt + optional_size
        if self.optional_end > len(data) or self.optional_end < self.directory_offset:
            raise PEError("truncated optional header")
        self.directory_count = u32(data, self.directory_offset - 4)
        self.header_size = u32(data, opt + 60)
        self.subsystem_version = (u16(data, opt + 48), u16(data, opt + 50))
        self.subsystem_type = u16(data, opt + 68)
        self.sections = []
        for index in range(section_count):
            base = self.optional_end + index * 40
            u32(data, base + 36)  # Require the complete section header.
            self.sections.append((u32(data, base + 12), u32(data, base + 8),
                                  u32(data, base + 20), u32(data, base + 16)))

    def directory(self, index: int) -> tuple[int, int]:
        if index >= self.directory_count:
            return 0, 0
        base = self.directory_offset + index * 8
        if base + 8 > self.optional_end:
            raise PEError("truncated data directory")
        return u32(self.data, base), u32(self.data, base + 4)

    def offset(self, rva: int) -> int:
        if 0 <= rva < min(self.header_size, len(self.data)):
            return rva
        for virtual, virtual_size, raw, raw_size in self.sections:
            if virtual <= rva < virtual + max(virtual_size, raw_size):
                delta = rva - virtual
                if delta < raw_size and raw + delta < len(self.data):
                    return raw + delta
                break
        raise PEError(f"RVA {rva:#x} is outside the file-backed sections")

    def imports(self) -> dict[str, list[str]]:
        imports: dict[str, list[str]] = defaultdict(list)
        import_rva, _ = self.directory(1)
        if not import_rva:
            return {}
        descriptor = self.offset(import_rva)
        for _ in range(1024):
            if descriptor + 20 > len(self.data):
                raise PEError("truncated import descriptor")
            lookup = u32(self.data, descriptor)
            name_rva = u32(self.data, descriptor + 12)
            address = u32(self.data, descriptor + 16)
            if not (lookup or name_rva or address):
                return dict(imports)
            dll = cstring(self.data, self.offset(name_rva)).lower()
            thunk = self.offset(lookup or address)
            for _ in range(65536):
                value = u64(self.data, thunk) if self.pointer_size == 8 else u32(self.data, thunk)
                if value == 0:
                    break
                ordinal_bit = 1 << (self.pointer_size * 8 - 1)
                if value & ordinal_bit:
                    imports[dll].append(f"#{value & 0xFFFF}")
                else:
                    imports[dll].append(cstring(self.data, self.offset(value) + 2))
                thunk += self.pointer_size
            else:
                raise PEError("unterminated import thunk table")
            descriptor += 20
        raise PEError("unterminated import descriptor table")


@dataclass
class Exports:
    machine: int
    symbols: set[str]
    forwarders: dict[str, str]


def inspect_exports(path: Path) -> Exports:
    image = PEImage(path)
    data = image.data
    rva, size = image.directory(0)
    symbols: set[str] = set()
    forwarders: dict[str, str] = {}
    if not rva:
        return Exports(image.machine, symbols, forwarders)
    base = image.offset(rva)
    ordinal_base = u32(data, base + 16)
    count = u32(data, base + 20)
    name_count = u32(data, base + 24)
    if count > 65536 or name_count > 65536:
        raise PEError("unreasonably large export table")
    addresses = image.offset(u32(data, base + 28)) if count else 0
    names = image.offset(u32(data, base + 32)) if name_count else 0
    ordinals = image.offset(u32(data, base + 36)) if name_count else 0
    for index in range(count):
        address = u32(data, addresses + index * 4)
        if not address:  # A hole is not an exported ordinal.
            continue
        ordinal = f"#{ordinal_base + index}"
        symbols.add(ordinal)
        if rva <= address < rva + size:
            forwarders[ordinal] = cstring(data, image.offset(address))
    for index in range(name_count):
        function_index = u16(data, ordinals + index * 2)
        if function_index >= count:
            raise PEError("export name has an out-of-range ordinal index")
        ordinal = f"#{ordinal_base + function_index}"
        if ordinal not in symbols:
            continue
        name = cstring(data, image.offset(u32(data, names + index * 4)))
        symbols.add(name)
        if ordinal in forwarders:
            forwarders[name] = forwarders[ordinal]
    return Exports(image.machine, symbols, forwarders)


class SystemExports:
    """Resolve imports against a caller-supplied OS DLL snapshot, never the host."""

    def __init__(self, directories: list[Path]):
        self.paths: dict[str, Path] = {}
        self.cache: dict[str, Exports] = {}
        for directory in directories:
            if not directory.is_dir():
                raise PEError(f"system directory does not exist: {directory}")
            for path in sorted(directory.iterdir()):
                if not path.is_file():
                    continue
                key = path.name.lower()
                if key in self.paths and self.paths[key] != path:
                    raise PEError(f"ambiguous system DLL {key}: {self.paths[key]} and {path}")
                self.paths[key] = path

    def resolve(self, dll: str, symbol: str, machine: int,
                seen: frozenset[tuple[str, str]] = frozenset()) -> str | None:
        dll = dll.lower()
        entry = (dll, symbol)
        if entry in seen:
            return f"forwarder cycle at {dll}!{symbol}"
        if len(seen) >= 32:
            return f"forwarder chain too deep at {dll}!{symbol}"
        path = self.paths.get(dll)
        if path is None:
            return f"missing DLL: {dll}"
        try:
            if dll not in self.cache:
                self.cache[dll] = inspect_exports(path)
            exports = self.cache[dll]
        except (OSError, PEError) as error:
            return f"cannot read {dll}: {error}"
        if exports.machine != machine:
            return f"wrong machine in {dll}: {exports.machine:#x}, expected {machine:#x}"
        if symbol not in exports.symbols:
            return f"missing export: {dll}!{symbol}"
        forwarder = exports.forwarders.get(symbol)
        if forwarder is not None:
            if "." not in forwarder:
                return f"invalid forwarder: {dll}!{symbol} -> {forwarder}"
            target_dll, target_symbol = forwarder.rsplit(".", 1)
            if not target_dll.lower().endswith((".dll", ".drv", ".exe")):
                target_dll += ".dll"
            failure = self.resolve(target_dll, target_symbol, machine, seen | {entry})
            if failure:
                return f"{dll}!{symbol} -> {failure}"
        return None


def inspect(path: Path) -> tuple[int, int, tuple[int, int], dict[str, list[str]], bool]:
    image = PEImage(path)
    return (image.machine, image.subsystem_type, image.subsystem_version,
            image.imports(), bool(image.directory(13)[0]))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--details", action="store_true",
                        help="print every imported DLL and symbol for manual OS-export review")
    parser.add_argument("--system-dir", type=Path, action="append", default=[],
                        help="directory of actual target OS DLLs; repeat for multiple directories")
    parser.add_argument("executables", type=Path, nargs="+")
    args = parser.parse_args()
    try:
        system = SystemExports(args.system_dir) if args.system_dir else None
    except (OSError, PEError) as error:
        parser.error(str(error))
    incompatible = False
    for path in args.executables:
        try:
            machine, subsystem_type, subsystem_version, imports, has_delay = inspect(path)
        except (OSError, PEError) as error:
            parser.error(f"{path}: {error}")
        names = [name for group in imports.values() for name in group]
        wide = sorted(name for name in names if name.endswith("W"))
        ansi = sorted(name for name in names if name.endswith("A"))
        later = sorted(name for name in names if name in KNOWN_POST_WIN95)
        machine_name = {0x14C: "i386", 0x8664: "amd64", 0xAA64: "arm64"}.get(
            machine, f"machine {machine:#x}")
        subsystem_name = {2: "GUI", 3: "console"}.get(subsystem_type,
                                                         str(subsystem_type))
        print(f"{path}: {machine_name}, {subsystem_name} subsystem, "
              f"minimum subsystem version {subsystem_version[0]}.{subsystem_version[1]:02d}, "
              f"{len(names)} imports from {len(imports)} DLLs")
        print(f"  ANSI/Unicode direct imports: {len(ansi)} A, {len(wide)} W")
        print(f"  known post-Win95 imports: {', '.join(later) or 'none from triage list'}")
        print(f"  delay-import directory: {'present (not parsed)' if has_delay else 'absent'}")
        if wide:
            print(f"  W examples: {', '.join(wide[:12])}")
        if system is not None:
            missing = sorted({failure for dll, symbols in imports.items()
                              for symbol in symbols
                              if (failure := system.resolve(dll, symbol, machine))})
            for failure in missing:
                print(f"  BLOCKER {failure}")
            if has_delay:
                print("  INCOMPLETE delay imports are not audited")
            incompatible |= bool(missing) or has_delay
            print(f"  target export audit: {len(missing)} blockers; runtime behavior remains unverified")
        if args.details:
            for dll, symbols in sorted(imports.items()):
                print(f"  {dll}:")
                for symbol in sorted(symbols):
                    print(f"    {symbol}")
    return int(incompatible)


if __name__ == "__main__":
    raise SystemExit(main())
