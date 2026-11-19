#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Regression: an Android PIE feature probe must not be linked as a DSO.
set -euo pipefail
check_dir=$(mktemp -d)
trap 'rm -rf -- "$check_dir"' EXIT
cat > "$check_dir/thread.c" <<'EOF'
#include <pthread.h>
void *start_routine(void *data) { return data; }
int main(void)
{
    pthread_t thread;
    if (pthread_create(&thread, 0, start_routine, 0))
        return 1;
    return pthread_join(thread, 0);
}
EOF
cc=/opt/longreach-android-api21/bin/cc
"$cc" -fPIE -c "$check_dir/thread.c" -o "$check_dir/pie.o"
"$cc" "$check_dir/pie.o" -pthread -o "$check_dir/thread-pie"
"$cc" -fPIC -c "$check_dir/thread.c" -o "$check_dir/shared.o"
"$cc" -shared "$check_dir/shared.o" -pthread -o "$check_dir/thread-shared.so"
python3 - "$check_dir" <<'PY'
from pathlib import Path
import struct
import sys
root = Path(sys.argv[1])
for name, executable in (('thread-pie', True), ('thread-shared.so', False)):
    data = (root / name).read_bytes()
    if data[:4] != b'\x7fELF' or struct.unpack_from('<H', data, 16)[0] != 3:
        raise RuntimeError(f'Expected position-independent ELF: {name}')
    entry = struct.unpack_from('<I' if data[4] == 1 else '<Q', data, 24)[0]
    if bool(entry) != executable:
        raise RuntimeError(f'Wrong entry point/link kind: {name}')
print('PASS: Android PIE pthread probe and shared-library link kinds')
PY
