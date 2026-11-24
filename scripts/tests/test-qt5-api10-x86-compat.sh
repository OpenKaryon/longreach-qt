#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Run inside an existing LLVM21 Linux image. Executes freestanding Linux i386
# probes, never an Android emulator. Retains evidence in a fresh output folder.
set -euo pipefail
repo=${REPO_ROOT:-/repo}
out=${1:?Pass a fresh absolute output directory}
sysroot=${2:-/opt/longreach-android/sysroot}
[[ "$out" == /* && ! -e "$out" ]] || { echo 'Use a fresh absolute output directory' >&2; exit 1; }
mkdir -p "$out"
clang-21 --version > "$out/compiler.txt"
ld.lld-21 --version > "$out/linker.txt"
uname -a > "$out/host-kernel.txt"
common=(--target=i686-linux-android10 --sysroot="$sysroot" -mssse3 -fPIC
        -ffunction-sections -fdata-sections -fno-stack-protector -fno-builtin)
for optimization in 0 2; do
    for profile in aligned-frame aligned-omit unaligned-omit; do
        directory="$out/O$optimization-$profile"
        mkdir "$directory"
        case "$profile" in
            aligned-frame) frame=(-mstackrealign -fno-omit-frame-pointer) ;;
            aligned-omit) frame=(-mstackrealign -fomit-frame-pointer) ;;
            unaligned-omit) frame=(-mno-stackrealign -fomit-frame-pointer) ;;
        esac
        flags=("${common[@]}" "-O$optimization" "${frame[@]}")
        clang-21 "${flags[@]}" -c "$repo/scripts/build/qt5-android/compat.c" -o "$directory/compat.o"
        clang-21 "${flags[@]}" -c "$repo/scripts/tests/qt5-api10-x86-wait4.c" -o "$directory/probe.o"
        llvm-nm-21 --undefined-only "$directory/compat.o" > "$directory/imports.txt"
        if grep -Eq ' (__wait4|syscall)$' "$directory/imports.txt"; then
            echo 'x86 wait4 still depends on a private or broken Bionic adapter' >&2
            exit 1
        fi
        ld.lld-21 -m elf_i386 --gc-sections -e _start "$directory/compat.o" "$directory/probe.o" -o "$directory/probe"
        "$directory/probe"
        echo "PASS: O$optimization $profile wait4 PID/status/rusage/WNOHANG/errno"
    done
done
cat > "$out/pagesize.c" <<'EOF'
#include <unistd.h>
int page_size_from_sdk_header(void) { return getpagesize(); }
EOF
clang-21 "${common[@]}" -O2 -c "$out/pagesize.c" -o "$out/pagesize.o"
llvm-nm-21 --undefined-only "$out/pagesize.o" > "$out/pagesize-imports.txt"
grep -Eq ' sysconf$' "$out/pagesize-imports.txt"
if grep -Eq ' __page_size$' "$out/pagesize-imports.txt"; then
    echo 'getpagesize still imports private Bionic data' >&2
    exit 1
fi
python3 - "$out" "$repo" "$sysroot" <<'PY'
import hashlib
import json
from pathlib import Path
import sys
out, repo, sysroot = map(Path, sys.argv[1:])
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
report = {'schema_version': 1, 'scope': 'host-linux-i386-syscall-contract',
          'android_guest_qualified': False, 'profiles_passed': 6,
          'compiler': (out / 'compiler.txt').read_text(),
          'host_kernel': (out / 'host-kernel.txt').read_text(),
          'compat_source_sha256': digest(repo / 'scripts/build/qt5-android/compat.c'),
          'probe_source_sha256': digest(repo / 'scripts/tests/qt5-api10-x86-wait4.c'),
          'unistd_header_sha256': digest(sysroot / 'usr/include/unistd.h'),
          'files': {path.relative_to(out).as_posix(): digest(path) for path in sorted(out.rglob('*')) if path.is_file()}}
(out / 'result.json').write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
PY
echo 'PASS: API10 x86 compatibility probe; Android guest qualification remains separate'
