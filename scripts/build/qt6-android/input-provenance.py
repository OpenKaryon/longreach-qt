# SPDX-License-Identifier: GPL-3.0-or-later

"""Record exact platform input files and final target runtime, without changing inputs."""
import hashlib
import json
from pathlib import Path

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
for root in (original / 'usr/lib/arm-linux-androideabi/21', ndk / 'sources/android/cpufeatures'):
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
    'target': 'armv7a-linux-androideabi21',
    'libcxx_shared_sha256': sha256(prefix / 'lib/libc++_shared.so'),
    'sysroot_fixes': ['AHARDWAREBUFFER_USAGE_FRONT_BUFFER uses 1ULL << 32 (same as NDK r28)'],
}
destination = Path('/out/platform-input-provenance.json')
destination.write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
print(f'Recorded {len(inputs)} platform/CPU-feature inputs and {len(headers)} effective headers')
