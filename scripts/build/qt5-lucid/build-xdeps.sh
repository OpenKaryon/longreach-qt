#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
# Static X client pieces for the Lucid target, installed into the sysroot
# under /usr/local so that Lucid's own packages stay untouched:
#
#   libxcb 1.11.1  - only the extension wrappers (shm, shape, sync, xfixes,
#                    randr, render, glx, xkb, ...). The core libxcb.a is
#                    removed after installation, so -lxcb always resolves to
#                    Lucid's libxcb.so.1 (1.5): one libxcb per process, shared
#                    with the system libX11 and libGL.
#   xcb-util 0.4.0, -image 0.4.0, -keysyms 0.4.0, -renderutil 0.3.9, -wm 0.4.1
#   libxkbcommon 0.7.2 with xkbcommon-x11 (Lucid has neither)
#
# The headers and xcb.pc installed here say 1.11, which is what Qt 5.15's
# configure checks. Core functions newer than 1.5 are resolved at run time:
# the wrappers' two fd-passing calls through xcb-lucid-compat.c, Qt's own
# through patches/qt5/linux.
#
# The Lucid builds compile natively with lucid-gcc; the Ubuntu 14.04 arm64
# build (libxcb 1.10, xkbcommon 0.4.1) passes its cross compiler in XDEPS_CC
# and XDEPS_CXX and its binutils' ar in AR.
set -euo pipefail
jobs=${LUCID_JOBS:-6}
src=/work/xsrc
mkdir -p "$src"
export PATH=/work/toolchain/bin:$PATH
cc=${XDEPS_CC:-lucid-gcc}
cxx=${XDEPS_CXX:-lucid-g++}
ar=${AR:-ar}
host=$("$cc" -dumpmachine)
build=$(gcc -dumpmachine)

unpack() {
    local tarball=/xsrc/$1
    tar -xf "$tarball" -C "$src"
    echo "$src/$(tar -tf "$tarball" | head -1 | cut -d/ -f1)"
}

# xcb-proto is build-time input only (protocol XML and the C generator), so
# it goes onto the build host; pkg-config variables are not sysroot-prefixed.
dir=$(unpack xcb-proto-1.11.tar.bz2)
(cd "$dir" && ./configure --prefix=/usr/local > /dev/null && make install > /dev/null)
echo "built xcb-proto-1.11 (build host)"

export CC=$cc CXX=$cxx CFLAGS='-O2 -fPIC' CXXFLAGS='-O2 -fPIC'
export PKG_CONFIG_SYSROOT_DIR=/work/sysroot
export PKG_CONFIG_LIBDIR=/work/sysroot/usr/local/lib/pkgconfig:/work/sysroot/usr/local/share/pkgconfig:/work/sysroot/usr/lib/$host/pkgconfig:/work/sysroot/usr/lib/pkgconfig:/work/sysroot/usr/share/pkgconfig
common=(--prefix=/usr/local --enable-static --disable-shared --host="$host" --build="$build")

