#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Execute the actual API10 x86 futex trap as a freestanding Linux i386 probe.

No Android guest, libc, multilib headers or SDK build is needed. Kernel WAIT,
timeout and WAKE semantics are checked; this is not Android qualification.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('patch', type=Path)
parser.add_argument('output', type=Path)
parser.add_argument('--compiler', default='clang++-21')
args = parser.parse_args()
added = '\n'.join(line[1:] for line in args.patch.read_text().splitlines()
                  if line.startswith('+') and not line.startswith('+++'))
start = added.index('        const bool supported')
end = added.index('\n#  else', start)
body = added[start:end]
args.output.mkdir(parents=True, exist_ok=False)
prefix = r"""
using uint = unsigned int;
static volatile int errno_value;
#define errno errno_value
#define ENOSYS 38
#define FUTEX_WAIT 0
#define FUTEX_WAKE 1
#define FUTEX_PRIVATE_FLAG 128
#define __NR_futex 240
#define Q_ASSERT_X(c, w, m) ((void)0)
#define Q_UNLIKELY(c) __builtin_expect(!!(c), 0)
__attribute__((noinline)) static int trap(int *addr, int op, int val, void *val2,
                                         void *addr2 = nullptr, int val3 = 0) {
"""
suffix = r"""
    return result;
}
extern "C" void _start() {
    int word = 7;
    int code = 0;
    errno = 73;
    if (trap(&word, FUTEX_WAIT, 8, nullptr) != -1 || errno != 11) code = 1;
    struct { int sec, nsec; } timeout = {0, 1000000};
    if (!code && (trap(&word, FUTEX_WAIT, 7, &timeout) != -1 || errno != 110)) code = 2;
    if (!code && (trap(&word, FUTEX_WAKE, 1, nullptr) != 0 || errno != 110)) code = 3;
    asm volatile("int $0x80" : : "a"(1), "b"(code) : "memory");
    __builtin_unreachable();
}
"""
source = args.output / 'futex.cpp'
source.write_text(prefix + body + suffix)
results = []
for optimization in (0, 2):
    for frame in ('keep', 'omit'):
        binary = args.output / f'futex-O{optimization}-{frame}'
        command = [args.compiler, '-m32', '-fPIC', f'-O{optimization}',
                   '-fno-omit-frame-pointer' if frame == 'keep' else '-fomit-frame-pointer',
                   '-ffreestanding', '-fno-stack-protector', '-fno-exceptions', '-fno-rtti',
                   '-std=c++17', '-nostdlib', '-static', '-Wl,-e,_start', str(source), '-o', str(binary)]
        subprocess.run(command, check=True)
        result = subprocess.run([str(binary)], timeout=5)
        if result.returncode:
            raise RuntimeError(f'Futex contract failed at check {result.returncode}: O{optimization}/{frame}')
        print(f'PASS: actual futex asm O{optimization}/{frame}: EAGAIN, ETIMEDOUT, WAKE and errno/PIC', flush=True)
        results.append({'optimization': optimization, 'frame': frame, 'exit': result.returncode})
(args.output / 'result.json').write_text(json.dumps({
    'scope': 'host-linux-i386-futex-contract', 'android_guest_qualified': False,
    'patch_sha256': hashlib.sha256(args.patch.read_bytes()).hexdigest(), 'profiles': results,
}, sort_keys=True, indent=2) + '\n')
