# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""API4 driver argv contracts with an inert compiler; no native code executes."""
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

from test_android_clang_wrapper import BASH, shell_path

ROOT = Path(__file__).resolve().parents[3]


@unittest.skipUnless(BASH, 'Bash needed for ordinary API4 driver fixtures')
class Api4Driver(unittest.TestCase):
    def invoke(self, arguments, name='cxx'):
        with tempfile.TemporaryDirectory(prefix='api4 driver argv-') as temporary:
            root = Path(temporary)
            runtime, commands = root / 'runtime with spaces', root / 'recording-bin'
            runtime.mkdir()
            commands.mkdir()
            (runtime / 'target.sh').write_text('target=armv5te-linux-androideabi4\narch_flags=(-march=armv5te -mfloat-abi=soft)\n',
                                              encoding='utf-8', newline='\n')
            wrapper = root / name
            text = (ROOT / 'scripts/build/qt4-android/api4-clang-wrapper.sh').read_text()
            text = text.replace('prefix=/opt/longreach-android-api4',
                                'prefix=' + shlex.quote(shell_path(runtime)), 1)
            wrapper.write_text(text, encoding='utf-8', newline='\n')
            for compiler in ('clang-21', 'clang++-21'):
                path = commands / compiler
                path.write_text('#!/bin/bash\nprintf "%s\\0" "$0" "$@" > "$LONGREACH_WRAPPER_ARGS_LOG"\n',
                                encoding='utf-8', newline='\n')
                path.chmod(0o755)
            log = root / 'arguments.bin'
            env = dict(os.environ, PATH=str(commands) + os.pathsep + os.environ['PATH'],
                       LONGREACH_WRAPPER_ARGS_LOG=shell_path(log), MSYS_NO_PATHCONV='1', MSYS2_ARG_CONV_EXCL='*')
            result = subprocess.run([BASH, '--noprofile', '--norc', shell_path(wrapper), *arguments],
                                    env=env, text=True, capture_output=True, timeout=10,
                                    creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
            self.assertEqual(result.returncode, 0, result.stderr)
            values = log.read_bytes().decode().split('\0')[:-1]
            self.assertIn('/recording-bin/clang', values[0])
            self.assertIn('--target=armv5te-linux-androideabi4', values)
            self.assertIn('-march=armv5te', values)
            self.assertIn('-mfloat-abi=soft', values)
            return values[1:]

    def test_compile_queries_and_c_entry_do_not_link_runtime(self):
        for args in (['-c', 'source with spaces.cpp'], ['-fsyntax-only', 'source.cpp'],
                     ['--version'], ['-v'], ['-###'], []):
            with self.subTest(args=args):
                values = self.invoke(args)
                self.assertFalse(any('crt' in v or v.endswith('.a') for v in values))
        values = self.invoke(['-c', 'source with spaces.c', '-o', 'output with spaces.o'], 'cc')
        self.assertNotIn('-nostdinc++', values)
        self.assertIn('source with spaces.c', values)
        self.assertIn('output with spaces.o', values)

    def test_partial_links_do_not_acquire_shared_crt_or_libraries(self):
        for mode in (['-r'], ['-Wl,-r'], ['-Xlinker', '--relocatable']):
            with self.subTest(mode=mode):
                values = self.invoke([*mode, 'first object.o', 'second.o', '-o', 'partial.o'])
                self.assertIn('-nostdlib', values)
                self.assertNotIn('-shared', values)
                self.assertFalse(any('crt' in v or v.endswith('.a') for v in values))

    def test_shared_jni_uses_dso_shim_and_complete_static_cpp_runtime(self):
        for mode in (['-shared'], ['-Wl,-shared'], ['-Xlinker', '-shared']):
            with self.subTest(mode=mode):
                values = self.invoke([*mode, 'object.o', '-o', 'libsample.so'])
                for name in ('crt-donut.o', 'armv5-compat.o', 'tmpfile-donut.o', 'libc++.a',
                             'libc++experimental.a', 'libc++abi.a', 'libunwind.a', 'libclang_rt.builtins-arm-android.a'):
                    self.assertTrue(any(v.endswith('/' + name) for v in values), name)
                self.assertNotIn('-lc++_shared', values)
                self.assertFalse(any('dynamic-linker' in v or 'crtbegin_' in v for v in values))

    def test_executable_uses_api4_crt_layout_and_non_pie_default(self):
        values = self.invoke(['object.o', '-o', 'sample'])
        self.assertIn('-no-pie', values)
        self.assertIn('-Wl,-dynamic-linker,/system/bin/linker', values)
        self.assertTrue(any(v.endswith('/sysroot/usr/lib/crtbegin_dynamic.o') for v in values))
        self.assertTrue(any(v.endswith('/sysroot/usr/lib/crtend_android.o') for v in values))
        self.assertFalse(any(v.endswith('/crt-donut.o') or '/21/' in v for v in values))
        values = self.invoke(['-static', 'object.o'])
        self.assertTrue(any(v.endswith('/crtbegin_static.o') for v in values))
        self.assertFalse(any('dynamic-linker' in v for v in values))

    def test_explicit_suppression_and_linker_operands_remain_effective(self):
        for flag, startup, runtime in (('-nostdlib', False, False), ('-nostartfiles', False, True),
                                       ('-nodefaultlibs', True, False)):
            values = self.invoke([flag, '-shared', 'object.o'])
            self.assertEqual(any(v.endswith('/crt-donut.o') for v in values), startup)
            self.assertEqual(any(v.endswith('/libc++.a') for v in values), runtime)
        for flags in (['-Wl,-rpath,-shared'], ['-include', '-shared'],
                      ['-Xlinker', '-rpath', '-Xlinker', '-shared']):
            values = self.invoke(['object.o', *flags])
            self.assertTrue(any(v.endswith('/crtbegin_dynamic.o') for v in values))
            self.assertFalse(any(v.endswith('/crt-donut.o') for v in values))


if __name__ == '__main__':
    unittest.main()
