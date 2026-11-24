# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Check shared-library ELF/ARM ABI metadata before packaging and collection."""
import argparse
import io
from pathlib import Path
import struct
import sys
import zipfile

SETTINGS = {'armeabi': (1, 40), 'armeabi-v7a': (1, 40), 'arm64-v8a': (2, 183),
            'x86': (1, 3), 'x86_64': (2, 62)}
ARM_ATTRIBUTES = 0x70000003


def inspect_header(header, abi, label='native library'):
    """Header checks only; use inspect_stream/bytes for the ARM attribute proof."""
    elf_class, machine = SETTINGS[abi]
    expected = 52 if elf_class == 1 else 64
    if (len(header) < expected or header[:7] != b'\x7fELF' + bytes((elf_class, 1, 1))
            or struct.unpack_from('<H', header, 18)[0] != machine):
        raise ValueError(f'Native library does not match {abi}: {label}')
    if struct.unpack_from('<H', header, 16)[0] != 3 or struct.unpack_from('<I', header, 20)[0] != 1:
        raise ValueError(f'Expected ET_DYN/current ELF version: {label}')
    ehsize = struct.unpack_from('<H', header, 40 if elf_class == 1 else 52)[0]
    if ehsize != expected:
        raise ValueError(f'Invalid ELF header size: {label}')
    flags = struct.unpack_from('<I', header, 36 if elf_class == 1 else 48)[0]
    if machine == 40:
        if flags & 0xff000000 != 0x05000000:
            raise ValueError(f'Expected ARM EABI5: {label}')
        if flags & 0x400:
            raise ValueError(f'ARM hard-float calling convention is unsupported: {label}')
        if flags & 0x00800000:
            raise ValueError(f'Big-endian ARM instructions are unsupported: {label}')
    return {'elf_bits': 32 if elf_class == 1 else 64, 'machine': machine,
            'elf_type': 3, 'flags': flags, 'header_size': expected}


def read_at(stream, offset, count, length, label):
    if offset < 0 or count < 0 or offset > length or count > length - offset:
        raise ValueError('Truncated ELF metadata: ' + label)
    stream.seek(offset)
    data = stream.read(count)
    if len(data) != count:
        raise ValueError('Truncated ELF metadata: ' + label)
    return data


def uleb(data, position, end):
    value = 0
    for shift in range(0, 35, 7):
        if position >= end:
            raise ValueError('Truncated ARM attribute value')
        byte = data[position]
        position += 1
        value |= (byte & 0x7f) << shift
        if not byte & 0x80:
            return value, position
    raise ValueError('Invalid ARM attribute value')


def ntbs(data, position, end):
    stop = data.find(b'\0', position, end)
    if stop < 0:
        raise ValueError('Truncated ARM attribute string')
    return data[position:stop], stop + 1


def arm_file_attributes(data):
    """Read aeabi File scopes using the Arm addenda32 attribute encoding."""
    if not data or data[0] != ord('A'):
        raise ValueError('Unsupported ARM attributes format')
    position, scopes = 1, []
    while position < len(data):
        start = position
        if len(data) - start < 4:
            raise ValueError('Truncated ARM vendor section')
        length = struct.unpack_from('<I', data, start)[0]
        if length < 5 or length > len(data) - start:
            raise ValueError('Invalid ARM vendor section length')
        end = start + length
        vendor, position = ntbs(data, start + 4, end)
        if vendor != b'aeabi':
            position = end
            continue
        while position < end:
            start = position
            scope, position = uleb(data, position, end)
            if end - position < 4:
                raise ValueError('Truncated ARM scope length')
            length = struct.unpack_from('<I', data, position)[0]
            position += 4
            if length < position - start or length > end - start:
                raise ValueError('Invalid ARM scope length')
            stop = start + length
            if scope != 1:
                # Section/Symbol overrides cannot be inferred from File alone.
                raise ValueError('Unsupported ARM attribute scope')
            values = {}
            while position < stop:
                tag, position = uleb(data, position, stop)
                if tag in (4, 5) or (tag >= 32 and tag & 1):
                    value, position = ntbs(data, position, stop)
                else:
                    value, position = uleb(data, position, stop)
                    if tag == 32:
                        vendor_name, position = ntbs(data, position, stop)
                        value = (value, vendor_name)
                if tag in values and values[tag] != value:
                    raise ValueError('Conflicting ARM file attributes')
                values[tag] = value
            scopes.append(values)
    if not scopes:
        raise ValueError('Missing aeabi File attributes')
    return scopes


