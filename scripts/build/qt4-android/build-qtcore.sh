#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

source /repo/scripts/build/qt4-android/target-config.sh
profile=${1:-core}
module_features=(-no-multimedia -no-scripttools -no-xmlpatterns)
qt3_feature=-no-qt3support
case "$profile" in
    core)
        tree=$core_tree
        prefix=$core_prefix
        features=(-no-gui -no-opengl -no-script -no-declarative -no-svg)
        modules=(sub-corelib)
        ;;
    quick)
        tree=$quick_tree
        prefix=$quick_prefix
        features=(-qpa minimal -no-opengl -script -declarative -no-javascript-jit -svg -qt-sql-sqlite
                  -qt-freetype -no-fontconfig -no-gtkstyle -no-accessibility)
        modules=(sub-sql sub-xml sub-svg sub-declarative)
        if [[ "$api" != 4 ]]; then
            features=(-qpa minimal -opengl es2 -script -declarative -no-javascript-jit -svg -qt-sql-sqlite
                      -qt-freetype -no-fontconfig -no-gtkstyle -no-accessibility)
            module_features=(-multimedia -scripttools -xmlpatterns)
            qt3_feature=-qt3support
            modules+=(sub-testlib sub-multimedia sub-opengl sub-scripttools sub-xmlpatterns sub-qt3support)
        fi
        ;;
    *) echo "Unknown Qt build profile $profile" >&2; exit 2 ;;
esac
source_archive=/inputs/qt-everywhere-opensource-src-4.8.7.tar.gz

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
if [[ "$profile" == quick && ! -f .donut-static-gui-animation ]]; then
    patch -p1 --fuzz=0 < /repo/patches/qt4/all/03-static-gui-animation-registration.patch
    touch .donut-static-gui-animation
fi
if [[ "$profile" == quick && ! -f .donut-script-frames ]]; then
    patch -p1 --fuzz=0 < /repo/patches/qt4/all/04-script-tagged-frame-pointers.patch
    touch .donut-script-frames
fi

if [[ "$api" != 4 && "$profile" == quick ]]; then
    for compatibility_patch in /repo/patches/qt4/android/*.patch \
            /repo/patches/qt4/linux-sarge-llvm/01-xmlpatterns-color-mask.patch; do
        if ! patch -p1 --reverse --dry-run --fuzz=0 < "$compatibility_patch" >/dev/null 2>&1; then
            patch -p1 --forward --fuzz=0 < "$compatibility_patch"
        fi
    done
fi

if [[ "$api" != 4 ]]; then
    cat >/work/donut-bin/donut-cxx <<'EOF'
#!/bin/bash
exec @RUNTIME@/bin/cxx -DQT_NO_SHAREDMEMORY -DQT_NO_SYSTEMSEMAPHORE "$@"
EOF
    cat >/work/donut-bin/donut-cc <<'EOF'
#!/bin/bash
exec @RUNTIME@/bin/cc "$@"
EOF
    cat >/work/donut-bin/donut-config-link <<'EOF'
#!/bin/bash
exec /work/donut-bin/donut-cxx -shared "$@"
EOF
else
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
fi
if [[ "$api" != 4 ]]; then
    sed -i "s|@RUNTIME@|$runtime|g" /work/donut-bin/donut-cxx /work/donut-bin/donut-cc
fi
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

configure_args=(-prefix "$prefix" -opensource -confirm-license -release -static -no-rpath
    -platform linux-donut-host -xplatform linux-donut-llvm -arch "$qt_arch" -host-arch x86_64
    "${features[@]}" "$qt3_feature" -no-phonon -no-phonon-backend
    -no-webkit "${module_features[@]}"
    -no-dbus -no-glib -no-icu -no-iconv
    -no-openssl -no-nis -no-cups -no-pch -no-largefile
    -no-stl -exceptions -qt-zlib
    -nomake demos -nomake examples -nomake docs -nomake translations -nomake tests)
configuration=$({
    printf '%s\0' "${configure_args[@]}"
    sha256sum configure /work/donut-bin/donut-cxx /work/donut-bin/donut-cc
} | sha256sum)
configuration=${configuration%% *}
reconfigure=false
if [[ ! -f .donut-configured ]]; then reconfigure=true; fi
if [[ "$api" != 4 && "$(cat .longreach-configuration 2>/dev/null || true)" != "$configuration" ]]; then
    reconfigure=true
fi
if $reconfigure; then
    ./configure "${configure_args[@]}"
    printf '%s\n' "$configuration" > .longreach-configuration
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

if [[ "$api" != 4 && "$(cat .longreach-object-configuration 2>/dev/null || true)" != "$configuration" ]]; then
    # Make does not track changes to -D flags. Retain objects only when their
    # effective configuration matches; source-only fixes still rebuild incrementally.
    for module in corelib network gui sql xml svg script declarative testlib multimedia opengl scripttools xmlpatterns qt3support; do
        if [[ -f "src/$module/Makefile" ]]; then make -C "src/$module" clean; fi
    done
    # Record the flags before compilation so a failed partial build can resume.
    printf '%s\n' "$configuration" > .longreach-object-configuration
fi

make -C src -k -j2 "${modules[@]}"
if [[ "$profile" == core ]]; then
    test -s lib/libQtCore.a
    test -s bin/qmake
else
    for module in QtGui QtScript QtDeclarative QtSql QtXml QtSvg; do
        test -s "lib/lib$module.a"
    done
    if [[ "$api" != 4 && "$(cat .longreach-plugin-configuration 2>/dev/null || true)" != "$configuration" ]]; then
        for plugin in src/plugins/platforms/minimal src/plugins/imageformats/svg src/imports/folderlistmodel src/imports/gestures src/imports/particles src/imports/shaders; do
            if [[ -f "$plugin/Makefile" ]]; then make -C "$plugin" clean; fi
        done
        printf '%s\n' "$configuration" > .longreach-plugin-configuration
    fi
    make -C src/plugins/platforms/minimal -j2
fi
bin/qmake -v
