#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail
jobs=${TIGER_JOBS:-6}
arch=${TIGER_ARCH:-i386}
spec=${TIGER_SPEC:-macx-tiger-clang}
sdk=/opt/qt4-tiger
mkdir -p /work/suite /work/apps /out/bin
cp -R /input/. /work/suite/
for target in $(grep -v '^#' /work/suite/expected-apps.txt | grep .); do
    mkdir -p "/work/apps/$target"
    cd "/work/apps/$target"
    "$sdk/bin/qmake" -spec "$sdk/mkspecs/$spec" \
        "/work/suite/$target/$target.pro" 'CONFIG+=app_bundle' 'CONFIG-=console' \
        'DEFINES+=SMOKE_STATIC_QSQLITE' \
        "LIBS+=-L$sdk/plugins/sqldrivers -lqsqlite"
    make -j "$jobs"
    # qmake's Mac generator is compiled on Linux, so create the bundle ourselves
    # if it emitted a flat executable. GUI apps need a bundle for Finder launch.
    bundle="$target.app"
    if [ ! -d "$bundle" ]; then
        mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
        cp "$target" "$bundle/Contents/MacOS/$target"
    fi
    # Linux-host qmake can create the bundle directory without its metadata.
    mkdir -p "$bundle/Contents/Resources"
    TARGET_NAME="$target" BUNDLE="$bundle" python3 /scripts/write-bundle.py
    cp -R "$bundle" /out/bin/
done
python3 /scripts/audit-macho.py /out/bin /out/macho-audit.json --arch "$arch"
tar -C /out/bin -czf "/out/qt4-tiger-$arch-examples.tar.gz" .
cp /opt/qt4-licenses/* /out/
printf 'Qt 4.8.7 / Mac OS X 10.4 Tiger / %s / Carbon.\nExtract qt4-tiger-%s-examples.tar.gz on the Mac to preserve executable permissions.\nMach-O compile/link audit passed; actual Tiger runtime testing is pending.\n' "$arch" "$arch" > /out/README.txt