def arm_metadata(stream, header, length, abi, label):
    table = struct.unpack_from('<I', header, 32)[0]
    entry_size, count = struct.unpack_from('<HH', header, 46)
    if not table or entry_size != 40:
        raise ValueError('Missing ARM attribute section table: ' + label)
    if not count:
        first = read_at(stream, table, entry_size, length, label)
        if struct.unpack_from('<I', first, 4)[0] != 0:
            raise ValueError('Invalid extended ELF section count: ' + label)
        count = struct.unpack_from('<I', first, 20)[0]
    entries = read_at(stream, table, entry_size * count, length, label)
    attribute_sections = []
    for index in range(count):
        kind, offset, size = struct.unpack_from('<I8xII', entries, index * entry_size + 4)
        if kind == ARM_ATTRIBUTES:
            attribute_sections.append(read_at(stream, offset, size, length, label))
    if len(attribute_sections) != 1:
        raise ValueError('Missing or ambiguous ARM attributes section: ' + label)
    try:
        records = arm_file_attributes(attribute_sections[0])
    except ValueError as error:
        raise ValueError(str(error) + ': ' + label) from error
    for values in records:
        if 64 in values:
            raise ValueError('Undefined ARM attribute defaults: ' + label)
        arch = values.get(6)
        # Tag_CPU_arch enum values 0..5 are pre-v4..v5TEJ; 6..10 are
        # compatible v6/v7 variants. Later M-profile enums are not ordered ISA.
        allowed = range(6) if abi == 'armeabi' else range(11)
        if arch not in allowed:
            raise ValueError(f'ARM CPU architecture does not match {abi}: {label}')
        if values.get(7, 0) not in (0, 0x41, 0x53):
            raise ValueError('Non-application ARM profile: ' + label)
        if arch <= 5 and values.get(9, 0) not in (0, 1, 3):
            raise ValueError('Thumb2 is incompatible with the ARMv5 baseline: ' + label)
        if values.get(28, 0) not in (0, 3):
            raise ValueError('ARM VFP argument calling convention is unsupported: ' + label)
        if values.get(29, 0):
            raise ValueError('ARM WMMX argument calling convention is unsupported: ' + label)
    return {'arm_cpu_arch': sorted({values[6] for values in records}),
            'arm_vfp_args': sorted({values.get(28, 0) for values in records})}


def inspect_stream(stream, abi, label='native library', length=None):
    if length is None:
        stream.seek(0, 2)
        length = stream.tell()
    stream.seek(0)
    header = stream.read(64)
    result = inspect_header(header, abi, label)
    if result['machine'] == 40:
        result.update(arm_metadata(stream, header, length, abi, label))
    return result


def inspect_bytes(data, abi, label='native library'):
    return inspect_stream(io.BytesIO(data), abi, label, len(data))


def inspect(path, abi):
    with Path(path).open('rb') as stream:
        return inspect_stream(stream, abi, str(path))


def inspect_apk(path, abi):
    try:
        with zipfile.ZipFile(path) as archive:
            libraries = [member for member in archive.infolist()
                         if member.filename.startswith('lib/') and member.filename.endswith('.so')]
            names = [member.filename for member in libraries]
            if (not names or len(names) != len(set(names))
                    or any(len(name.split('/')) != 3 or name.split('/')[1] != abi for name in names)):
                raise ValueError('Missing, duplicate or mixed native ABI: ' + str(path))
            result = []
            for member in libraries:
                with archive.open(member) as stream:
                    metadata = inspect_stream(stream, abi, str(path) + ':' + member.filename, member.file_size)
                result.append(dict(member=member.filename, **metadata))
            return result
    except zipfile.BadZipFile as error:
        raise ValueError('Invalid native APK archive: ' + str(path)) from error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--abi', choices=SETTINGS, required=True)
    parser.add_argument('libraries', type=Path, nargs='+')
    args = parser.parse_args()
    for path in args.libraries:
        inspect(path, args.abi)
    print(f'Native ABI {args.abi}: {len(args.libraries)} libraries PASS')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError) as error:
        sys.exit(f'Native ABI validation failed: {error}')
