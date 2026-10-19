# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 4.8.7, static, for Windows i386 with MinGW-w64, from Windows 95: one SDK
# whose applications run on 95, 98, ME, NT 4.0, 2000, XP and later.
#
#   toolchain  the MinGW cross-compiler and the Win95 runtime objects
#   builder    OpenSSL, then Qt: patch, configure, build, install
#   final      the toolchain plus the installed SDK
#
# patches/qt4/windows restores the Windows 9x branches Qt removed in 4.6, each
# choosing the ANSI or older API at run time (each patch's header says how).
# Ubuntu 16.04: its MinGW-w64 GCC 5.3 has a runtime old enough for Windows 95.

# ---------------------------------------------------------------------------
# toolchain: the MinGW cross-compiler, shared by builder and final.
# ---------------------------------------------------------------------------

# Base images are pinned by digest; BASE_REGISTRY is where they are pulled
# from (the OpenKaryonLab copy, or docker.io/library: docs/sources.md).
ARG BASE_REGISTRY=ghcr.io/openkaryonlab
FROM --platform=linux/amd64 ${BASE_REGISTRY}/ubuntu:16.04@sha256:1f1a2d56de1d604801a9671f301190704c25d604a416f59e03c04f5c6ffee0d6 AS toolchain

# The win32 threading model: the posix one pulls in winpthreads, which needs
# APIs Windows 95 does not have.
RUN \
    set -eux && \
    export DEBIAN_FRONTEND=noninteractive && \
    echo 'Acquire::Retries "5";' > /etc/apt/apt.conf.d/80-retries && \
    apt -y update && \
    apt -y upgrade && \
    apt -y install \
        build-essential python perl git wget nano ca-certificates xz-utils \
        binutils-mingw-w64-i686 mingw-w64-i686-dev g++-mingw-w64-i686 gcc-mingw-w64-i686 && \
    update-alternatives --set i686-w64-mingw32-gcc /usr/bin/i686-w64-mingw32-gcc-win32 && \
    update-alternatives --set i686-w64-mingw32-g++ /usr/bin/i686-w64-mingw32-g++-win32 && \
    apt -y autoremove && \
    apt -y autoclean && \
    apt -y clean && \
    rm -rf /var/lib/apt/lists/* && \
    exit 0

# Two objects every application links (the mkspec adds them, see the builder):
#   exe-exit.o    atexit/_onexit through MSVCRT's own _onexit; MinGW-w64's
#                 table needs CRT locks the Windows 95 MSVCRT lacks (see the
#                 source);
#   gthr-win95.o  libgcc's thread glue with CreateSemaphoreW, absent on 95,
#                 renamed to CreateSemaphoreA - the names it creates are null.
COPY scripts/build/qt4-win95/win95-cxx14-exe-exit.c /opt/win95-cxx14/exe-exit.c
RUN \
    set -eux && \
    cd /opt/win95-cxx14 && \
    i686-w64-mingw32-gcc -Os -c exe-exit.c -o exe-exit.o && \
    i686-w64-mingw32-ar x "$(i686-w64-mingw32-g++ -print-libgcc-file-name)" gthr-win32.o && \
    i686-w64-mingw32-nm gthr-win32.o | grep -F '__imp__CreateSemaphoreW@16' && \
    i686-w64-mingw32-objcopy \
        --redefine-sym __imp__CreateSemaphoreW@16=__imp__CreateSemaphoreA@16 \
        gthr-win32.o gthr-win95.o && \
    rm gthr-win32.o

# ---------------------------------------------------------------------------
# builder: OpenSSL, then unpack, patch, configure, build and install Qt.
# ---------------------------------------------------------------------------
FROM toolchain AS builder

ARG QT4_VERSION="4.8.7"
ARG QT4_DISTRO="qt-everywhere-opensource-src-${QT4_VERSION}.tar.gz"
ARG QT4_SHA256="e2882295097e47fe089f8ac741a95fef47e0a73a3f3cdf21b56990638f626ea0"
# OpenSSL 1.0.2u: the last series that runs on Windows 95 (3.x needs XP).
# patches/qt4/all/06 makes Qt 4 select its TLS 1.2 ciphers by name.
ARG OPENSSL_DISTRO="openssl-1.0.2u.tar.gz"
ARG OPENSSL_SHA256="ecd0c6ffb493dd06707d38b14bb4d8c2288bb7033735606569d8f90f89669d16"
ARG DOWNLOAD_DIR="downloads"
ARG QT4_SRC_DIR="qt-everywhere-opensource-src-${QT4_VERSION}"
ARG PARALLEL_JOBS=""

COPY ${DOWNLOAD_DIR}/${OPENSSL_DISTRO} /opt/${OPENSSL_DISTRO}
RUN \
    set -eux && \
    echo "${OPENSSL_SHA256}  /opt/${OPENSSL_DISTRO}" | sha256sum -c - && \
    mkdir /tmp/openssl && \
    tar -xzf /opt/${OPENSSL_DISTRO} -C /tmp/openssl --strip-components=1 && \
    cd /tmp/openssl && \
    ./Configure mingw --cross-compile-prefix=i686-w64-mingw32- --prefix=/opt/openssl-1.0.2u \
        no-shared no-ssl2 no-asm no-capieng && \
    make depend && \
    make -j "${PARALLEL_JOBS:-$(nproc)}" && \
    make install_sw && \
    cp LICENSE /opt/openssl-1.0.2u/LICENSE && \
    rm -rf /tmp/openssl /opt/${OPENSSL_DISTRO}

COPY patches/qt4/all /tmp/patches/all
COPY patches/qt4/windows /tmp/patches/windows
COPY ${DOWNLOAD_DIR}/${QT4_DISTRO} /opt/${QT4_DISTRO}

# The cross invocation is Qt 4.8.7's own (see the header of
# mkspecs/win32-g++/qmake.conf); qmake, moc, rcc and uic come out as Linux
# binaries the build runs.
#
# For Windows 95 on top of the mkspec patch: no SIMD (the oldest CPUs it runs
# on have none, and the OS saves no SSE state), the 4.0 subsystem version
# (Windows 95 refuses a higher one), and the two runtime objects above.
#
# OPENSSL_LIBS reaches Qt 4's configure through the environment, not the
# argument list; without it the SSL compile test fails silently, hence the
# check after configure.
RUN \
    set -eux && \
    cd /opt && \
    echo "${QT4_SHA256}  /opt/${QT4_DISTRO}" | sha256sum -c - && \
    tar -xzf $QT4_DISTRO && \
    mv $QT4_SRC_DIR Qt-4.8 && \
    rm -f $QT4_DISTRO && \
    cd /opt/Qt-4.8/ && \
    for p in /tmp/patches/all/*.patch /tmp/patches/windows/*.patch; do echo "applying $p"; patch -p1 < "$p"; done && \
    printf '\nQMAKE_LFLAGS += -static -Wl,--major-subsystem-version,4,--minor-subsystem-version,0\nQMAKE_LIBS += /opt/win95-cxx14/exe-exit.o /opt/win95-cxx14/gthr-win95.o\n' \
        >> mkspecs/win32-g++/qmake.conf && \
    OPENSSL_LIBS="-L/opt/openssl-1.0.2u/lib -lssl -lcrypto -lws2_32 -lgdi32 -ladvapi32" \
    ./configure -prefix "/usr/local/Qt-4.8" \
    -opensource -confirm-license -release -static \
    -platform linux-g++ \
    -xplatform win32-g++ -device-option CROSS_COMPILE=i686-w64-mingw32- \
    -no-mmx -no-3dnow -no-sse -no-sse2 -no-sse3 -no-ssse3 -no-sse4.1 -no-sse4.2 -no-avx \
    -openssl-linked -I/opt/openssl-1.0.2u/include -L/opt/openssl-1.0.2u/lib \
    -nomake demos -nomake examples -nomake docs -nomake translations -nomake tests \
    -no-webkit -no-phonon -no-phonon-backend -no-glib -no-gtkstyle \
    -no-dbus -no-cups -no-icu -no-pch -no-separate-debug-info -no-openvg -no-fontconfig \
    -no-sql-mysql -no-sql-psql -no-sql-odbc -qt-sql-sqlite \
    -qt-zlib -qt-libpng -qt-libjpeg -qt-libtiff -qt-libmng \
    -opengl desktop -qt3support -xmlpatterns -script -scripttools -svg -declarative \
    -multimedia -audio-backend -accessibility -stl -exceptions -largefile \
    -D QT_NO_DIRECTWRITE && \
    grep -q "openssl-linked" mkspecs/qconfig.pri || \
        { echo "configure did not enable linked OpenSSL - check OPENSSL_LIBS" >&2; exit 1; } && \
    make -j "${PARALLEL_JOBS:-$(nproc)}" && \
    make install && \
    echo "SDK prefix to be shipped:" && du -sh /usr/local/Qt-4.8 && \
    exit 0

# ---------------------------------------------------------------------------
# final: the shipped SDK - the toolchain stage plus the `make install` output.
# ---------------------------------------------------------------------------
FROM toolchain

COPY --from=builder /usr/local/Qt-4.8 /usr/local/Qt-4.8
# libQtNetwork.prl records -lssl -lcrypto and the -L path, and qmake resolves
# those when an application links QtNetwork, so the OpenSSL build travels too.
COPY --from=builder /opt/openssl-1.0.2u /opt/openssl-1.0.2u

ENV QTDIR=/usr/local/Qt-4.8
ENV PATH="/usr/local/Qt-4.8/bin:${PATH}"
LABEL org.openkaryon.longreach-qt.platform="windows-i386-win95" \
      org.openkaryon.longreach-qt.openssl="1.0.2u"

ENTRYPOINT []
