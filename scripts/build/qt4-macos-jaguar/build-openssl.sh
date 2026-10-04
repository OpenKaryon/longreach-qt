#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
# OpenSSL 1.0.2u for Mac OS X 10.2 / PowerPC with the Jaguar compiler, as the
# Tiger PowerPC build uses it (static, no assembler). no-dso: the DSO layer
# loads engines with dlopen, which 10.2 does not have. The headers are the
# 10.4u ones the Qt mkspec uses, with a 10.2 deployment target; the command
# line tool's imports are checked against the 10.2.8 SDK.
set -euo pipefail
jobs=${JAGUAR_JOBS:-6}
sdk=/opt/osxcross-ppc/target/SDK/MacOSX10.4u.sdk
bin=/opt/osxcross-ppc/target/bin
flags="-isysroot $sdk -nostdinc -isystem /opt/jaguar-gcc/lib/gcc/powerpc-apple-darwin8/5.5.0/include \
-isystem /opt/osxcross-ppc/target/lib/gcc/powerpc-apple-darwin8/5.5.0/include-fixed \
-isystem $sdk/usr/include -mmacosx-version-min=10.2"
echo 'ecd0c6ffb493dd06707d38b14bb4d8c2288bb7033735606569d8f90f89669d16  /archives/openssl-1.0.2u.tar.gz' | sha256sum -c -
mkdir -p /work/openssl-jaguar
cd /work/openssl-jaguar
tar -xzf /archives/openssl-1.0.2u.tar.gz --strip-components=1
./Configure darwin-ppc-cc --prefix=/opt/openssl-jaguar no-shared no-asm no-capieng no-dso > /out/openssl-configure.log 2>&1
tools=(CC="/opt/jaguar-gcc/bin/powerpc-apple-darwin8-gcc $flags" AR="$bin/powerpc-apple-darwin8-ar r"
       RANLIB="$bin/powerpc-apple-darwin8-ranlib")
make -j "$jobs" "${tools[@]}" > /out/openssl-build.log 2>&1 || { tail -30 /out/openssl-build.log; exit 1; }
make install_sw "${tools[@]}" > /out/openssl-install.log 2>&1
mkdir -p /opt/qt4-licenses
cp LICENSE /opt/qt4-licenses/OPENSSL-LICENSE.txt
python3 /scripts/check-imports.py /opt/openssl-jaguar/bin/openssl /out/openssl-jaguar-imports.txt
