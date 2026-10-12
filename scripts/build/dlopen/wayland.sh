#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Wayland without libwayland at link time, for builds whose binaries must also
# start where no libwayland is installed:
#
#   wayland.sh INSTALL_PREFIX PC_PREFIX
#
# installs into INSTALL_PREFIX the libwayland headers and libwayland-dlopen.a,
# whose stubs (archive.sh) load libwayland-client, -server, -cursor and -egl
# at run time, with .pc files that name PC_PREFIX (what pkg-config's sysroot
# is prefixed to, if any). libwayland-{client,server,cursor,egl}.a are links
# to the same archive, for build systems that look for the library files.
# The protocol's interface tables, which libwayland exports as data, are
# generated from wayland.xml and compiled in. Where no libwayland is
# installed, Qt finds no Wayland display and uses xcb, as it does without a
# Wayland session.
#
#   WAYLAND_LIBDIR      the build's libwayland-*.so.0 (required)
#   WAYLAND_EGL         the build's libwayland-egl.so.1, if any
#   WAYLAND_EGL_VERSION its version (Mesa's, where Mesa provides it)
#   WAYLAND_INCLUDEDIR  their headers (/usr/include)
#   WAYLAND_XML         the core protocol (/usr/share/wayland/wayland.xml)
#   WAYLAND_SCANNER     a wayland-scanner the build host runs (wayland-scanner)
#   WAYLAND_SCANNER_PC  the scanner path wayland-scanner.pc names (the same)
#   WAYLAND_VERSION     the libraries' version (the scanner's)
#   CC, NM, AR          as for archive.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
prefix=$1
pc_prefix=$2
libdir=${WAYLAND_LIBDIR:?WAYLAND_LIBDIR names the libwayland directory}
includedir=${WAYLAND_INCLUDEDIR:-/usr/include}
xml=${WAYLAND_XML:-/usr/share/wayland/wayland.xml}
scanner=${WAYLAND_SCANNER:-$(command -v wayland-scanner)}
version=${WAYLAND_VERSION:-$("$scanner" --version 2>&1 | awk '{ print $NF }')}
work=$(mktemp -d)
mkdir -p "$prefix/lib/pkgconfig" "$prefix/include"

libraries=(libwayland-client.so.0="$libdir/libwayland-client.so.0"
           libwayland-server.so.0="$libdir/libwayland-server.so.0"
           libwayland-cursor.so.0="$libdir/libwayland-cursor.so.0")
if [ -n "${WAYLAND_EGL:-}" ]; then
    libraries+=(libwayland-egl.so.1="$WAYLAND_EGL")
fi

cp "$includedir"/wayland-*.h "$prefix/include/"
"$scanner" code < "$xml" > "$work/wayland-protocol.c"
CFLAGS="-I$prefix/include" bash "$here/archive.sh" "$prefix/lib/libwayland-dlopen.a" longreach_wayland \
    --extra "$work/wayland-protocol.c" "${libraries[@]}"
# Every exported data symbol must come from the generated tables.
for symbol in $(cat "$prefix/lib/libwayland-dlopen.a.data"); do
    grep -q "^WL_EXPORT const struct wl_interface $symbol = " "$work/wayland-protocol.c" \
        || { echo "no table for $symbol" >&2; exit 1; }
done
rm "$prefix/lib/libwayland-dlopen.a.data"
for lib in client server cursor ${WAYLAND_EGL:+egl}; do
    ln -sf libwayland-dlopen.a "$prefix/lib/libwayland-$lib.a"
done

pc() {
    cat > "$prefix/lib/pkgconfig/$1.pc" <<EOF
prefix=$pc_prefix
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: $1 (dlopen stubs)
Description: $1, loaded at run time by libwayland-dlopen.a
Version: $2
Cflags: -I\${includedir}
Libs: -L\${libdir} -lwayland-dlopen -ldl
EOF
}
pc wayland-client "$version"
pc wayland-server "$version"
pc wayland-cursor "$version"
if [ -n "${WAYLAND_EGL:-}" ]; then
    pc wayland-egl "${WAYLAND_EGL_VERSION:-$version}"
fi
cat > "$prefix/lib/pkgconfig/wayland-scanner.pc" <<EOF
wayland_scanner=${WAYLAND_SCANNER_PC:-$scanner}

Name: Wayland scanner
Description: the build host's wayland-scanner
Version: $version
EOF
echo "libwayland-dlopen.a, wayland $version: ${#libraries[@]} libraries"
rm -rf "$work"
