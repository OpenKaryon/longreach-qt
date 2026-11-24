# SPDX-License-Identifier: GPL-3.0-or-later
"""Atomic text protocol and actual build/driver source with inert tools only."""
import importlib.util
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('atomic_output', ROOT / 'scripts/tests/require-android-atomic.py')
output = importlib.util.module_from_spec(spec)
spec.loader.exec_module(output)
BASH = (next((str(p) for p in (Path('C:/Program Files/Git/bin/bash.exe'),
                              Path('C:/Program Files/Git/usr/bin/bash.exe')) if p.is_file()), None)
        if os.name == 'nt' else shutil.which('bash'))


def shell_path(path):
    value = Path(path).resolve().as_posix()
    return '/' + value[0].lower() + value[2:] if os.name == 'nt' else value


class AtomicOutput(unittest.TestCase):
    def current(self):
        return ['ATOMIC_PROVIDER: libc++_shared.so', 'ATOMIC_WORKERS: 2', 'ATOMIC_EXIT:0',
                'PASS: generic 24-byte cross-DSO atomic store/load/exchange/CAS/thread handoff']

    def test_current_protocol_and_old_16_byte_output(self):
        output.validate('\n'.join(self.current()))
        with self.assertRaises(ValueError):
            output.validate('PASS: generic 16-byte atomic store/load/exchange/CAS/thread handoff\nATOMIC_EXIT:0\n')

    def test_missing_duplicate_conflicting_and_failed_results(self):
        for index in range(4):
            for fault in ('missing', 'duplicate', 'conflicting'):
                with self.subTest(index=index, fault=fault):
                    lines = self.current()
                    if fault == 'missing': lines.pop(index)
                    elif fault == 'duplicate': lines.append(lines[index])
                    else: lines.append(lines[index].split(':')[0] + ': incorrect')
                    with self.assertRaises(ValueError): output.validate('\n'.join(lines))
        with self.assertRaisesRegex(ValueError, 'reported a failure'):
            output.validate('\n'.join(self.current() + ['FAIL: provider mismatch']))

    def test_cli_rejects_nonzero_exit_and_accepts_complete_current_protocol(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'atomic.stdout'
            for valid in (True, False):
                text = '\n'.join(self.current())
                path.write_text(text if valid else text.replace('ATOMIC_EXIT:0', 'ATOMIC_EXIT:7'))
                result = subprocess.run([sys.executable, str(ROOT / 'scripts/tests/require-android-atomic.py'), str(path)],
                    capture_output=True, text=True, timeout=5, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
                self.assertEqual(result.returncode, 0 if valid else 1, result.stderr)


@unittest.skipUnless(BASH, 'Bash needed for ordinary build/driver recording')
class AtomicBuild(unittest.TestCase):
    def invoke(self, abi, fault='', target='liblongreach-atomic-a.so'):
        with tempfile.TemporaryDirectory(prefix='atomic probe argv-') as temporary:
            root = Path(temporary)
            tools, prefix, destination = root / 'tools', root / 'runtime with spaces', root / 'probe output'
            for directory in (tools, prefix / 'bin', prefix / 'lib', destination): directory.mkdir(parents=True, exist_ok=True)
            (prefix / 'lib/libc++_shared.so').write_text('inert runtime bytes')
            (prefix / 'target.sh').write_text((ROOT / 'scripts/build/qt6-android/target-config.sh').read_text(), newline='\n')
            wrapper = (ROOT / 'scripts/build/qt6-android/clang-wrapper.sh').read_text()
            wrapper = wrapper.replace('prefix=/opt/longreach-android-api21', 'prefix='+shlex.quote(shell_path(prefix)), 1)
            (prefix / 'bin/cxx').write_text(wrapper, encoding='utf-8', newline='\n')
            (prefix / 'bin/cxx').chmod(0o755)
            shim = '''#!/bin/bash
printf '%s\\0' "${0##*/}" "$@" >> "$PROBE_CALLS"
printf '\\0' >> "$PROBE_CALLS"
if [[ "${0##*/}" == clang++-21 ]]; then
    previous=''
    for argument in "$@"; do
        if [[ "$previous" == -o ]]; then printf 'inert bytes, never executable code' > "$argument"; fi
        previous=$argument
    done
elif [[ "${0##*/}" == llvm-nm-21 ]]; then
    name="${@: -1}"; name="${name##*/}"
    mode=''; if [[ "$name" == "$PROBE_FAULT_TARGET" ]]; then mode="$PROBE_FAULT"; fi
    if [[ "$mode" == tool-failed ]]; then echo 'recorded nm failure' >&2; exit 7; fi
    for symbol in __atomic_load __atomic_store __atomic_exchange __atomic_compare_exchange __atomic_is_lock_free; do
        if [[ "$symbol" == __atomic_exchange ]]; then
            if [[ "$mode" == missing-import ]]; then continue; fi
            if [[ "$mode" == embedded-provider ]]; then printf '0000 T %s\\n' "$symbol"; continue; fi
        fi
        printf '         U %s\\n' "$symbol"
    done
    case "$name" in
        liblongreach-atomic-a.so) side=a ;;
        liblongreach-atomic-b.so) side=b ;;
        *) exit 0 ;;
    esac
    printf '0000 T longreach_atomic_worker_%s\\n' "$side"
    if [[ "$mode" != missing-worker ]]; then printf '0000 T longreach_atomic_provider_%s\\n' "$side"; fi
fi
'''
            for tool in ('clang++-21', 'llvm-nm-21', 'llvm-readobj-21'):
                path = tools / tool
                path.write_text(shim, encoding='utf-8', newline='\n')
                path.chmod(0o755)
            source = (ROOT / 'scripts/build/qt6-android/build-probe.sh').read_text()
            source = source.replace('repo=/repo', 'repo='+shlex.quote(shell_path(ROOT)), 1)
            source = source.replace('prefix=/opt/longreach-android-api21', 'prefix='+shlex.quote(shell_path(prefix)), 1)
            source = ('awk() { /usr/bin/awk "$@"; }\ncp() { /usr/bin/cp "$@"; }\n'
                      'mkdir() { /usr/bin/mkdir "$@"; }\n') + source
            script, log = root / 'build.sh', root / 'calls.bin'
            script.write_text(source, encoding='utf-8', newline='\n')
            environment = dict(os.environ, ANDROID_ABI=abi, PROBE_OUTPUT_DIR=shell_path(destination),
                               PATH=shell_path(tools), PROBE_CALLS=shell_path(log), PROBE_FAULT=fault,
                               PROBE_FAULT_TARGET=target, MSYS_NO_PATHCONV='1', MSYS2_ARG_CONV_EXCL='*')
            result = subprocess.run([BASH, '--noprofile', '--norc', shell_path(script)], env=environment,
                                    capture_output=True, text=True, timeout=8,
                                    creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
            calls = [call.rstrip('\0').split('\0') for call in log.read_bytes().decode().split('\0\0') if call] if log.exists() else []
            return result, calls, {p.name for p in destination.iterdir()}

    def test_full_actual_build_and_driver_deliver_two_dsos_for_all_abis(self):
        for abi in ('armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64'):
            with self.subTest(abi=abi):
                result, calls, files = self.invoke(abi)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue({'cxx23-probe', 'libc++_shared.so', 'atomic-probe', 'liblongreach-atomic-a.so', 'liblongreach-atomic-b.so'} <= files)
                links = [call for call in calls if call[0] == 'clang++-21']
                self.assertEqual(len(links), 4, links)
                shared = [call for call in links if '-shared' in call]
                self.assertEqual(len(shared), 2, links)
                for side, call in zip(('a', 'b'), shared):
                    self.assertIn('-DLONGREACH_ATOMIC_WORKER=longreach_atomic_worker_'+side, call)
                    self.assertIn('-DLONGREACH_ATOMIC_PROVIDER=longreach_atomic_provider_'+side, call)
                    self.assertIn('-Wl,-soname,liblongreach-atomic-'+side+'.so', call)
                    self.assertIn('-fvisibility=hidden', call)
                    self.assertTrue(any(v.endswith('/crtbegin_so.o') for v in call))
                executable = next(call for call in links if any(v.endswith('/android-atomic.cpp') for v in call))
                self.assertIn('-llongreach-atomic-a', executable)
                self.assertIn('-llongreach-atomic-b', executable)
                self.assertIn('-pie', executable)
                self.assertTrue(any(v.endswith('/crtbegin_dynamic.o') for v in executable))
                for call in links:
                    self.assertIn('-lc++_shared', call)
                    self.assertFalse(any(v.endswith('/atomic.c') or v.endswith('/atomic-android.o') or v.endswith('/libatomic.a') for v in call))
                self.assertEqual(len([c for c in calls if c[0] == 'llvm-nm-21']), 3)

    def test_consumer_metadata_fault_stops_the_build_before_later_outputs(self):
        for target in ('liblongreach-atomic-a.so', 'liblongreach-atomic-b.so', 'atomic-probe'):
            for fault in ('embedded-provider', 'missing-import', 'tool-failed'):
                with self.subTest(target=target, fault=fault):
                    result, calls, files = self.invoke('x86_64', fault, target)
                    self.assertNotEqual(result.returncode, 0)
                    if target != 'atomic-probe': self.assertNotIn('atomic-probe', files)
        for target in ('liblongreach-atomic-a.so', 'liblongreach-atomic-b.so'):
            with self.subTest(target=target, fault='missing-worker'):
                result, _, files = self.invoke('armeabi-v7a', 'missing-worker', target)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('worker function export', result.stderr)
                self.assertNotIn('atomic-probe', files)


if __name__ == '__main__':
    unittest.main()
