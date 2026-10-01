# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon

import os
root = '/work/sysroot'
count = 0
for parent, dirs, files in os.walk(root):
    for name in dirs + files:
        path = os.path.join(parent, name)
        if os.path.islink(path):
            target = os.readlink(path)
            if target.startswith('/'):
                relative = os.path.relpath(os.path.join(root, target.lstrip('/')), parent)
                os.unlink(path)
                os.symlink(relative, path)
                count += 1
print('Relativized sysroot links:', count)
