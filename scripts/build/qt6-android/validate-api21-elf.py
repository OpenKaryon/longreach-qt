# SPDX-License-Identifier: GPL-3.0-or-later

"""Check selected ELF metadata against the Android API10/API21 SDK policy."""
import argparse
import json
from pathlib import Path
import struct


def relocation_metadata(data, dynamic, segments, bits, abi, api, path, offset):
    # Bionic android-2.3.7_r1/linker/linker.c and
    # android-5.0.2_r1/linker/linker.cpp: ordinary shared-library operations.
    # This SDK deliberately excludes COPY, IFUNC/IRELATIVE and native TLS.
    # API10 i386 lacks the type-zero skip present in the API21 loader.
    supported = {
        'x86': {1, 2, 6, 7, 8} | ({0} if api == 21 else set()),
        'armeabi-v7a': {0, 2, 3, 21, 22, 23},
        'x86_64': {0, 1, 2, 6, 7, 8, 10},
        'arm64-v8a': {0, 257, 258, 259, 260, 261, 262, 1025, 1026, 1027},
    }[abi]
    relative = {'x86': 8, 'armeabi-v7a': 23, 'x86_64': 8, 'arm64-v8a': 1027}[abi]
    if 22 in dynamic or any(value & 4 for value in dynamic.get(30, [])):
        # A stricter SDK contract than API10/API21 LP32's historical tolerance.
        raise RuntimeError(f'TEXTREL markers are excluded by the SDK policy: {path}')

    def one(tag, default=None):
        values = dynamic.get(tag, [])
        if len(values) > 1:
            raise RuntimeError(f'Duplicate relocation tag {tag}: {path}')
        return values[0] if values else default

    rela = bits == 64
    address_tag, size_tag, entry_tag = (7, 8, 9) if rela else (17, 18, 19)
    wrong_tags = (17, 18, 19) if rela else (7, 8, 9)
    if any(tag in dynamic for tag in wrong_tags):
        raise RuntimeError(f'Unsupported relocation table format for {abi}: {path}')
    entry_size = 24 if rela else 8
    if one(entry_tag, entry_size) != entry_size:
        raise RuntimeError(f'Invalid relocation entry size: {path}')
    tables = []
    for name, tags in (('dynamic', (address_tag, size_tag)), ('plt', (23, 2, 20))):
        if not any(tag in dynamic for tag in tags):
            continue
        if not all(tag in dynamic for tag in tags):
            raise RuntimeError(f'Incomplete {name} relocation table: {path}')
        address, size = one(tags[0]), one(tags[1])
        if name == 'plt' and one(20) != address_tag:
            raise RuntimeError(f'Unsupported PLT relocation table format: {path}')
        if size % entry_size:
            raise RuntimeError(f'Invalid {name} relocation table size: {path}')
        start = offset(address, size) if size else 0
        tables.append((name, start, size))

    types, counts = set(), {}
    for name, start, size in tables:
        counts[name] = size // entry_size
        for position in range(start, start + size, entry_size):
            target, info = struct.unpack_from('<QQ' if rela else '<II', data, position)
            kind, symbol = (info & 0xffffffff, info >> 32) if rela else (info & 255, info >> 8)
            if kind not in supported:
                raise RuntimeError(f'Unsupported API{api} {abi} relocation type {kind}: {path}')
            types.add(kind)
            if kind == relative and symbol:
                raise RuntimeError(f'RELATIVE relocation must not reference a symbol: {path}')
            if not kind:
                continue
            # These old implementations write a native word, even for some
            # narrowly named operations. BSS targets are valid memory mappings.
            writable = any(segment[0] == 1 and segment[6] & 2
                           and segment[2] <= target
                           and target + bits // 8 <= segment[2] + segment[5]
                           for segment in segments)
            if not writable:
                raise RuntimeError(f'Relocation target is not writable mapped memory: {path}')
    return {'format': 'RELA' if rela else 'REL', 'types': sorted(types),
            'table_entries': counts, 'textrel_markers': False,
            'targets_writable': True, 'policy': 'android-sdk-relocations-v1'}


