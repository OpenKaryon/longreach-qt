#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail

source=/build/qt-everywhere-src-5.15.19
archive=/src/qt.tar.xz
patches=/src/patches/qt5
prefix=/opt/qt5-linux-arm64-llvm

echo "173c2326dae138bbb0d98921e9d911e55c00163d93a6db29f294b5e19ff306ae  $archive" | sha256sum -c -
/opt/llvm-21/bin/clang --version | grep -E '^clang version 21\.1\.8([[:space:]]|$)'
wayland-scanner --version

mkdir -p /build /opt/qt5-llvm/bin
tar -xJf "$archive" -C /build --exclude='*/qtwebengine/*'
cd "$source"
for patch in "$patches"/{all,linux,linux-arm64-llvm}/*.patch; do
    git apply "$patch"
done

# Keep the legacy headers and startup files, but use upstream Clang, LLD
# and the static ARM64 LLVM runtimes already built against glibc 2.17.
for tool in cc cxx; do
    compiler=clang
    stdlib=
    if [ "$tool" = cxx ]; then
        compiler=clang++
        stdlib='-stdlib=libc++ -nostdinc++ -isystem /opt/llvm-runtime-21/include/c++/v1'
    fi
    cat > "/opt/qt5-llvm/bin/target-$tool" <<EOF
#!/bin/bash
exec /opt/llvm-21/bin/$compiler $stdlib --target=aarch64-unknown-linux-gnu \
    --sysroot=/work/sysroot -resource-dir=/opt/llvm-runtime-21/resource -Qunused-arguments \
    -nostdinc -isystem /opt/llvm-21/lib/clang/21/include -pthread \
    -isystem /work/sysroot/usr/local/include -isystem /work/sysroot/usr/include/aarch64-linux-gnu \
    -isystem /work/sysroot/usr/include -B/work/sysroot/usr/lib/aarch64-linux-gnu \
    -L/opt/llvm-runtime-21/lib -L/work/sysroot/usr/local/lib -L/work/sysroot/lib/aarch64-linux-gnu \
    -L/work/sysroot/usr/lib/aarch64-linux-gnu -Wl,-rpath-link,/work/sysroot/lib/aarch64-linux-gnu:/work/sysroot/usr/lib/aarch64-linux-gnu \
    --rtlib=compiler-rt --unwindlib=libunwind -fuse-ld=lld -Wl,--threads=2 "\$@"
EOF
    chmod +x "/opt/qt5-llvm/bin/target-$tool"
done

mkspecs=/src/qt5-linux-arm64/mkspecs
spec="$source/qtbase/mkspecs/linux-trusty-aarch64-clang"
mkdir -p "$spec"
cp "$mkspecs/linux-trusty-aarch64-clang/qmake.conf" "$spec/"
cp "$mkspecs/linux-trusty-aarch64-g++/qplatformdefs.h" "$spec/"

mkdir /build/qt
cd /build/qt
"$source/configure" -opensource -confirm-license -prefix "$prefix" \
    -platform linux-g++ -xplatform linux-trusty-aarch64-clang -pkg-config \
    OPENSSL_PATH=/opt/openssl-3 OPENSSL_LIBS="-L/opt/openssl-3/lib -lssl -lcrypto -ldl -pthread" \
    -c++std c++14 -static -optimize-size -release \
    -xcb -bundled-xcb-xinput -xkbcommon -fontconfig -system-freetype \
    -nomake examples -nomake tests -nomake tools \
    -no-cups -dbus-runtime -alsa -pulseaudio -gstreamer 1.0 -speechd -gif -no-iconv -no-icu -no-glib \
    -opengl desktop -openssl-linked -no-openvg -no-pch \
    -sql-sqlite -qt-sqlite -ssl -no-libudev -no-libinput -no-mtdev -no-tslib \
    -make libs -qt-harfbuzz -qt-libjpeg -qt-libpng -qt-pcre -qt-zlib \
    -skip qtwebengine

# Missing host tools can silently remove both of these modules.
grep -E '^Qt Wayland Client \.+ yes$' config.summary
grep -E '^Qt Wayland Compositor \.+ yes$' config.summary
make -j"${PARALLEL_JOBS:-4}"
make install
install -m 644 config.summary "$prefix/qt-config.summary"
for module in Core Widgets WaylandClient WaylandCompositor; do
    test -f "$prefix/lib/libQt5$module.a"
done
test "$("$prefix/bin/qmake" -query QT_VERSION)" = 5.15.19
