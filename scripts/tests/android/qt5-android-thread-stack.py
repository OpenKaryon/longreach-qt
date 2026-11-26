#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Exercise the actual stack-size adapter with recorded POSIX boundaries.

Freestanding Linux i386/amd64 controls require no multilib libc; they do not
qualify an Android ABI, actual pthread allocation or the public QThread API.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('patch', type=Path)
parser.add_argument('output', type=Path)
parser.add_argument('--compiler', default='g++')
args = parser.parse_args()
added = '\n'.join(line[1:] for line in args.patch.read_text().splitlines()
                  if line.startswith('+') and not line.startswith('+++'))
begin = added.index('static int qt_android_set_stack_size(')
end = added.index('\n}', begin) + 2
body = added[begin:end]
if 'qt_android_set_stack_size(&attr, d->stackSize)' not in added:
    raise RuntimeError('QThread does not invoke the tested adapter')
prefix = r'''
using size_t = __SIZE_TYPE__;
#define PAGE_SIZE 4096
#if LEGACY_PAGE_MINIMUM
#define PTHREAD_STACK_MIN (2 * PAGE_SIZE)
#else
#define PTHREAD_STACK_MIN 16384
#endif
#define EINVAL 22
#define _SC_PAGESIZE 1
struct pthread_attr_t { size_t observed; };
static long page_size = 4096;
static int calls = 0, forced_error = 0;
static long sysconf(int name) { return name == _SC_PAGESIZE ? page_size : -1; }
static int pthread_attr_setstacksize(pthread_attr_t *attr, size_t value) {
    ++calls;
    attr->observed = value;
    if (forced_error) return forced_error;
    const size_t alignment = page_size > 0 ? size_t(page_size) : 4096;
    return value < PTHREAD_STACK_MIN || value % alignment ? EINVAL : 0;
}
'''
suffix = r'''
static int check(size_t request, size_t expected, int result, int count) {
    pthread_attr_t attr{size_t(7)};
    calls = 0;
    const int code = qt_android_set_stack_size(&attr, request);
    return code == result && calls == count && (!count || attr.observed == expected);
}
static int tests() {
    if (!check(262144, 262144, 0, 1)) return 1;
    if (!check(262145, 266240, 0, 1)) return 2;
    if (!check(262161, 266240, 0, 1)) return 3;
    if (!check(266239, 266240, 0, 1)) return 4;
    if (!check(524305, 528384, 0, 1)) return 5;
    if (!check(PTHREAD_STACK_MIN - 1, PTHREAD_STACK_MIN - 1, EINVAL, 1)) return 6;
    if (!check(1, 1, EINVAL, 1)) return 7;
    if (!check(0, 0, EINVAL, 1)) return 8; // Public QThread zero bypasses the adapter.
    if (!check(PTHREAD_STACK_MIN, PTHREAD_STACK_MIN, 0, 1)) return 9;
    if (!check(~size_t(0), 0, EINVAL, 0)) return 10;
#if __SIZEOF_SIZE_T__ == 4
    if (!check(4294963200U, 4294963200U, 0, 1)) return 11;
#else
    if (!check(18446744073709547520ULL, 18446744073709547520ULL, 0, 1)) return 11;
#endif
    page_size = 16384;
    if (!check(262145, 278528, 0, 1)) return 12;
    if (!check(524305, 540672, 0, 1)) return 13;
    page_size = 65536;
    if (!check(262145, 327680, 0, 1)) return 14;
    page_size = -1;
    if (!check(262145, 262145, EINVAL, 1)) return 15;
    page_size = 0;
    if (!check(262144, 262144, 0, 1)) return 16;
    page_size = 4096;
    forced_error = 16;
    if (!check(262145, 266240, 16, 1)) return 17;
    return 0;
}
extern "C" __attribute__((noreturn)) void _start() {
    const int result = tests();
#if defined(__i386__)
    asm volatile("int $0x80" : : "a"(1), "b"(result) : "memory");
#elif defined(__x86_64__)
    asm volatile("syscall" : : "a"(60L), "D"(long(result)) : "rcx", "r11", "memory");
#else
#error This host control requires Linux i386 or amd64
#endif
    __builtin_unreachable();
}
'''
args.output.mkdir(parents=True, exist_ok=False)
source = args.output / 'stack.cpp'
source.write_text(prefix + body + suffix)
results = []
for bits in (32, 64):
    for optimization in (0, 2):
        for legacy_minimum in (0, 1):
            binary = args.output / f'stack-{bits}-O{optimization}-legacy{legacy_minimum}'
            command = [args.compiler, f'-m{bits}', f'-O{optimization}', '-std=c++17',
                       f'-DLEGACY_PAGE_MINIMUM={legacy_minimum}',
                       '-ffreestanding', '-fno-stack-protector', '-fno-exceptions', '-fno-rtti',
                       '-fno-pie', '-nostdlib', '-static', '-Wl,-e,_start', str(source), '-o', str(binary)]
            subprocess.run(command, check=True)
            completed = subprocess.run([str(binary)], timeout=5)
            if completed.returncode:
                raise RuntimeError(f'Stack adapter failed contract{completed.returncode}: {bits}/O{optimization}/legacy{legacy_minimum}')
            print(f'PASS: actual stack adapter {bits}-bit O{optimization} legacy-minimum{legacy_minimum}: 17 contracts', flush=True)
            results.append({'bits': bits, 'optimization': optimization, 'legacy_page_minimum': legacy_minimum,
                            'contracts': 17, 'exit': 0})
(args.output / 'result.json').write_text(json.dumps({
    'scope': 'Host stack-size adapter with recorded POSIX boundaries; no memory allocation',
    'android_guest_qualified': False, 'patch_sha256': hashlib.sha256(args.patch.read_bytes()).hexdigest(),
    'adapter_sha256': hashlib.sha256(body.encode()).hexdigest(), 'profiles': results,
}, indent=2) + '\n')
