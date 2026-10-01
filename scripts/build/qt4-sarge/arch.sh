# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Sourced by the Sarge build scripts: what differs between the i386 and amd64
# targets. SARGE_ARCH comes from the Dockerfile; the build image's own GCC is
# the one for that architecture.
case "${SARGE_ARCH:-i386}" in
    i386)
        SARGE_TRIPLE=i686-linux-gnu
        SARGE_QT_ARCH=i386
        SARGE_LOADER=/lib/ld-linux.so.2
        SARGE_OPENSSL_TARGET=linux-elf
        ;;
    amd64)
        SARGE_TRIPLE=x86_64-linux-gnu
        SARGE_QT_ARCH=x86_64
        SARGE_LOADER=/lib/ld-linux-x86-64.so.2
        SARGE_OPENSSL_TARGET=linux-x86_64
        ;;
    *)
        echo "unknown SARGE_ARCH: $SARGE_ARCH" >&2
        exit 1
        ;;
esac
SARGE_SPEC=linux-sarge-${SARGE_ARCH:-i386}-g++
export SARGE_TRIPLE SARGE_QT_ARCH SARGE_LOADER SARGE_OPENSSL_TARGET SARGE_SPEC