build() {   # build <tarball> [configure args...]
    local dir
    dir=$(unpack "$1"); shift
    # The older tarballs' config.sub predates aarch64: a cross build takes
    # the build host's (autotools-dev).
    if [ "$host" != "$build" ]; then
        find "$dir" \( -name config.sub -o -name config.guess \) -exec sh -c 'cp "/usr/share/misc/$(basename "$1")" "$1"' _ {} \;
    fi
    (cd "$dir" && ./configure "${common[@]}" "$@" > configure.log 2>&1 || { tail -40 configure.log; exit 1; }
     make -j "$jobs" > make.log 2>&1 || { tail -60 make.log; exit 1; }
     make install DESTDIR=/work/sysroot > /dev/null
     rm -f /work/sysroot/usr/local/lib/*.la)  # libtool archives point at absolute host paths
    echo "built $(basename "$dir")"
}

build libpthread-stubs-0.3.tar.bz2

# Calls to the five core functions newer than 1.5 that the wrappers and
# xcb-util use go through xcb-lucid-compat.c (system's own when present).
compat_defs='-Dxcb_send_fd=qt_lucid_xcb_send_fd -Dxcb_get_reply_fds=qt_lucid_xcb_get_reply_fds -Dxcb_discard_reply=qt_lucid_xcb_discard_reply -Dxcb_str_sizeof=qt_lucid_xcb_str_sizeof -Dxcb_sumof=qt_lucid_xcb_sumof'
# libxcb's configure reads the protocol location from the host xcb-proto.pc.
CFLAGS="$CFLAGS $compat_defs" \
PKG_CONFIG_LIBDIR=/usr/local/lib/pkgconfig:/usr/local/share/pkgconfig:$PKG_CONFIG_LIBDIR \
PKG_CONFIG_SYSROOT_DIR= XCBPROTO_CFLAGS=' ' XCBPROTO_LIBS=' ' \
    build libxcb-1.11.1.tar.bz2 --enable-xkb --enable-xinput --disable-xprint --disable-selinux \
        XCBPROTO_XCBINCLUDEDIR=/usr/local/share/xcb \
        XCBPROTO_XCBPYTHONDIR=/usr/local/lib/python2.7/site-packages \
        NEEDED_CFLAGS="-I/work/sysroot/usr/include" NEEDED_LIBS="-lXau -lXdmcp"
# Keep the extension archives, drop the core: Lucid's libxcb.so.1 is the core.
rm -f /work/sysroot/usr/local/lib/libxcb.a
"$cc" -O2 -fPIC -I/work/sysroot/usr/local/include -c /scripts/xcb-lucid-compat.c -o /tmp/xcb-lucid-compat.o
"$ar" rcs /work/sysroot/usr/local/lib/libxcb-lucid-compat.a /tmp/xcb-lucid-compat.o
sed -i 's/^Libs: -L${libdir} -lxcb$/Libs: -L${libdir} -lxcb-lucid-compat -lxcb -ldl/' \
    /work/sysroot/usr/local/lib/pkgconfig/xcb.pc
grep -q lucid-compat /work/sysroot/usr/local/lib/pkgconfig/xcb.pc

# libX11-xcb: Lucid's libx11-xcb1 is not on a stock install. A static stub
# that loads it at run time replaces the library -lX11-xcb finds, so no
# binary records libX11-xcb.so.1 as NEEDED. The .so.1 stays for the linker:
# 14.04's libGL needs it. (Lucid keeps it in /usr/lib, 14.04 in the multiarch
# directory.)
for x11xcb_pc in /work/sysroot/usr/lib/pkgconfig/x11-xcb.pc /work/sysroot/usr/lib/$host/pkgconfig/x11-xcb.pc; do
    [ -f "$x11xcb_pc" ] && break
done
x11xcb_lib=$(dirname "$(dirname "$x11xcb_pc")")
rm -f "$x11xcb_lib"/libX11-xcb.so "$x11xcb_lib"/libX11-xcb.a
"$cc" -O2 -fPIC -c /scripts/x11-xcb-stub.c -o /tmp/x11-xcb-stub.o
"$ar" rcs "$x11xcb_lib"/libX11-xcb.a /tmp/x11-xcb-stub.o
sed -i 's/^Libs: -L${libdir} -lX11-xcb$/Libs: -L${libdir} -lX11-xcb -ldl/' "$x11xcb_pc"
grep -q -- '-lX11-xcb -ldl' "$x11xcb_pc"

export CFLAGS="$CFLAGS $compat_defs"   # xcb_aux calls xcb_discard_reply
build xcb-util-0.4.0.tar.bz2
build xcb-util-image-0.4.0.tar.bz2
build xcb-util-keysyms-0.4.0.tar.bz2
build xcb-util-renderutil-0.3.9.tar.bz2
build xcb-util-wm-0.4.1.tar.bz2
# xcb-util-image needs xcb-util (xcb_aux); its .pc lists it only for
# --static, which Qt's configure does not pass.
sed -i 's/^\(Libs: -L${libdir} -lxcb-image\) *$/\1 -lxcb-util/' /work/sysroot/usr/local/lib/pkgconfig/xcb-image.pc
grep -q -- '-lxcb-image -lxcb-util' /work/sysroot/usr/local/lib/pkgconfig/xcb-image.pc
build libxkbcommon-0.7.2.tar.xz --disable-docs --enable-x11 \
    --with-xkb-config-root=/usr/share/X11/xkb --with-x-locale-root=/usr/share/X11/locale
ls /work/sysroot/usr/local/lib/*.a
