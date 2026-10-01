#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -eu
source "$(dirname "$0")/arch.sh"
jobs=${SARGE_JOBS:-6}
root=/work/sysroot
mkdir -p /work/gcc-source /work/cxx-build /work/toolchain/bin
if [ ! -f /work/gcc-source/libstdc++-v3/configure ]; then
    tar -xJf /archives/gcc-5.5.0.tar.xz --strip-components=1 -C /work/gcc-source
fi
# The GCC top-level build normally generates this selected thread header.
# Supply the same POSIX selection for a standalone libstdc++ build.
ln -sf gthr-posix.h /work/gcc-source/libgcc/gthr-default.h
cat > /work/toolchain/bin/sarge-gcc <<'EOF'
#!/bin/bash
exec /usr/bin/gcc --sysroot=/work/sysroot -std=gnu89 -fgnu89-inline -fno-stack-protector -fno-gnu-unique -Wl,--hash-style=sysv -B/work/sysroot/usr/lib/ -L/work/sysroot/usr/lib -Wl,-rpath-link,/work/sysroot/lib:/work/sysroot/usr/lib:/work/sysroot/usr/X11R6/lib "$@"
EOF
cat > /work/toolchain/bin/sarge-g++ <<'EOF'
#!/bin/bash
exec /usr/bin/g++ --sysroot=/work/sysroot -fno-stack-protector -fno-gnu-unique -Wl,--hash-style=sysv -B/work/sysroot/usr/lib/ -L/work/sysroot/usr/lib -Wl,-rpath-link,/work/sysroot/lib:/work/sysroot/usr/lib:/work/sysroot/usr/X11R6/lib "$@"
EOF
chmod +x /work/toolchain/bin/sarge-*
export PATH=/work/toolchain/bin:$PATH
cd /work/cxx-build
CC=sarge-gcc CXX=sarge-g++ CFLAGS='-Os' CXXFLAGS='-Os' \
    /work/gcc-source/libstdc++-v3/configure \
    --prefix=/work/cxx-runtime --build="$SARGE_TRIPLE" --host="$SARGE_TRIPLE" \
    --disable-multilib --disable-nls --disable-shared --enable-static \
    --disable-libstdcxx-pch --with-gxx-include-dir=/work/cxx-runtime/include/c++/5.5.0
make clean
rm -f /work/cxx-build/src/c++98/atomicity.cc
make -j "$jobs"
make install
cat > /work/toolchain/bin/sarge-g++ <<EOF
#!/bin/bash
exec /usr/bin/g++ --sysroot=/work/sysroot -fno-stack-protector -fno-gnu-unique -Wl,--hash-style=sysv -B/work/sysroot/usr/lib/ -nostdinc++ -isystem /work/cxx-runtime/include/c++/5.5.0 -isystem /work/cxx-runtime/include/c++/5.5.0/$SARGE_TRIPLE -isystem /work/cxx-runtime/include/c++/5.5.0/backward -L/work/cxx-runtime/lib -L/work/sysroot/usr/lib -Wl,-rpath-link,/work/sysroot/lib:/work/sysroot/usr/lib:/work/sysroot/usr/X11R6/lib "\$@"
EOF
chmod +x /work/toolchain/bin/sarge-g++
sarge-g++ -std=gnu++14 -pthread -static-libgcc -static-libstdc++ /work/probe/probe.cpp -o /work/probe/probe
readelf -V /work/probe/probe
"$root$SARGE_LOADER" --library-path "$root/lib:$root/usr/lib" /work/probe/probe
