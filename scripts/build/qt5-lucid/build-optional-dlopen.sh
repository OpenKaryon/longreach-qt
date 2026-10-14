#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Wayland, ALSA, PulseAudio, speech-dispatcher, BlueZ and GStreamer for the
# Lucid build (and the 14.04 arm64 one, docker/qt5/linux/arm64) without
# making any of them a dependency: the build image's
# (Ubuntu 16.04) headers, and in place of the libraries stub archives
# (scripts/build/dlopen) that load them at run time. Lucid has no libwayland
# and no GStreamer 1.0; it has ALSA, PulseAudio 0.9.21 and speech-dispatcher
# 0.6. Where a library is missing, Qt finds no Wayland display (and uses xcb),
# no audio device, no speech engine, no Bluetooth adapter or no media
# backend.
set -eu
dlopen=/scripts/dlopen
sysroot=/work/sysroot
prefix=$sysroot/usr/local
lib=$prefix/lib
include=$prefix/include
# The build image's libraries give the function names, which are the same for
# every architecture; the arm64 build compiles the stubs with its own CC.
multiarch=$(dpkg-architecture -qDEB_BUILD_MULTIARCH)
so=/usr/lib/$multiarch
export CC=${CC:-lucid-gcc}
mkdir -p "$lib/pkgconfig" "$include" "$sysroot/usr/bin"

version() { dpkg-query -W -f='${Version}' "$1" | sed -e 's/^[0-9]*://' -e 's/[-+].*//'; }

# The scanner is copied into the sysroot so that the path wayland-scanner.pc
# names works whether or not pkg-config prefixes it with the sysroot.
# libwayland 1.12 also exports its private wl_map functions, which later
# versions do not: the symbol reader leaves them out, or the stubs would take
# every newer libwayland for an older one (wayland.sh treats a library that
# lacks a stubbed function as missing).
cat > /tmp/nm-wayland <<EOF
#!/bin/sh
${NM:-nm} "\$@" | grep -v ' wl_map_'
EOF
chmod +x /tmp/nm-wayland
NM=/tmp/nm-wayland WAYLAND_LIBDIR=$so WAYLAND_VERSION=$(version libwayland-dev) \
    WAYLAND_SCANNER_PC=/usr/bin/wayland-scanner bash "$dlopen/wayland.sh" "$prefix" /usr/local
cp /usr/bin/wayland-scanner "$sysroot/usr/bin/wayland-scanner"

# pc NAME VERSION LIBS [CFLAGS]
pc() {
    cat > "$lib/pkgconfig/$1.pc" <<EOF
prefix=/usr/local
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: $1 (dlopen stubs)
Description: $1, loaded at run time
Version: $2
Cflags: -I\${includedir} ${4:-}
Libs: -L\${libdir} $3 -ldl
EOF
}

# ALSA reports success with 0, so the calls that open a device or list them
# fail with -ENOENT; Qt reaches the others only through what those return.
cp -r /usr/include/alsa "$include/"
bash "$dlopen/archive.sh" "$lib/libasound.a" longreach_alsa \
    --fail snd_pcm_open=-2 --fail snd_device_name_hint=-2 --fail snd_card_get_name=-2 \
    libasound.so.2="$so/libasound.so.2"
pc alsa "$(version libasound2-dev)" -lasound

# PulseAudio: Qt stops when pa_threaded_mainloop_new returns NULL. Qt's
# configure test includes glib-mainloop.h, which includes glib.h, and calls
# pa_glib_mainloop_new; Qt itself makes no glib call.
cp -r /usr/include/pulse /usr/include/glib-2.0 "$include/"
mkdir -p "$lib/glib-2.0/include"
cp "$so/glib-2.0/include/glibconfig.h" "$lib/glib-2.0/include/"
bash "$dlopen/archive.sh" "$lib/libpulse-dlopen.a" longreach_pulse \
    libpulse.so.0="$so/libpulse.so.0" libpulse-mainloop-glib.so.0="$so/libpulse-mainloop-glib.so.0"
pc libpulse "$(version libpulse-dev)" -lpulse-dlopen
pc libpulse-mainloop-glib "$(version libpulse-dev)" -lpulse-dlopen \
    '-I${includedir}/glib-2.0 -I${libdir}/glib-2.0/include'

# speech-dispatcher: Qt stops when spd_open returns NULL.
cp -r /usr/include/speech-dispatcher "$include/"
bash "$dlopen/archive.sh" "$lib/libspeechd.a" longreach_speechd \
    --fail spd_list_modules=longreach_speechd_no_modules --extra /scripts/speechd-missing.c \
    libspeechd.so.2="$so/libspeechd.so.2"
pc speech-dispatcher "$(version libspeechd-dev)" -lspeechd '-I${includedir}/speech-dispatcher'

# BlueZ: Qt talks to bluetoothd over D-Bus and to the kernel over sockets,
# with its own copies of the structures; it calls no libbluetooth function,
# but its configure test links the library and includes its headers.
cp -r /usr/include/bluetooth "$include/"
bash "$dlopen/archive.sh" "$lib/libbluetooth.a" longreach_bluez libbluetooth.so.3="$so/libbluetooth.so.3"
pc bluez "$(version libbluetooth-dev)" -lbluetooth

# GStreamer 1.0, which Lucid does not have, and the GLib it brings: Qt starts
# its GStreamer services only when gst_init_check succeeds
# (patches/qt5/linux/04). The types Qt reads through macros (GST_TYPE_BUFFER
# and the like) are data, mirrored into the archive and copied again after
# gst_init (gstreamer-init.c).
gst_libs=()
for name in glib-2.0 gobject-2.0 gstreamer-1.0 gstbase-1.0 gstaudio-1.0 gstvideo-1.0 \
            gstpbutils-1.0 gstallocators-1.0 gstapp-1.0 gsttag-1.0; do
    library=$(ls "/lib/$multiarch/lib$name.so.0" "$so/lib$name.so.0" 2>/dev/null | head -1)
    gst_libs+=("lib$name.so.0=$library")
done
cp -r /usr/include/gstreamer-1.0 "$include/"
mkdir -p "$lib/gstreamer-1.0/include/gst"
cp "$so/gstreamer-1.0/include/gst/gstconfig.h" "$lib/gstreamer-1.0/include/gst/"
bash "$dlopen/archive.sh" "$lib/libgstreamer-dlopen.a" longreach_gst --mirror \
    --skip gst_init --skip gst_init_check --extra /scripts/gstreamer-init.c "${gst_libs[@]}"
glib_cflags='-I${includedir}/glib-2.0 -I${libdir}/glib-2.0/include'
for name in glib-2.0 gobject-2.0; do
    pc "$name" "$(version libglib2.0-dev)" -lgstreamer-dlopen "$glib_cflags"
done
for name in gstreamer gstreamer-base gstreamer-audio gstreamer-video gstreamer-pbutils \
            gstreamer-allocators gstreamer-app gstreamer-tag; do
    pc "$name-1.0" "$(version libgstreamer1.0-dev)" -lgstreamer-dlopen \
        "-I\${includedir}/gstreamer-1.0 -I\${libdir}/gstreamer-1.0/include $glib_cflags"
done

# Exported data has no stub; Qt must not need any.
for archive in asound pulse-dlopen speechd bluetooth gstreamer-dlopen; do
    data=$lib/lib$archive.a.data
    if [ -s "$data" ]; then
        echo "lib$archive.a: data without stubs: $(tr '\n' ' ' < "$data")"
    fi
    rm "$data"
done
