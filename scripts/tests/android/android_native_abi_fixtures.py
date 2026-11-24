# SPDX-License-Identifier: GPL-3.0-or-later
"""Small ELF metadata fixtures only; the payload contains no executable code."""
import struct

SETTINGS = {'armeabi': (1, 40), 'armeabi-v7a': (1, 40), 'arm64-v8a': (2, 183),
            'x86': (1, 3), 'x86_64': (2, 62)}


def uleb(value):
    data = bytearray()
    while True:
        byte = value & 0x7f
        value >>= 7
        data.append(byte | (0x80 if value else 0))
        if not value:
            return bytes(data)


def attributes(arch=10, profile=0x41, vfp_args=0, extra=b''):
    values = b'\x05fixture-cpu\0\x06' + uleb(arch) + b'\x07' + uleb(profile) + b'\x1c' + uleb(vfp_args) + extra
    scope = b'\x01' + struct.pack('<I', 5 + len(values)) + values
    vendor = b'aeabi\0' + scope
    return b'A' + struct.pack('<I', 4 + len(vendor)) + vendor


def elf(abi, payload=b'SYNTHETIC-NATIVE-ABI-FIXTURE', *, arch=None, flags=None, attrs=None):
    elf_class, machine = SETTINGS[abi]
    size = 52 if elf_class == 1 else 64
    header = bytearray(size)
    header[:7] = b'\x7fELF' + bytes((elf_class, 1, 1))
    struct.pack_into('<HHI', header, 16, 3, machine, 1)
    struct.pack_into('<H', header, 40 if elf_class == 1 else 52, size)
    if machine != 40:
        return bytes(header) + payload
    struct.pack_into('<I', header, 36, 0x05000000 if flags is None else flags)
    if attrs is None:
        attrs = attributes(arch if arch is not None else (4 if abi == 'armeabi' else 10),
                           0 if abi == 'armeabi' else 0x41)
    offset = size + len(payload)
    section_offset = offset + len(attrs)
    struct.pack_into('<I', header, 32, section_offset)
    struct.pack_into('<HHH', header, 46, 40, 2, 0)
    sections = bytearray(80)
    struct.pack_into('<IIIIIIIIII', sections, 40, 0, 0x70000003, 0, 0, offset, len(attrs), 0, 0, 1, 0)
    return bytes(header) + payload + attrs + bytes(sections)