def inspect(path, abi, api):
    if api not in (10, 21) or (api == 10 and abi not in ('x86', 'armeabi-v7a')):
        raise RuntimeError(f'Unsupported Android ABI/API policy: {abi}/API{api}')
    data = path.read_bytes()
    bits, machine, machine_name = {'armeabi-v7a': (32, 40, 'ARM'),
                                    'arm64-v8a': (64, 183, 'AArch64'),
                                    'x86': (32, 3, 'Intel 80386'),
                                    'x86_64': (64, 62, 'x86-64')}[abi]
    elf_class = 1 if bits == 32 else 2
    if len(data) < (52 if bits == 32 else 64) or data[:7] != b'\x7fELF' + bytes((elf_class, 1, 1)):
        raise RuntimeError(f'Expected little-endian ELF{bits}: {path}')
    if struct.unpack_from('<H', data, 16)[0] != 3 or struct.unpack_from('<I', data, 20)[0] != 1:
        raise RuntimeError(f'Expected an ET_DYN library with current ELF version: {path}')
    if struct.unpack_from('<H', data, 18)[0] != machine:
        raise RuntimeError(f'Expected {machine_name} target: {path}')
    if bits == 32:
        phoff = struct.unpack_from('<I', data, 28)[0]
        phsize, phcount = struct.unpack_from('<HH', data, 42)
        segments = [struct.unpack_from('<IIIIIIII', data, phoff + index * phsize)
                    for index in range(phcount)]
    else:
        phoff = struct.unpack_from('<Q', data, 32)[0]
        phsize, phcount = struct.unpack_from('<HH', data, 54)
        segments = []
        for index in range(phcount):
            kind, flags, start, virtual, physical, size, memsize, align = struct.unpack_from(
                '<IIQQQQQQ', data, phoff + index * phsize)
            segments.append((kind, start, virtual, physical, size, memsize, flags, align))
    if any(entry[0] == 7 for entry in segments):
        raise RuntimeError(f'Native ELF TLS requires a newer Android loader: {path}')

    def offset(address, length=1):
        for kind, start, virtual, _, size, _, _, _ in segments:
            if (kind == 1 and virtual <= address < virtual + size
                    and length <= virtual + size - address
                    and start + address - virtual + length <= len(data)):
                return start + address - virtual
        raise RuntimeError(f'Unmapped ELF address in {path}')

    dynamic = {}
    for kind, start, _, _, size, _, _, _ in segments:
        if kind == 2:
            for pos in range(start, start + size, bits // 4):
                tag, value = struct.unpack_from('<II' if bits == 32 else '<QQ', data, pos)
                if not tag:
                    break
                dynamic.setdefault(tag, []).append(value)
    if 4 not in dynamic:
        raise RuntimeError(f'API{api} needs a SysV DT_HASH table: {path}')
    if any(tag in dynamic for tag in (35, 36, 37, 0x6000000f, 0x60000010, 0x60000011, 0x60000012,
                                    0x6fffe000, 0x6fffe001, 0x6fffe003)):
        raise RuntimeError(f'Packed relocations require a newer Android loader: {path}')
    relocations = relocation_metadata(data, dynamic, segments, bits, abi, api, path, offset)
    strings = offset(dynamic[5][0])

    def string(index):
        start = strings + index
        return data[start:data.index(0, start)].decode('utf-8', errors='replace')

    needed = [string(index) for index in dynamic.get(1, [])]
    if any(name in ('libstdc++.so', 'libstdc++.so.6', 'libgcc_s.so.1', 'libc.so.6') for name in needed):
        raise RuntimeError(f'Unexpected GNU/host runtime dependency: {path}: {needed}')
    count = struct.unpack_from('<I', data, offset(dynamic[4][0]) + 4)[0]
    symbols = offset(dynamic[6][0])
    symbol_size = dynamic.get(11, [16 if bits == 32 else 24])[0]
    legacy_futex_check = api == 10 and abi == 'x86'
    for index in range(count):
        position = symbols + index * symbol_size
        name = string(struct.unpack_from('<I', data, position)[0])
        info = data[position + (12 if bits == 32 else 4)]
        if info & 15 == 10:
            raise RuntimeError(f'GNU IFUNC symbols are excluded by the SDK policy: {path}: {name}')
        section = struct.unpack_from('<H', data, position + (14 if bits == 32 else 6))[0]
        if legacy_futex_check and name == 'futex' and section == 0:
            raise RuntimeError(f'Legacy x86 SDK must not import libc futex (unavailable on API21): {path}')
        if '__ndk1' in name:
            raise RuntimeError(f'Stock NDK libc++ ABI leaked into the LLVM21 SDK: {path}: {name}')
    return {'path': str(path), 'machine': machine_name, 'elf_bits': bits,
            'sysv_hash': True, 'native_tls': False, 'packed_relocations': False,
            'needed': needed, 'legacy_x86_futex_import_checked': legacy_futex_check,
            'relocations': relocations}


def validate(prefix, abi, api, runtime):
    paths = set()
    for directory in ('lib', 'plugins', 'qml'):
        paths.update(path.resolve() for path in (prefix / directory).rglob('*.so') if path.is_file())
    paths.add(runtime.resolve())
    results = [inspect(path, abi, api) for path in sorted(paths)]
    if len(results) < 2:
        raise RuntimeError('No Qt target libraries found')
    return {'platform': f'Android API{api} {abi}',
            'validation_scope': 'selected-elf-metadata-v1',
            'runtime_loading_verified': False, 'symbol_resolution_verified': False,
            'libraries': results}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('prefix', type=Path)
    parser.add_argument('--abi', choices=('armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64'), default='armeabi-v7a')
    parser.add_argument('--api', choices=(10, 21), type=int, default=21)
    parser.add_argument('--runtime', type=Path, help='explicit runtime library for offline metadata checks')
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args(argv)
    if args.api == 10 and args.abi not in ('armeabi-v7a', 'x86'):
        parser.error('API10 supports only ARMv7 or x86')
    runtime_prefix = '/opt/longreach-android' if args.api == 10 else '/opt/longreach-android-api21'
    runtime = args.runtime or Path(runtime_prefix) / 'lib/libc++_shared.so'
    # A failed producer check cannot leave an earlier success report advertised.
    args.report.unlink(missing_ok=True)
    report = validate(args.prefix, args.abi, args.api, runtime)
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    extra = ', no libc futex import' if args.api == 10 and args.abi == 'x86' else ''
    print(f'API{args.api} selected ELF metadata: {len(report["libraries"])} {args.abi} libraries, SysV hash, no native TLS/packed relocations, explicit relocation policy{extra}')
    return report


if __name__ == '__main__':
    main()
