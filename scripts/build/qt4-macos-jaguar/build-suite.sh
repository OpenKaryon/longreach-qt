#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
# Milestone 4 of the Jaguar port: build the shared Qt 4 applications
# (tests/expected-apps.txt) against the Jaguar SDK in
# /opt/qt4-jaguar, bundle them, and check each executable's imports against
# the 10.2.8 SDK. The build continues past a failing application so that one
# run lists all of them; the exit status is the number of failures.
set -uo pipefail
jobs=${JAGUAR_JOBS:-6}
spec=macx-jaguar-g++
sdk=/opt/qt4-jaguar
mkdir -p /work/suite /work/apps /out/bin /out/imports
cp -R /input/. /work/suite/
failures=0
for target in $(grep -v '^#' /work/suite/expected-apps.txt | grep .); do
    mkdir -p "/work/apps/$target"
    cd "/work/apps/$target"
    if ! { "$sdk/bin/qmake" -spec "$sdk/mkspecs/$spec" \
               "/work/suite/$target/$target.pro" 'CONFIG+=app_bundle' 'CONFIG-=console' \
               'DEFINES+=SMOKE_STATIC_QSQLITE' "LIBS+=-L$sdk/plugins/sqldrivers -lqsqlite" \
           && make -j "$jobs"; } > "/out/build-$target.log" 2>&1; then
        echo "BUILD FAILED: $target"
        failures=$((failures + 1))
        continue
    fi
    executable=$target
    [ -f "$target.app/Contents/MacOS/$target" ] && executable="$target.app/Contents/MacOS/$target"
    if ! python3 /scripts/check-imports.py "$executable" "/out/imports/$target.txt" > "/out/imports/$target.summary" 2>&1; then
        echo "IMPORTS FAILED: $target: $(head -1 "/out/imports/$target.summary")"
        failures=$((failures + 1))
    fi
    # qmake's Mac generator runs on Linux, so write the bundle ourselves.
    bundle="$target.app"
    if [ ! -d "$bundle" ]; then
        mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
        cp "$target" "$bundle/Contents/MacOS/$target"
    fi
    mkdir -p "$bundle/Contents/Resources"
    TARGET_NAME="$target" BUNDLE="$bundle" python3 /scripts/write-bundle.py
    cp -R "$bundle" /out/bin/
done

# A weak import is NULL on 10.2 and must be checked before use. QtCore checks
# its own (patches 02 and 03), QtGui calls them only through the Jaguar
# shim, and QtOpenGL's pixel buffer code checks aglCreatePBuffer. No other
# Qt object may reference one.
awk '$1 == "weak" {print $2}' /out/imports/*.txt | sort -u > /out/weak-imports.txt
nm=/opt/osxcross-ppc/target/bin/powerpc-apple-darwin8-nm
[ -d /work/qt-source ] && find /work/qt-source/src /work/qt-source/tools -name '*.o' -path '*release-static*' \
    | grep -v -e '/src/corelib/' -e '/src/gui/.obj/release-static/qt_jaguar_mac.o' \
              -e '/src/opengl/.obj/release-static/qglpixelbuffer_mac.o' | sort | while read -r object; do
    $nm -u "$object" 2>/dev/null | sort -u | comm -12 - /out/weak-imports.txt \
        | grep -v '^_HICopyAccessibilityRoleDescription$' | sed "s|^|${object#/work/qt-source/}: |"
done > /out/direct-weak-references.txt
if [ -s /out/direct-weak-references.txt ]; then
    echo 'Qt objects reference weak imports without a check:'
    cat /out/direct-weak-references.txt
    failures=$((failures + 1))
fi
tar -C /out/bin -czf /out/qt4-jaguar-ppc-examples.tar.gz .
echo "failures=$failures"
exit $failures
