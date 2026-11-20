# SPDX-License-Identifier: GPL-3.0-or-later

"""Record exact platform input files and final target runtime, without changing inputs."""
import hashlib
import json
import os
from pathlib import Path

abi = os.environ.get('ANDROID_ABI', 'armeabi-v7a')
triple, target = {
    'armeabi-v7a': ('arm-linux-androideabi', 'armv7a-linux-androideabi21'),
    'arm64-v8a': ('aarch64-linux-android', 'aarch64-linux-android21'),
    'x86': ('i686-linux-android', 'i686-linux-android21'),
    'x86_64': ('x86_64-linux-android', 'x86_64-linux-android21'),
}[abi]
prefix = Path('/opt/longreach-android-api21')
ndk = Path('/ndk')
original = ndk / 'toolchains/llvm/prebuilt/linux-x86_64/sysroot'


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


inputs = {}
for root in (original / f'usr/lib/{triple}/21', ndk / 'sources/android/cpufeatures'):
    for path in sorted(root.rglob('*')):
        if path.is_file():
            inputs[str(path.relative_to(ndk))] = sha256(path)
headers = {str(path.relative_to(prefix / 'sysroot')): sha256(path)
           for path in sorted((prefix / 'sysroot/usr/include').rglob('*')) if path.is_file()}
cxx_headers = {str(path.relative_to(prefix / 'include/c++/v1')): sha256(path)
               for path in sorted((prefix / 'include/c++/v1').rglob('*')) if path.is_file()}
manifest = {
    'ndk_source_properties': (ndk / 'source.properties').read_text(),
    'ndk_platform_input_hashes': inputs,
    'effective_header_sha256': headers,
    'consumer_cxx_header_root': str(prefix / 'include/c++/v1'),
    'consumer_cxx_header_sha256': cxx_headers,
    'llvm_version': '21.1.8',
    'target': target, 'abi': abi,
    'libcxx_shared_sha256': sha256(prefix / 'lib/libc++_shared.so'),
    'sysroot_fixes': ['AHARDWAREBUFFER_USAGE_FRONT_BUFFER uses 1ULL << 32 (same as NDK r28)'],
}
if abi == 'x86':
    atomic_source = Path('/work/api21/llvm-project-21.1.8.src/compiler-rt/lib/builtins/atomic.c')
    manifest['generic_atomic_provider'] = {
        'implementation': 'upstream compiler-rt 21.1.8 atomic.c',
        'source_sha256': sha256(atomic_source),
        'shared_library': 'libc++_shared.so',
        'lock_backend': 'pthread',
    }
destination = Path('/out/platform-input-provenance.json')
destination.write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
print(f'Recorded {len(inputs)} platform/CPU-feature inputs and {len(headers)} effective headers')
