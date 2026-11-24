# SPDX-License-Identifier: GPL-3.0-or-later
"""Run wrapper shell logic with inert argv-recording stand-ins, never Clang."""
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
if os.name == 'nt':
    BASH = next((str(path) for path in (Path('C:/Program Files/Git/bin/bash.exe'),
                                       Path('C:/Program Files/Git/usr/bin/bash.exe')) if path.is_file()), None)
else:
    BASH = shutil.which('bash')


def shell_path(path):
    value = Path(path).resolve().as_posix()
    return '/' + value[0].lower() + value[2:] if os.name == 'nt' else value


@unittest.skipUnless(BASH, 'Bash needed for ordinary wrapper argv fixtures')
class ClangWrapper(unittest.TestCase):
    def invoke(self, abi, arguments, name='cxx', expected_exit=0):
        with tempfile.TemporaryDirectory(prefix='longreach wrapper argv-') as temporary:
            root = Path(temporary)
            runtime, commands = root / 'runtime', root / 'recording-bin'
            runtime.mkdir()
            commands.mkdir()
            (runtime / 'target.sh').write_text(
                f"abi={shlex.quote(abi)}\ntarget=fixture-android21\nndk_triple=fixture-triple\nbuiltins_arch=fixture\narch_flags=(-march=fixture)\n", encoding='utf-8')
            wrapper = root / name
            source = (ROOT / 'scripts/build/qt6-android/clang-wrapper.sh').read_text()
            source = source.replace('prefix=/opt/longreach-android-api21', 'prefix=' + shlex.quote(shell_path(runtime)), 1)
            wrapper.write_text(source, encoding='utf-8', newline='\n')
            for compiler in ('clang-21', 'clang++-21'):
                path = commands / compiler
                path.write_text('#!/bin/bash\nprintf "%s\\0" "$0" "$@" > "$LONGREACH_WRAPPER_ARGS_LOG"\n', encoding='utf-8', newline='\n')
                path.chmod(0o755)
            log = root / 'arguments.bin'
            environment = dict(os.environ, PATH=str(commands)+os.pathsep+os.environ['PATH'],
                               LONGREACH_WRAPPER_ARGS_LOG=shell_path(log), MSYS_NO_PATHCONV='1', MSYS2_ARG_CONV_EXCL='*')
            result = subprocess.run([BASH, '--noprofile', '--norc', shell_path(wrapper), *arguments],
                env=environment, capture_output=True, text=True, timeout=8,
                creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
            self.assertEqual(result.returncode, expected_exit, result.stderr)
            if expected_exit:
                self.assertFalse(log.exists(), 'Rejected mode reached the compiler stand-in')
                return result.stderr
            values = log.read_bytes().decode().split('\0')[:-1]
            self.assertIn('/recording-bin/clang', values[0])
            return values[1:]

    def test_relocatable_link_has_no_pie_crt_or_default_runtime(self):
        for abi in ('armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64'):
            for flags in (['-r'], ['-Wl,-r'], ['-Xlinker', '--relocatable']):
                with self.subTest(abi=abi, flags=flags):
                    values = self.invoke(abi, [*flags, 'first object.o', 'second.o', '-o', 'partial.o'])
                    self.assertFalse(any('crtbegin' in value or 'crtend' in value for value in values), values)
                    self.assertNotIn('-pie', values)
                    self.assertNotIn('-lc++_shared', values)
                    self.assertFalse(any('builtins-' in value or 'no-undefined' in value for value in values))

    def test_shared_aliases_select_shared_crt_and_no_dynamic_interpreter(self):
        for abi in ('armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64'):
            for flags in (['-shared'], ['-Wl,-shared'], ['-Xlinker', '-shared'], ['--shared'], ['--for-linker', '-shared']):
                with self.subTest(abi=abi, flags=flags):
                    values = self.invoke(abi, [*flags, 'object.o', '-o', 'library.so'])
                    self.assertTrue(any(value.endswith('/crtbegin_so.o') for value in values))
                    self.assertTrue(any(value.endswith('/crtend_so.o') for value in values))
                    self.assertFalse(any('dynamic-linker' in value for value in values))
                    self.assertNotIn('-pie', values)

    def test_static_link_selects_static_crt_and_archives(self):
        for abi in ('armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64'):
            for flags in (['-static'], ['-Wl,-static'], ['-Xlinker', '--static']):
                with self.subTest(abi=abi, flags=flags):
                    values = self.invoke(abi, [*flags, 'object.o', '-o', 'program'])
                    self.assertTrue(any(value.endswith('/crtbegin_static.o') for value in values))
                    self.assertNotIn('-lc++_shared', values)
                    self.assertTrue(any(value.endswith('/libc++.a') for value in values))
                    self.assertTrue(any(value.endswith('/libc++abi.a') for value in values))
                    self.assertFalse(any('dynamic-linker' in value for value in values))

    def test_compile_and_no_input_diagnostic_queries_do_not_enter_link_phase(self):
        for arguments in (['-c','source with spaces.cpp'], ['-fsyntax-only','source.cpp'], ['--version'], ['-v'], ['-###'], []):
            with self.subTest(arguments=arguments):
                values = self.invoke('arm64-v8a', arguments)
                self.assertFalse(any('crtbegin' in value or 'crtend' in value for value in values))
                self.assertNotIn('-lc++_shared', values)

    def test_static_pie_uses_dynamic_crt_and_static_runtime_without_interpreter(self):
        for abi in ('armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64'):
            with self.subTest(abi=abi):
                values = self.invoke(abi, ['-static-pie', 'object.o'])
                self.assertIn('-static-pie', values)
                self.assertTrue(any(value.endswith('/crtbegin_dynamic.o') for value in values))
                self.assertTrue(any(value.endswith('/libc++.a') for value in values))
                self.assertFalse(any('dynamic-linker' in value for value in values))
                self.assertNotIn('-lc++_shared', values)

    def test_driver_runtime_suppression_flags_remain_effective(self):
        for flag, crt, libraries in (('-nostdlib', False, False), ('-nostartfiles', False, True), ('-nodefaultlibs', True, False)):
            with self.subTest(flag=flag):
                values = self.invoke('x86_64', [flag, 'object.o'])
                self.assertEqual(any('crtbegin' in value for value in values), crt)
                self.assertEqual('-lc++_shared' in values, libraries)
                self.assertEqual(any('builtins-' in value for value in values), libraries)
                self.assertEqual(any('tmpfile-android.o' in value for value in values), libraries)

    def test_c_entry_and_queries_preserve_original_arguments(self):
        for name in ('cc', 'clang', 'fixture-clang'):
            with self.subTest(name=name):
                values = self.invoke('arm64-v8a', ['-c', 'source with spaces.c', '-o', 'result with spaces.o'], name)
                self.assertNotIn('-nostdinc++', values)
                self.assertIn('source with spaces.c', values)
                self.assertFalse(any('crtbegin' in value for value in values))
        for extra in (['-v'], ['-###']):
            values = self.invoke('x86', ['object.o', *extra])
            self.assertIn(extra[0], values)
            self.assertTrue(any('crtbegin_dynamic.o' in value for value in values))
        values = self.invoke('x86', ['-no-pie', 'object.o'])
        self.assertIn('-no-pie', values)
        self.assertNotIn('-pie', values)

    def test_conflicting_shared_static_modes_fail_before_compiler(self):
        for flags in (['-shared', '-static'], ['-Xlinker', '-shared', '-Wl,-static'], ['-static-pie', '-shared']):
            with self.subTest(flags=flags):
                error = self.invoke('x86_64', [*flags, 'object.o'], expected_exit=2)
                self.assertIn('shared and static link modes cannot be combined', error)

    def test_default_executable_and_linker_option_operands_preserve_abi(self):
        for abi in ('armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64'):
            for extra in ([], ['-Wl,-rpath,-shared'], ['-Xlinker','-rpath','-Xlinker','-shared'],
                           ['-Wl,-rpath', '-Wl,-shared'], ['-include','-shared'], ['--', '-shared']):
                with self.subTest(abi=abi, extra=extra):
                    values = self.invoke(abi, ['object with spaces.o', *extra, '-o', 'program'])
                    interpreter = '/system/bin/linker64' if abi in ('arm64-v8a','x86_64') else '/system/bin/linker'
                    self.assertIn('-Wl,-dynamic-linker,'+interpreter, values)
                    self.assertIn('object with spaces.o', values)
                    self.assertTrue(any(value.endswith('/crtbegin_dynamic.o') for value in values))
                    self.assertIn('-lc++_shared', values)


if __name__ == '__main__':
    unittest.main()
