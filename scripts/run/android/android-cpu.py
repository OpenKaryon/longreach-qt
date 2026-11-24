# SPDX-License-Identifier: GPL-3.0-or-later
"""Check retained guest x86 flags; absence is unqualified evidence, not CPUID proof."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

ABIS = ('armeabi', 'armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64')
# The base architecture is checked separately by guest ABI properties. These
# are the explicit additions selected by the repository's compiler recipes.
REQUIRED = {'x86': ('ssse3',),
            'x86_64': ('cx16', 'lahf_lm', 'pni', 'popcnt', 'ssse3', 'sse4_1', 'sse4_2')}
FIELDS = ('guest_cpuinfo_sha256', 'guest_cpu_baseline_sha256')


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def inspect(data, abi):
    if abi not in ABIS:
        raise ValueError('Unsupported guest CPU ABI: ' + abi)
    text = data.decode('utf-8-sig')
    if not text.strip():
        raise ValueError('Empty guest CPU evidence')
    required = REQUIRED.get(abi, ())
    result = {'schema_version': 1, 'abi': abi, 'policy': 'android-compiler-x86-additions-v1',
              'guest_cpuinfo_sha256': hashlib.sha256(data).hexdigest(),
              'required_flags': list(required), 'checked_x86_flags': bool(required),
              'processor_ids': [], 'common_flags': []}
    if not required:
        # Preserve and bind ARM evidence without claiming to validate its ISA.
        return result
    # Old ADB can preserve extra CRs, making every field appear separated by a
    # blank line. A new processor field, not blank lines, delimits each CPU.
    records, current = [], None
    for line in text.splitlines():
        if ':' not in line:
            continue
        key, value = line.split(':', 1)
        key = key.strip().lower()
        if key == 'processor':
            if current is not None:
                records.append(current)
            current = {'processor': value.strip()}
        elif key == 'flags':
            if current is None:
                raise ValueError('Missing guest CPU processor/flags evidence')
            if 'flags' in current:
                raise ValueError('Ambiguous guest CPU processor/flags field')
            current['flags'] = value.strip()
    if current is not None:
        records.append(current)
    processors, common = {}, None
    for values in records:
        if not re.fullmatch(r'[0-9]+', values.get('processor', '')) or not values.get('flags'):
            raise ValueError('Missing guest CPU processor/flags evidence')
        processor = int(values['processor'])
        if processor in processors:
            raise ValueError('Duplicate guest CPU processor ID')
        flags = set(values['flags'].lower().split())
        missing = sorted(set(required) - flags)
        if missing:
            raise ValueError(f'Guest CPU {processor} lacks required evidence flags: ' + ', '.join(missing))
        processors[processor] = flags
        common = flags if common is None else common & flags
    if not processors:
        raise ValueError('Missing guest CPU processor/flags evidence')
    result.update(processor_ids=sorted(processors), common_flags=sorted(common))
    return result


def validate(directory, abi, bindings=None):
    directory = Path(directory)
    source = directory / 'guest-cpuinfo.txt'
    report = directory / 'guest-cpu-baseline.json'
    result = inspect(source.read_bytes(), abi)
    report_data = report.read_bytes()
    if json.loads(report_data.decode('utf-8-sig')) != result:
        raise ValueError('Guest CPU baseline report differs from current evidence/policy')
    hashes = {FIELDS[0]: result[FIELDS[0]], FIELDS[1]: hashlib.sha256(report_data).hexdigest()}
    if bindings is not None and any(bindings.get(key) != value for key, value in hashes.items()):
        raise ValueError('Case belongs to different guest CPU evidence')
    return dict(hashes, guest_cpu_baseline=result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--abi', choices=ABIS, required=True)
    parser.add_argument('--cpuinfo', type=Path, required=True)
    args = parser.parse_args()
    # Read-only CLI. The owning runner writes the record under its own lease.
    print(json.dumps(inspect(args.cpuinfo.read_bytes(), args.abi), sort_keys=True, indent=2))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, UnicodeError) as error:
        sys.exit('Guest CPU validation failed: ' + str(error))
