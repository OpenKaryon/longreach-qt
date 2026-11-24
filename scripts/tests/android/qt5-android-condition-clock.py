#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Host pthread timeout regression using an actual extracted Qt source function.

Pass qwaitcondition_unix.cpp from the prepared Qt source and an empty output
folder. This checks clock selection, not Android ABI/runtime qualification.
Requires a Linux host with clang++-21 and pthreads.
"""
import argparse
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('source', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
source = args.source.read_text()
begin = source.index('void qt_initialize_pthread_cond(')
end = source.index('\nvoid qt_abstime_for_timeout(', begin)
function = source[begin:end]
args.output.mkdir(parents=True, exist_ok=True)
prefix = r'''
#include <pthread.h>
#include <time.h>
#include <cstdio>
#include <cerrno>
#undef _POSIX_MONOTONIC_CLOCK
#define _POSIX_MONOTONIC_CLOCK HEADER_CLOCK
struct QElapsedTimer {
    enum ClockType { SystemTime, MonotonicClock };
    static ClockType clockType() { return USE_MONOTONIC ? MonotonicClock : SystemTime; }
};
static void report_error(int code, const char*, const char*) { if (code) __builtin_trap(); }
static int (*local_condattr_setclock)(pthread_condattr_t*, clockid_t) =
    HAVE_CLOCK ? pthread_condattr_setclock : nullptr;
'''
suffix = r'''
static long long nanoseconds(timespec value) {
    return (long long)value.tv_sec * 1000000000 + value.tv_nsec;
}
int main() {
    pthread_cond_t cond;
    pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;
    qt_initialize_pthread_cond(&cond, "probe");
    timespec deadline, start, finish;
    clock_gettime(EXPECT_MONOTONIC ? CLOCK_MONOTONIC : CLOCK_REALTIME, &deadline);
    deadline.tv_nsec += 60000000;
    if (deadline.tv_nsec >= 1000000000) { ++deadline.tv_sec; deadline.tv_nsec -= 1000000000; }
    pthread_mutex_lock(&mutex);
    clock_gettime(CLOCK_MONOTONIC, &start);
    int result = pthread_cond_timedwait(&cond, &mutex, &deadline);
    clock_gettime(CLOCK_MONOTONIC, &finish);
    pthread_mutex_unlock(&mutex);
    pthread_cond_destroy(&cond);
    pthread_mutex_destroy(&mutex);
    long long elapsed = nanoseconds(finish) - nanoseconds(start);
    std::printf("result=%d elapsed_ns=%lld\n", result, elapsed);
    return result == ETIMEDOUT && elapsed >= 20000000 && elapsed < 2000000000 ? 0 : 1;
}
'''
program = args.output / 'clock.cpp'
program.write_text(prefix + function + suffix)
profiles = [
    ('android-api21-old-headers', 1, -1, 1, 1, 1),
    ('android-api10-old-headers', 1, -1, 0, 1, 0),
    ('android-system-clock', 1, -1, 1, 0, 0),
    ('posix-monotonic', 0, 0, 1, 1, 1),
    ('posix-system-clock', 0, -1, 1, 0, 0),
]
failures = 0
for name, android, header, available, monotonic, expected in profiles:
    binary = args.output / name
    command = ['clang++-21', '-std=c++17', '-pthread', '-O2',
               f'-DHEADER_CLOCK={header}', f'-DHAVE_CLOCK={available}',
               f'-DUSE_MONOTONIC={monotonic}', f'-DEXPECT_MONOTONIC={expected}']
    if android:
        command.append('-DQ_OS_ANDROID')
    subprocess.run(command + [str(program), '-o', str(binary)], check=True)
    result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=5)
    print(name, result.returncode, result.stdout.strip(), flush=True)
    failures += result.returncode != 0
raise SystemExit(bool(failures))
