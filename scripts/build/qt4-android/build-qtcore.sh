#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

profile=${1:-core}
case "$profile" in
    core)
        tree=/work/qt4-donut
        prefix=/work/qtcore-donut-sdk
        features=(-no-gui -no-opengl -no-script -no-declarative)
        modules=(sub-corelib)
        ;;
    quick)
        tree=/work/qt4-donut-quick
        prefix=/work/qtquick-donut-sdk
        features=(-qpa minimal -no-opengl -script -declarative -no-javascript-jit
                  -qt-freetype -no-fontconfig -no-gtkstyle -no-accessibility)
        modules=(sub-sql sub-declarative)
        ;;
    *) echo "Unknown Qt build profile $profile" >&2; exit 2 ;;
esac
source_archive=/inputs/qt-everywhere-opensource-src-4.8.7.tar.gz
target=armv5te-linux-androideabi4
sdk=/work/sysroot-api4
runtime=/work/runtime-build

if [[ ! -f "$tree/configure" ]]; then
    mkdir -p "$tree"
    tar -xzf "$source_archive" -C "$tree" --strip-components=1
fi
cd "$tree"

mkdir -p /work/donut-bin mkspecs/linux-donut-llvm mkspecs/linux-donut-host
host_platformdefs=mkspecs/linux-donut-host/qplatformdefs.h
target_platformdefs=mkspecs/linux-donut-llvm/qplatformdefs.h
cmp -s mkspecs/linux-g++/qplatformdefs.h "$host_platformdefs" ||
    cp mkspecs/linux-g++/qplatformdefs.h "$host_platformdefs"
sed -e '/^#include <sys\/shm.h>/d' \
    -e 's/^#define QT_SOCKLEN_T *int$/#define QT_SOCKLEN_T socklen_t/' \
    mkspecs/linux-g++/qplatformdefs.h > /work/donut-bin/qplatformdefs.h
cmp -s /work/donut-bin/qplatformdefs.h "$target_platformdefs" ||
    cp /work/donut-bin/qplatformdefs.h "$target_platformdefs"
python3 /repo/scripts/build/qt4-android/patch-qtcore.py "$profile"
if [[ "$profile" == quick && ! -f .donut-script-frames ]]; then
    patch -p1 --fuzz=0 < /repo/patches/qt4/all/04-script-tagged-frame-pointers.patch
    touch .donut-script-frames
fi

cat >/work/donut-bin/donut-cxx <<EOF
#!/bin/bash
exec clang++-21 --target=$target --sysroot=$sdk -march=armv5te -mfloat-abi=soft -fPIC -femulated-tls \\
    -D__STDC_LIMIT_MACROS -D__STDC_CONSTANT_MACROS -DSIZE_MAX=__SIZE_MAX__ -D_LIBCPP_PROVIDES_DEFAULT_RUNE_TABLE \\
    -DQT_NO_SHAREDMEMORY -DQT_NO_SYSTEMSEMAPHORE \\
    -nostdinc++ -isystem $runtime/include/c++/v1 "\$@"
EOF
cat >/work/donut-bin/donut-cc <<EOF
#!/bin/bash
exec clang-21 --target=$target --sysroot=$sdk -march=armv5te -mfloat-abi=soft -fPIC "\$@"
EOF
cat >/work/donut-bin/donut-config-link <<EOF
#!/bin/bash
# Configure cross-tests inspect successful links, and builds here are static.
exec /work/donut-bin/donut-cxx --ld-path=/usr/bin/ld.lld-21 -shared -nostdlib \\
    -Wl,--hash-style=sysv "\$@" -L$sdk/usr/lib -ldl -lm -lc
EOF
chmod +x /work/donut-bin/donut-*

cat >mkspecs/linux-donut-host/qmake.conf <<'EOF'
include(../linux-g++/qmake.conf)
QMAKE_CXXFLAGS += -std=gnu++98
EOF
if [[ "$profile" == quick ]]; then
    cat >>mkspecs/linux-donut-host/qmake.conf <<'EOF'
QMAKE_CC = clang-21
QMAKE_CXX = clang++-21
QMAKE_LINK = clang++-21
QMAKE_LINK_SHLIB = clang++-21
EOF
fi
cat >mkspecs/linux-donut-llvm/qmake.conf <<'EOF'
include(../linux-g++/qmake.conf)
QMAKE_CC = /work/donut-bin/donut-cc -fgnu89-inline
QMAKE_CXX = /work/donut-bin/donut-cxx -std=gnu++98
QMAKE_LINK = /work/donut-bin/donut-config-link
QMAKE_LINK_SHLIB = /work/donut-bin/donut-config-link
QMAKE_AR = llvm-ar-21 cqs
QMAKE_RANLIB = llvm-ranlib-21
QMAKE_LIBS_THREAD =
QMAKE_CFLAGS_THREAD =
QMAKE_CXXFLAGS_THREAD =
DEFINES += QT_NO_LINUX_FUTEX
EOF

if [[ ! -f .donut-configured ]]; then
    ./configure -prefix "$prefix" -opensource -confirm-license -release -static -no-rpath \
        -platform linux-donut-host -xplatform linux-donut-llvm -arch arm -host-arch x86_64 \
        "${features[@]}" -no-qt3support -no-phonon -no-phonon-backend \
        -no-webkit -no-scripttools -no-xmlpatterns \
        -no-multimedia -no-svg -no-dbus -no-glib -no-icu -no-iconv \
        -no-openssl -no-nis -no-cups -no-pch -no-largefile \
        -no-stl -exceptions -qt-zlib \
        -nomake demos -nomake examples -nomake docs -nomake translations -nomake tests
    touch .donut-configured
fi

if [[ "$profile" == quick && ! -f .donut-host-clang ]]; then
    for tool in bootstrap moc rcc uic; do
        if [[ -f src/tools/$tool/Makefile ]]; then
            make -C "src/tools/$tool" clean
        fi
    done
    make -C src -j2 sub-moc sub-rcc sub-uic
    if [[ -d src/gui/.uic ]]; then
        find src/gui/.uic -name 'ui_*.h' -delete
    fi
    touch .donut-host-clang
fi

make -C src -k -j2 "${modules[@]}"
if [[ "$profile" == core ]]; then
    test -s lib/libQtCore.a
    test -s bin/qmake
else
    for module in QtGui QtScript QtDeclarative QtSql; do
        test -s "lib/lib$module.a"
    done
    make -C src/plugins/platforms/minimal -j2
fi
bin/qmake -v
