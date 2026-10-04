#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
# Milestones 2 and 3 of the Jaguar port: configure Qt 4.8.7 for Mac OS X 10.2
# / PowerPC, build and install QtCore and QtGui, and build the two probes with
# the installed qmake, as an application of the SDK would. Each probe must
# pass check-imports.py: every strong import exists in the 10.2.8 SDK.
set -uo pipefail
jobs=${JAGUAR_JOBS:-6}
spec=macx-jaguar-g++
source=/work/qt-source
bin=/opt/osxcross-ppc/target/bin
mkdir -p "$source"
tar -xzf /archives/qt-everywhere-opensource-src-4.8.7.tar.gz --strip-components=1 -C "$source"
cd "$source"
for p in /patches/all/*.patch /patches/macos/*.patch; do patch -p1 < "$p" || exit 1; done
mkdir -p "mkspecs/$spec"
cp mkspecs/macx-g++/qplatformdefs.h "mkspecs/$spec/"
cp /scripts/qmake.conf "mkspecs/$spec/"
# The module set of the Tiger build (scripts/build/qt4-macos/build-qt.sh),
# with OpenSSL from build-openssl.sh. Jaguar has no libiconv (10.3).
OPENSSL_LIBS='-L/opt/openssl-jaguar/lib -lssl -lcrypto' \
./configure -v -prefix /opt/qt4-jaguar -opensource -confirm-license -release -static \
    -platform linux-g++ -xplatform "$spec" -arch ppc -host-arch x86_64 \
    -carbon -no-framework -no-dwarf2 -no-pch -no-separate-debug-info \
    -openssl-linked -I/opt/openssl-jaguar/include -L/opt/openssl-jaguar/lib \
    -nomake demos -nomake examples -nomake docs -nomake translations -nomake tests \
    -no-webkit -no-phonon -no-phonon-backend -no-dbus -no-cups -no-nis -no-icu \
    -no-glib -no-gtkstyle -no-openvg -no-sql-mysql -no-sql-psql -no-sql-odbc -no-iconv \
    -plugin-sql-sqlite -qt-zlib -qt-libpng -qt-libjpeg -qt-libtiff -qt-libmng \
    -opengl desktop -qt3support -xmlpatterns -script -scripttools -svg -declarative \
    -multimedia -audio-backend -accessibility -stl -exceptions -largefile \
    > /out/configure.log 2>&1 || { tail -40 /out/configure.log; exit 1; }
grep -q 'QT_ARCH = powerpc' mkspecs/qconfig.pri || { echo 'configure did not select powerpc'; exit 1; }
grep -q openssl-linked mkspecs/qconfig.pri || { echo 'configure did not link OpenSSL'; exit 1; }

make -j "$jobs" > /out/qt-build.log 2>&1 || { grep -E 'error:|Error [0-9]' /out/qt-build.log | head -40; exit 1; }
make install > /out/qt-install.log 2>&1 || exit 1
(cd tools/designer/src/uitools && /opt/qt4-jaguar/bin/qmake -spec "/opt/qt4-jaguar/mkspecs/$spec" uitools.pro \
    && make -j "$jobs" && make install) > /out/qt-uitools.log 2>&1 || { tail -20 /out/qt-uitools.log; exit 1; }

status=0
for probe in qtcore-probe qtgui-probe; do
    cp -r "/scripts/$probe" "/work/$probe"
    cd "/work/$probe"
    { /opt/qt4-jaguar/bin/qmake -spec "$spec" "$probe.pro" && make; } > "/out/$probe-build.log" 2>&1 \
        || { tail -30 "/out/$probe-build.log"; exit 1; }
    cp "$probe" /out/
    { file "$probe"; $bin/powerpc-apple-darwin8-otool -L "$probe";
      $bin/powerpc-apple-darwin8-otool -l "$probe" | awk '$1 == "cmd" {print $2}' | sort | uniq -c; } > "/out/$probe-macho.txt"
    $bin/powerpc-apple-darwin8-nm -m "$probe" | grep '(undefined)' > "/out/$probe-imports.txt"
    python3 /scripts/check-imports.py "$probe" "/out/$probe-jaguar-imports.txt" || status=1
done

# A weak import is NULL on 10.2. In QtGui only the Jaguar shim
# (qt_jaguar_mac.cpp) may reference one; it checks before each call. The
# accessibility code checks HICopyAccessibilityRoleDescription itself.
awk '$1 == "weak" {print $2}' /out/qtgui-probe-jaguar-imports.txt | sort -u > /work/weak-imports.txt
cd "$source/src/gui/.obj/release-static"
for object in *.o; do
    [ "$object" = qt_jaguar_mac.o ] && continue
    $bin/powerpc-apple-darwin8-nm -u "$object" 2>/dev/null | sort -u | comm -12 - /work/weak-imports.txt \
        | grep -v '^_HICopyAccessibilityRoleDescription$' | sed "s|^|$object: |"
done > /out/qtgui-direct-weak-references.txt
if [ -s /out/qtgui-direct-weak-references.txt ]; then
    echo 'QtGui references weak imports outside the Jaguar shim:'
    cat /out/qtgui-direct-weak-references.txt
    status=1
fi
exit $status
