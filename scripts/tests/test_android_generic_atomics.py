# SPDX-License-Identifier: GPL-3.0-or-later
"""Actual producer shell fragments with inert tool/metadata stand-ins only."""
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
BASH = (next((str(p) for p in (Path('C:/Program Files/Git/bin/bash.exe'),
                              Path('C:/Program Files/Git/usr/bin/bash.exe')) if p.is_file()), None)
        if os.name == 'nt' else shutil.which('bash'))
SYMBOLS = ('__atomic_load', '__atomic_store', '__atomic_exchange',
           '__atomic_compare_exchange', '__atomic_is_lock_free')


def shell_path(path):
    value = Path(path).resolve().as_posix()
    return '/' + value[0].lower() + value[2:] if os.name == 'nt' else value


@unittest.skipUnless(BASH, 'Bash needed for ordinary producer argv fixtures')
class GenericAtomics(unittest.TestCase):
    def run_fragment(self, family, abi, mode='ready', fragment='link'):
        with tempfile.TemporaryDirectory(prefix='android generic atomics-') as temporary:
            root = Path(temporary)
            tools, prefix, runtime = root / 'tools', root / 'prefix', root / 'runtime'
            for directory in (tools, prefix / 'lib', runtime / 'lib', root / 'out'):
                directory.mkdir(parents=True, exist_ok=True)
            for name in ('libc++.a', 'libc++experimental.a', 'libc++abi.a', 'libunwind.a'):
                (runtime / 'lib' / name).write_text('inert archive placeholder')
            log = root / 'calls.bin'
            shim = '''#!/bin/bash
printf '%s\\0' "${0##*/}" "$@" >> "$ATOMIC_ARGS_LOG"
printf '\\0' >> "$ATOMIC_ARGS_LOG"
if [[ "${0##*/}" == llvm-nm-21 ]]; then
    if [[ "$*" != *--dynamic* ]]; then
        if [[ "$ATOMIC_MODE" == static-provider ]]; then printf '0000 T __atomic_load\\n'; fi
        exit 0
    fi
    for symbol in __atomic_load __atomic_store __atomic_exchange __atomic_compare_exchange __atomic_is_lock_free; do
        if [[ "$symbol" == __atomic_exchange ]]; then
            case "$ATOMIC_MODE" in
                missing) continue ;;
                duplicate) printf '0000 T %s\\n' "$symbol" ;;
                data) printf '0000 D %s\\n' "$symbol"; continue ;;
            esac
        fi
        printf '0000 %s %s\\n' "${ATOMIC_KIND:-T}" "$symbol"
    done
elif [[ "${0##*/}" == clang-21 || "${0##*/}" == clang++-21 ]]; then
    previous=''
    for argument in "$@"; do
        if [[ "$previous" == -o ]]; then printf 'inert output, never native code' > "$argument"; fi
        previous=$argument
    done
fi
'''
            for tool in ('clang-21', 'clang++-21', 'llvm-nm-21', 'llvm-readobj-21', 'cmake'):
                path = tools / tool
                path.write_text(shim, encoding='utf-8', newline='\n')
                path.chmod(0o755)
            selected = ROOT / f'scripts/build/{family}/target-config.sh'
            script_path = ROOT / f'scripts/build/{family}/' / ('install-toolchain.sh' if family == 'qt5-android' else 'build-runtime.sh')
            source = script_path.read_text(encoding='utf-8')
            if fragment == 'configure':
                source = (ROOT / f'scripts/build/{family}/build-runtime.sh').read_text(encoding='utf-8')
                start = source.index('flags=')
                end = source.index('cmake --build "$builtins"')
                end = source.index('\n', end)
                body = source[start:end]
            elif family == 'qt6-android':
                body = source[source.index('platform="$sysroot'):]
            else:
                anchor = 'source "$repo/scripts/build/android-api21/generic-atomics.sh"'
                start = source.index(anchor) if anchor in source else source.index('atomic_objects=()')
                body = source[start:source.index('\n{ declare -p')]
            body = body.replace('/out/', '"$output_fixture/"')
            # Source lookup substitution only; execute the actual recipe branch.
            body = body.replace('/repo/scripts/', shell_path(ROOT / 'scripts') + '/')
            prelude = '\n'.join((
                'set -euo pipefail',
                'awk() { /usr/bin/awk "$@"; }',
                'grep() { /usr/bin/grep "$@"; }',
                'cp() { /usr/bin/cp "$@"; }',
                'repo='+shlex.quote(shell_path(ROOT)),
                'source '+shlex.quote(shell_path(selected)),
                'prefix='+shlex.quote(shell_path(prefix)),
                'runtime='+shlex.quote(shell_path(runtime)),
                'builtins='+shlex.quote(shell_path(root / 'builtins.a')),
                'builtins_archive="$builtins"',
                'llvm='+shlex.quote(shell_path(root / 'llvm')),
                'sysroot='+shlex.quote(shell_path(root / 'sysroot')),
                'output_fixture='+shlex.quote(shell_path(root / 'out')),
                'arch=(--target="$target" --sysroot="$sysroot" "${arch_flags[@]}" -fPIC)',
            ))
            script = root / 'recipe.sh'
            script.write_text(prelude+'\n'+body+'\n', encoding='utf-8', newline='\n')
            env = dict(os.environ, ANDROID_ABI=abi, PATH=shell_path(tools),
                       ATOMIC_ARGS_LOG=shell_path(log), ATOMIC_MODE=mode,
                       ATOMIC_KIND='W' if mode == 'weak' else 'T',
                       MSYS_NO_PATHCONV='1', MSYS2_ARG_CONV_EXCL='*')
            result = subprocess.run([BASH, '--noprofile', '--norc', shell_path(script)],
                                    env=env, capture_output=True, text=True, timeout=8,
                                    creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
            calls = []
            if log.exists():
                for call in log.read_bytes().decode().split('\0\0'):
                    if call: calls.append(call.rstrip('\0').split('\0'))
            return result, calls

    def test_actual_runtime_recipe_compiles_one_provider_for_every_abi(self):
        for family, abis in (('qt6-android', ('armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64')),
                             ('qt5-android', ('armeabi-v7a', 'x86'))):
            for abi in abis:
                with self.subTest(family=family, abi=abi):
                    result, calls = self.run_fragment(family, abi)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    compile_calls = [c for c in calls if c[0] == 'clang-21']
                    self.assertEqual(len(compile_calls), 1, calls)
                    compile = compile_calls[0]
                    self.assertIn('-D_LIBATOMIC_USE_PTHREAD', compile)
                    self.assertIn('-fvisibility=default', compile)
                    self.assertIn('-fPIC', compile)
                    expected_target = {'armeabi-v7a': 'armv7a-linux-androideabi', 'arm64-v8a': 'aarch64-linux-android',
                                       'x86': 'i686-linux-android', 'x86_64': 'x86_64-linux-android'}[abi]
                    expected_target += '10' if family == 'qt5-android' else '21'
                    self.assertIn('--target='+expected_target, compile)
                    if abi == 'armeabi-v7a':
                        self.assertIn('-mfloat-abi=softfp', compile)
                    elif abi == 'x86':
                        self.assertIn('-mssse3', compile)
                    elif abi == 'x86_64':
                        self.assertIn('-march=x86-64-v2', compile)
                    self.assertTrue(any(v.endswith('/compiler-rt/lib/builtins/atomic.c') for v in compile), compile)
                    links = [c for c in calls if c[0] == 'clang++-21']
                    self.assertEqual(len(links), 1)
                    objects = [v for v in links[0] if v.endswith('/atomic-android.o')]
                    self.assertEqual(len(objects), 1, links)
                    self.assertEqual(objects[0], compile[compile.index('-o') + 1])
                    self.assertIn('-shared', links[0])
                    self.assertFalse(any('libatomic.a' in v or v == '-latomic' for v in links[0]))
                    self.assertTrue(any(c[0] == 'llvm-nm-21' and '--dynamic' in c for c in calls))
                    self.assertTrue(any(c[0] == 'llvm-nm-21' and '--dynamic' not in c for c in calls))

    def test_actual_compiler_rt_configuration_excludes_secondary_providers(self):
        for family, abi in (('qt6-android', 'arm64-v8a'), ('qt5-android', 'armeabi-v7a')):
            with self.subTest(family=family):
                result, calls = self.run_fragment(family, abi, fragment='configure')
                self.assertEqual(result.returncode, 0, result.stderr)
                configure = [c for c in calls if '-DLLVM_ENABLE_RUNTIMES=compiler-rt' in c]
                self.assertEqual(len(configure), 1)
                self.assertIn('-DCOMPILER_RT_EXCLUDE_ATOMIC_BUILTIN=ON', configure[0])
                self.assertIn('-DCOMPILER_RT_BUILD_STANDALONE_LIBATOMIC=OFF', configure[0])

    def test_export_and_static_provider_metadata_failures_are_not_accepted(self):
        for family in ('qt6-android', 'qt5-android'):
            for mode in ('missing', 'duplicate', 'data', 'static-provider'):
                with self.subTest(family=family, mode=mode):
                    result, calls = self.run_fragment(family, 'x86', mode)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertTrue('generic atomic' in result.stderr.lower() or 'static builtins' in result.stderr.lower(), result.stderr)
                    if mode == 'static-provider':
                        self.assertFalse(any(c[0] == 'clang++-21' for c in calls), 'Conflicting builtins reached the shared link')

    def test_weak_function_exports_are_accepted(self):
        result, _ = self.run_fragment('qt6-android', 'x86_64', 'weak')
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
