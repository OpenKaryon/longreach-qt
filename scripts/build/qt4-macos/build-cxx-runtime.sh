#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail
jobs=${TIGER_JOBS:-6}
mkdir -p /work/gcc-source /work/cxx-build
tar -xJf /archives/gcc-5.5.0.tar.xz --strip-components=1 -C /work/gcc-source
ln -sf gthr-posix.h /work/gcc-source/libgcc/gthr-default.h
# Darwin uses absolute/PC-relative exception data. Its unwinder does not
# implement text/data-relative bases; reject those encodings explicitly.
python3 - <<'PY'
from pathlib import Path
p = Path('/work/gcc-source/libgcc/unwind-pe.h')
s = p.read_text()
for function in ('_Unwind_GetTextRelBase', '_Unwind_GetDataRelBase'):
    s = s.replace('      return ' + function + ' (context);',
                  '#ifdef __APPLE__\n      __gxx_abort ();\n#else\n      return '
                  + function + ' (context);\n#endif')
p.write_text(s)
PY
cd /work/cxx-build
# Rebuild only the C++ runtime, using clang and Tiger headers. The original
# SDK's GCC 4.0 headers do not supply std::function used by our shared suite.
CC=i386-apple-darwin8-clang CXX=i386-apple-darwin8-clang++ \
    AR=i386-apple-darwin8-ar RANLIB=i386-apple-darwin8-ranlib \
    CFLAGS='-Os -fno-blocks' CXXFLAGS='-Os -fno-blocks' \
    /work/gcc-source/libstdc++-v3/configure \
    --prefix=/opt/tiger-cxx --build=x86_64-pc-linux-gnu --host=i386-apple-darwin8 \
    --disable-multilib --disable-nls --disable-shared --enable-static \
    --disable-libstdcxx-pch --with-gxx-include-dir=/opt/tiger-cxx/include/c++/5.5.0
# GCC 5 defaulted to C++98; clang 14 defaults to C++14. Keep the C++98
# implementation's legacy operator void*, without overriding C++11/14 units.
sed -i 's/^AM_CXXFLAGS =/AM_CXXFLAGS = -std=gnu++98/' src/c++98/Makefile
make -j "$jobs"
make install
mkdir -p /opt/qt4-licenses
cp /work/gcc-source/COPYING3 /opt/qt4-licenses/GCC-COPYING3.txt
cp /work/gcc-source/COPYING.RUNTIME /opt/qt4-licenses/GCC-RUNTIME-EXCEPTION.txt
cat > /opt/tiger-toolchain/bin/tiger-clang++ <<'EOF'
#!/bin/bash
link=yes
for arg in "$@"; do
    case "$arg" in -c|-E|-S|-dump*|-print*|--version|-v) link=no;; esac
done
extra=()
if [ "$link" = yes ]; then
    extra=(/opt/tiger-cxx/lib/libstdc++.a /opt/tiger-toolchain/SDK/MacOSX10.4u.sdk/usr/lib/gcc/i686-apple-darwin10/4.0.1/libgcc.a -lgcc_s.10.4)
fi
exec i386-apple-darwin8-clang++ -fno-blocks -nostdlib++ -nostdinc++ -isystem /opt/tiger-cxx/include/c++/5.5.0 -isystem /opt/tiger-cxx/include/c++/5.5.0/i386-apple-darwin8 -isystem /opt/tiger-cxx/include/c++/5.5.0/backward "$@" "${extra[@]}"
EOF
chmod +x /opt/tiger-toolchain/bin/tiger-clang++
printf '#include <functional>\nint main(){std::function<int()> f=[](){return 0;};return f();}\n' > /tmp/tiger-cxx14.cpp
tiger-clang++ -std=gnu++14 /tmp/tiger-cxx14.cpp -o /tmp/tiger-cxx14-probe
file /tmp/tiger-cxx14-probe
i386-apple-darwin8-otool -L /tmp/tiger-cxx14-probe
