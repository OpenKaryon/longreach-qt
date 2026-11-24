# SPDX-License-Identifier: GPL-3.0-or-later
"""Exercise legacy CRT callback ownership through real host DSO unloads.

The architecture defines select the ARM/x86 CRT branches, not guest execution.
The complete Android qualification separately checks the actual target ABI.
"""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
CC = shutil.which('cc')


@unittest.skipUnless(sys.platform.startswith('linux') and CC,
                     'Linux C compiler and dynamic loader needed')
class LegacyCrt(unittest.TestCase):
    def test_callbacks_belong_to_each_dso_on_arm_and_x86(self):
        for architecture in ('__arm__', '__i386__'):
            with self.subTest(architecture=architecture), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)

                def run(*arguments):
                    result = subprocess.run(arguments, capture_output=True, text=True, timeout=30)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    return result

                crt = root / 'crt.o'
                run(CC, '-fPIC', '-fvisibility=hidden', '-D' + architecture, '-c',
                    str(ROOT / 'scripts/build/qt4-android/crt-donut.c'), '-o', str(crt))
                library = root / 'callback.c'
                library.write_text('''
extern int atexit(void (*callback)(void));
__attribute__((visibility("default")))
int register_callback(void (*callback)(void)) { return atexit(callback); }
''')
                paths = [root / name for name in ('first.so', 'second.so')]
                for path in paths:
                    # Link the DSO directly to libc, without a host crtbegin or
                    # libc_nonshared.a supplying a replacement atexit wrapper.
                    run(CC, '-fPIC', '-fvisibility=hidden', '-shared', '-nostdlib',
                        '-Wl,--no-undefined', str(crt), str(library), '-l:libc.so.6', '-o', str(path))
                driver = root / 'driver.c'
                driver.write_text('''
#include <dlfcn.h>
#include <stdio.h>
typedef int (*registration)(void (*)(void));
static int sequence;
static void one(void) { sequence = sequence * 10 + 1; }
static void two(void) { sequence = sequence * 10 + 2; }
static void three(void) { sequence = sequence * 10 + 3; }
static void four(void) { sequence = sequence * 10 + 4; }
int main(int argc, char **argv) {
    if (argc != 3) return 1;
    void *first = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    void *second = dlopen(argv[2], RTLD_NOW | RTLD_LOCAL);
    if (!first || !second) { fprintf(stderr, "%s\\n", dlerror()); return 2; }
    registration a = (registration)dlsym(first, "register_callback");
    registration b = (registration)dlsym(second, "register_callback");
    if (!a || !b || a(one) || a(two) || b(three)) return 3;
    if (dlclose(first) || sequence != 21) return 4;
    if (dlclose(second) || sequence != 213) return 5;
    first = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!first) return 6;
    a = (registration)dlsym(first, "register_callback");
    if (!a || a(four) || dlclose(first) || sequence != 2134) return 7;
    puts("independent DSO callbacks, LIFO unload and reload: PASS");
    return 0;
}
''')
                executable = root / 'driver'
                run(CC, str(driver), '-ldl', '-o', str(executable))
                self.assertIn('PASS', run(str(executable), *(str(path) for path in paths)).stdout)


if __name__ == '__main__':
    unittest.main()
