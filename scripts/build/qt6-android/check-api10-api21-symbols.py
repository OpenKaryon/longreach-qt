# SPDX-License-Identifier: GPL-3.0-or-later
"""Compare API10 SDK dynamic imports with its dependencies and pinned API21 stubs.

This is a symbol-name availability check, not an Android loader implementation.
Target libraries and platform stubs are read as ELF data, never loaded or executed.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path, PurePosixPath
import struct
import tempfile
import zipfile

ARCHIVE = 'android-ndk-r27-linux.zip'
TRIPLES = {'x86': 'i686-linux-android', 'armeabi-v7a': 'arm-linux-androideabi'}
REQUIRED_PLATFORM = {'libc.so', 'libm.so', 'libdl.so', 'liblog.so'}

# Audited optional calls, not a general weak-symbol exemption. The producer
# must supply the exact source that was compiled; a changed guard requires a
# fresh review. Current x86 object disassembly also retains both NULL checks.
GUARDED_WEAK_IMPORTS = {
    '__pthread_cond_timedwait_relative': {
        'module': 'Core', 'source_key': 'qt_wait',
        'source_sha256': '54f008c93e10247f04137aa94530082356e85ad996b4591030e7395ac8cf9945',
        'source': 'Qt 5.15.19 qtbase/src/corelib/thread/qwaitcondition_unix.cpp',
        'guard': '!local_condattr_setclock && local_cond_timedwait_relative',
        'fallback': 'pthread_cond_timedwait; API21 pthread_condattr_setclock selects monotonic clock',
    },
    'getentropy': {
        'module': 'Network', 'source_key': 'openssl_rand',
        'source_sha256': '488e3d6c9ff70159168d47b216a3604a17d95c58eced3fff139a4a23b2e866dd',
        'source': 'OpenSSL 3.5.7 providers/implementations/rands/seeding/rand_unix.c',
        'guard': 'getentropy != NULL; failure with ENOSYS also falls through',
        'fallback': 'remaining configured OpenSSL entropy sources',
    },
}


def digest(path):
    with path.open('rb') as stream:
        result = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(block)
        return result.hexdigest()


def symbols(path, abi):
    data = path.read_bytes()
    machine = {'x86': 3, 'armeabi-v7a': 40}[abi]
    if (len(data) < 52 or data[:7] != b'\x7fELF\x01\x01\x01'
            or struct.unpack_from('<HHI', data, 16) != (3, machine, 1)):
        raise ValueError('Expected target ELF32 ET_DYN symbol input: ' + str(path))

    def area(start, size):
        if start < 0 or size < 0 or start + size > len(data):
            raise ValueError('Truncated ELF symbol metadata: ' + str(path))
        return data[start:start + size]

    start = struct.unpack_from('<I', data, 32)[0]
    entry_size, count = struct.unpack_from('<HH', data, 46)
    if not start or entry_size != 40 or not count:
        raise ValueError('ELF dynamic-symbol sections required: ' + str(path))
    raw = area(start, count * entry_size)
    sections = [struct.unpack_from('<10I', raw, index * entry_size) for index in range(count)]
    selected = [(index, section) for index, section in enumerate(sections) if section[1] == 11]
    if len(selected) != 1:
        raise ValueError('Expected one ELF dynamic-symbol table: ' + str(path))
    index, section = selected[0]
    if section[9] != 16 or section[5] % 16 or section[6] >= len(sections):
        raise ValueError('Invalid ELF dynamic-symbol table: ' + str(path))
    strings = sections[section[6]]
    if strings[1] != 3:
        raise ValueError('ELF dynamic-symbol strings are not SHT_STRTAB')
    strings = area(strings[4], strings[5])
    table = area(section[4], section[5])
    versions = [item for item in sections if item[1] == 0x6fffffff and item[6] == index]
    if len(versions) > 1:
        raise ValueError('Duplicate ELF symbol-version table')
    version_data = area(versions[0][4], versions[0][5]) if versions else None
    if version_data is not None and len(version_data) != len(table) // 8:
        raise ValueError('Invalid ELF symbol-version table')
    result = {'defined': set(), 'undefined': set(), 'undefined_weak': set(), 'undefined_strong': set()}
    for index, position in enumerate(range(0, len(table), 16)):
        name, _, _, info, visibility, section_index = struct.unpack_from('<IIIBBH', table, position)
        if not name or info >> 4 not in (1, 2):
            continue
        end = strings.find(b'\0', name) if name < len(strings) else -1
        if end < 0:
            raise ValueError('Invalid ELF dynamic-symbol name')
        name = strings[name:end].decode('utf-8', errors='strict')
        version = struct.unpack_from('<H', version_data, index * 2)[0] if version_data is not None else 1
        if not section_index:
            if (version & 0x7fff) > 1:
                raise ValueError('Versioned API10 imports require separate qualification: ' + name)
            result['undefined'].add(name)
            result['undefined_weak' if info >> 4 == 2 else 'undefined_strong'].add(name)
        elif (visibility & 3) in (0, 3) and (version & 0x7fff) != 0 and not (version & 0x8000):
            result['defined'].add(name)
    return result


def sdk_inputs(prefix, runtime):
    # Keep aliases so DT_NEEDED is matched against actual installed filenames.
    paths = {path for directory in ('lib', 'plugins', 'qml')
             for path in (prefix / directory).rglob('*.so') if path.is_file()}
    paths.add(runtime)
    if not runtime.is_file() or len({path.resolve() for path in paths}) < 2:
        raise ValueError('Expected the API10 runtime and Qt target libraries')
    result = {}
    for path in sorted(paths):
        key = 'runtime/libc++_shared.so' if path == runtime else path.relative_to(prefix).as_posix()
        result[key] = path
    return result


def guarded_optional_imports(key, abi, missing, table, guard_sources):
    accepted = []
    for name in sorted(missing):
        policy = GUARDED_WEAK_IMPORTS.get(name)
        if (policy is None or key != f'lib/libQt5{policy["module"]}_{abi}.so'
                or name not in table['undefined_weak'] or name in table['undefined_strong']):
            continue
        source = (guard_sources or {}).get(policy['source_key'])
        if source is None or not source.is_file() or digest(source) != policy['source_sha256']:
            raise ValueError(f'Audited optional weak import requires unchanged guard source: {key}: {name}')
        accepted.append({'name': name, 'policy': 'qt5-api10-guarded-weak-v1',
                         'source_sha256': policy['source_sha256'], 'source': policy['source'],
                         'guard': policy['guard'], 'fallback': policy['fallback']})
    return accepted


def validate(prefix, runtime, abi, archive, lock_path, guard_sources=None):
    if abi not in TRIPLES:
        raise ValueError('Forward availability policy supports only API10 ARMv7/x86')
    lock = json.loads(lock_path.read_text(encoding='utf-8-sig'))
    records = [record for record in lock['sources'] if record.get('file') == ARCHIVE]
    if len(records) != 1 or digest(archive) != records[0]['sha256']:
        raise ValueError('Pinned API21 NDK archive SHA256 mismatch')
    source = Path(__file__).with_name('validate-api21-elf.py')
    spec = importlib.util.spec_from_file_location('forward_sdk_metadata', source)
    metadata = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(metadata)
    sdk = sdk_inputs(prefix, runtime)
    inputs, table, dependencies, by_name = {}, {}, {}, {}
    for key, path in sdk.items():
        inputs[key] = digest(path)
        dependencies[key] = metadata.inspect(path, abi, 10)['needed']
        table[key] = symbols(path, abi)
        by_name.setdefault(path.name, []).append(key)
    # Duplicate aliases may point to identical bytes; competing definitions may
    # not silently resolve to whichever directory happens to be traversed first.
    for name, keys in by_name.items():
        if len({inputs[key] for key in keys}) != 1:
            raise ValueError('Ambiguous SDK dependency filename: ' + name)
    platform_hashes, platform, linker_scripts = {}, {}, {}
    member_prefix = ('android-ndk-r27/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/'
                     + TRIPLES[abi] + '/21/')
    with zipfile.ZipFile(archive) as package, tempfile.TemporaryDirectory(prefix='android-api21-exports-') as temporary:
        for member in package.infolist():
            if member.is_dir() or not member.filename.startswith(member_prefix):
                continue
            relative = member.filename[len(member_prefix):]
            if not relative.endswith('.so'):
                continue
            if len(PurePosixPath(relative).parts) != 1 or '\\' in relative or relative in platform or relative in linker_scripts:
                raise ValueError('Unexpected or duplicate API21 platform stub path')
            path = Path(temporary) / relative
            data = package.read(member)
            path.write_bytes(data)
            if relative == 'libc++.so' and data.strip() == b'INPUT(-lc++_shared)':
                # This pinned NDK file is a linker script, not an Android DSO.
                # libc++_shared.so must come from the SDK dependency closure.
                linker_scripts[relative] = digest(path)
                continue
            platform_hashes[relative] = digest(path)
            platform[relative] = symbols(path, abi)['defined']
    if not REQUIRED_PLATFORM <= platform.keys():
        raise ValueError('API21 platform lacks required libc/libm/libdl/liblog stubs')
    if set(platform) & set(by_name):
        raise ValueError('SDK library shadows an API21 platform dependency')
    results = []
    for key in sorted(sdk):
        available = set(table[key]['defined'])
        seen, pending = set(), list(dependencies[key])
        while pending:
            name = pending.pop()
            if name in seen:
                continue
            seen.add(name)
            if name in platform:
                available.update(platform[name])
            elif name in by_name:
                target = by_name[name][0]
                available.update(table[target]['defined'])
                pending.extend(dependencies[target])
            else:
                raise ValueError(f'Missing API21 dependency for {key}: {name}')
        missing = table[key]['undefined'] - available
        optional = guarded_optional_imports(key, abi, missing, table[key], guard_sources)
        missing = sorted(missing - {entry['name'] for entry in optional})
        if missing:
            raise ValueError(f'API21 symbol names unavailable for {key}: ' + ', '.join(missing))
        results.append({'path': key, 'sha256': inputs[key],
                        'needed_closure': sorted(seen),
                        'checked_import_names': sorted(table[key]['undefined']),
                        'guarded_optional_weak_imports': optional})
    return {'schema_version': 1, 'abi': abi, 'source_api': 10, 'platform_api': 21,
            'validation_scope': 'dependency-symbol-name-availability-with-source-bound-optional-weak-v2',
            'symbol_resolution_verified': False, 'runtime_loading_verified': False,
            'unresolved_weak_imports_ignored': any(item['guarded_optional_weak_imports'] for item in results),
            'blanket_weak_import_exemption': False,
            'checker_sha256': digest(Path(__file__)), 'elf_policy_sha256': digest(source),
            'platform_lock_sha256': digest(lock_path),
            'platform_archive_sha256': records[0]['sha256'],
            'platform_stub_sha256': platform_hashes,
            'excluded_platform_linker_scripts_sha256': linker_scripts, 'libraries': results}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('prefix', type=Path)
    parser.add_argument('--runtime', type=Path, default=Path('/opt/longreach-android/lib/libc++_shared.so'))
    parser.add_argument('--abi', required=True, choices=tuple(TRIPLES))
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--lock', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--qt-wait-source', type=Path)
    parser.add_argument('--openssl-rand-source', type=Path)
    args = parser.parse_args(argv)
    args.report.unlink(missing_ok=True)
    report = validate(args.prefix, args.runtime, args.abi, args.archive, args.lock,
                      {'qt_wait': args.qt_wait_source, 'openssl_rand': args.openssl_rand_source})
    temporary = args.report.with_suffix(args.report.suffix + '.tmp')
    try:
        temporary.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n', encoding='utf-8')
        temporary.replace(args.report)
    finally:
        temporary.unlink(missing_ok=True)
    print(f'API10 {args.abi}: API21 dependency symbol names checked in {len(report["libraries"])} SDK libraries; runtime loading unverified')
    return report


if __name__ == '__main__':
    main()
