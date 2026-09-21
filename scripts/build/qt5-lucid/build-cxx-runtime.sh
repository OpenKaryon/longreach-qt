#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
# Static libstdc++ from GCC 5.5.0, configured against Lucid's glibc 2.11
# headers, so that no C++ runtime function needs a newer glibc symbol.
# The host's own libstdc++ archive was built against glibc 2.23 and would.
set -eu
jobs=${LUCID_JOBS:-6}
# x86_64-linux-gnu or i686-linux-gnu: the image's own compiler.
triple=$(gcc -dumpmachine)
mkdir -p /work/gcc-source /work/cxx-build /work/toolchain/bin
if [ ! -f /work/gcc-source/libstdc++-v3/configure ]; then
    tar -xJf /archives/gcc-5.5.0.tar.xz --strip-components=1 -C /work/gcc-source
fi
# The GCC top-level build normally generates this thread header selection.
ln -sf gthr-posix.h /work/gcc-source/libgcc/gthr-default.h
common='--sysroot=/work/sysroot -B/work/sysroot/usr/lib/ -L/work/sysroot/usr/lib -L/work/sysroot/lib -Wl,-rpath-link,/work/sysroot/lib:/work/sysroot/usr/lib'
cat > /work/toolchain/bin/lucid-gcc <<EOS
#!/bin/bash
exec /usr/bin/gcc $common "\$@"
EOS
cat > /work/toolchain/bin/lucid-g++ <<EOS
#!/bin/bash
exec /usr/bin/g++ $common "\$@"
EOS
chmod +x /work/toolchain/bin/lucid-*
export PATH=/work/toolchain/bin:$PATH
cd /work/cxx-build
CC=lucid-gcc CXX=lucid-g++ CFLAGS='-O2 -fPIC' CXXFLAGS='-O2 -fPIC' \
    /work/gcc-source/libstdc++-v3/configure \
    --prefix=/work/cxx-runtime --build="$triple" --host="$triple" \
    --disable-multilib --disable-nls --disable-shared --enable-static \
    --disable-libstdcxx-pch --with-gxx-include-dir=/work/cxx-runtime/include/c++/5.5.0
make -j "$jobs"
make install
cat > /work/toolchain/bin/lucid-g++ <<EOS
#!/bin/bash
exec /usr/bin/g++ $common -nostdinc++ -isystem /work/cxx-runtime/include/c++/5.5.0 -isystem /work/cxx-runtime/include/c++/5.5.0/$triple -isystem /work/cxx-runtime/include/c++/5.5.0/backward -L/work/cxx-runtime/lib "\$@"
EOS
chmod +x /work/toolchain/bin/lucid-g++
