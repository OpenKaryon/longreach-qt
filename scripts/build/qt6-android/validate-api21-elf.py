# SPDX-License-Identifier: GPL-3.0-or-later

"""Check target ELF compatibility with the Android API21 loader (not a security scan)."""
import argparse
import json
from pathlib import Path
import struct

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('prefix', type=Path)
parser.add_argument('--abi', choices=('armeabi-v7a', 'arm64-v8a', 'x86_64'), default='armeabi-v7a')
parser.add_argument('--report', type=Path, required=True)
args = parser.parse_args()


def inspect(path):
    data = path.read_bytes()
    bits, machine, machine_name = {'armeabi-v7a': (32, 40, 'ARM'),
                                    'arm64-v8a': (64, 183, 'AArch64'),
                                    'x86_64': (64, 62, 'x86-64')}[args.abi]
    elf_class = 1 if bits == 32 else 2
    if data[:6] != b'\x7fELF' + bytes((elf_class, 1)):
        raise RuntimeError(f'Expected little-endian ELF{bits}: {path}')
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

    def offset(address):
        for kind, start, virtual, _, size, _, _, _ in segments:
            if kind == 1 and virtual <= address < virtual + size:
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
        raise RuntimeError(f'API21 needs a SysV DT_HASH table: {path}')
    if any(tag in dynamic for tag in (35, 36, 37, 0x6000000f, 0x60000011, 0x6fffe000)):
        raise RuntimeError(f'Packed relocations require a newer Android loader: {path}')
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
    for index in range(count):
        name = string(struct.unpack_from('<I', data, symbols + index * symbol_size)[0])
        if '__ndk1' in name:
            raise RuntimeError(f'Stock NDK libc++ ABI leaked into the LLVM21 SDK: {path}: {name}')
    return {'path': str(path), 'machine': machine_name, 'elf_bits': bits,
            'sysv_hash': True, 'native_tls': False, 'packed_relocations': False,
            'needed': needed}


paths = set()
for directory in ('lib', 'plugins', 'qml'):
    paths.update(path.resolve() for path in (args.prefix / directory).rglob('*.so') if path.is_file())
runtime = Path('/opt/longreach-android-api21/lib/libc++_shared.so')
paths.add(runtime)
results = [inspect(path) for path in sorted(paths)]
if len(results) < 2:
    raise RuntimeError('No Qt target libraries found')
args.report.write_text(json.dumps({'platform': f'Android API21 {args.abi}', 'libraries': results}, indent=2) + '\n')
print(f'API21 ELF loader compatibility: {len(results)} {args.abi} libraries, SysV hash, no native TLS or newer relocations')
