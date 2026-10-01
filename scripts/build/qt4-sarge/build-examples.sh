#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail
source "$(dirname "$0")/arch.sh"
jobs=${SARGE_JOBS:-6}
sdk=/work/sdk
python /scripts/fix-linker-script.py
mkdir -p /work/suite /work/apps /out/bin
cp -R /input/. /work/suite/
for target in $(grep -v '^#' /work/suite/expected-apps.txt | grep .); do
    mkdir -p "/work/apps/$target"
    cd "/work/apps/$target"
    "$sdk/bin/qmake" -spec "$sdk/mkspecs/$SARGE_SPEC" \
        "/work/suite/$target/$target.pro"
    make -j "$jobs"
    bash /audit-scripts/qt4-check-deps.sh "$target"
    cp "$target" /out/bin/
done
python /scripts/audit-elf.py
if [ -n "${SARGE_LICENSE_DIR:-}" ]; then
    cp "$SARGE_LICENSE_DIR"/* /out/
else
    cp /archives/openssl-1.0.2u.tar.gz /out/
    cp /work/openssl-source/LICENSE /out/OPENSSL-LICENSE.txt
    cp /work/qt-source/LICENSE.LGPLv21 /work/qt-source/LGPL_EXCEPTION.txt /out/
    cp /work/qt-source/LICENSE.LGPLv3 /out/
    cp /work/gcc-source/COPYING3 /out/GCC-COPYING3.txt
    cp /work/gcc-source/COPYING.RUNTIME /out/GCC-RUNTIME-EXCEPTION.txt
fi
