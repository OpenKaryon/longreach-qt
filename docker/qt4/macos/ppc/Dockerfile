# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 4.8.7 with upstream LLVM 21.1.8 for Mac OS X 10.2 Jaguar (PowerPC).
# Keep cctools and the GCC driver and CRT that provide the Darwin 10.2 ABI.

ARG SDK_IMAGE=sdk
ARG BASE_REGISTRY=ghcr.io/openkaryonlab
ARG LLVM_COMPILER_IMAGE=longreach-llvm:21.1.8-compiler

FROM --platform=linux/amd64 ${BASE_REGISTRY}/ubuntu:22.04@sha256:5ec03bb3441e8b0bf3b4f9cd4629a1ae763010dc3035bb8da3ae6cf026486401 AS osxcross
ARG APT_SNAPSHOT
COPY scripts/build/apt-snapshot.sh /usr/local/bin/apt-snapshot
ENV DEBIAN_FRONTEND=noninteractive
RUN sh /usr/local/bin/apt-snapshot "$APT_SNAPSHOT" && apt-get update && apt-get install -y --no-install-recommends \
    build-essential clang llvm-dev cmake git patch python3 perl curl ca-certificates \
    autoconf automake libtool libssl-dev libxml2-dev liblzma-dev zlib1g-dev \
    libbz2-dev bzip2 xz-utils file && rm -rf /var/lib/apt/lists/*
ARG JOBS=6
RUN apt-get update && apt-get install -y --no-install-recommends libgmp-dev libmpfr-dev libmpc-dev wget && rm -rf /var/lib/apt/lists/*
# osxcross's ppc-test branch, by commit, from the OpenKaryonLab copy.
ARG LAB_GIT=https://github.com/OpenKaryonLab
COPY scripts/build/git-fetch-pinned.sh /tmp/
RUN bash /tmp/git-fetch-pinned.sh /opt/osxcross-ppc af8300c6b3e099c91970a8d2d0f3bffe703f2421 \
        "$LAB_GIT/osxcross.git"
# Its build.sh clones xar's master from upstream; xar comes from the copy at
# the commit the other osxcross builds pin instead.
RUN cd /opt/osxcross-ppc \
    && sed -i 's#^git clone https://github.com/tpoechtrager/xar.git$#bash /tmp/git-fetch-pinned.sh xar 5fa4675419cfec60ac19a9c7f7c2d0e7c831a497 "$LAB_GIT/xar.git"#' build.sh \
    && grep -q '^bash /tmp/git-fetch-pinned.sh xar ' build.sh \
    && ! grep -q 'github.com/tpoechtrager' build.sh
COPY downloads/MacOSX10.4u.sdk.tar.xz /opt/osxcross-ppc/tarballs/
RUN cd /opt/osxcross-ppc \
    && echo 'd28276ce6b0f14af30f3bfdc171f8ef4033652da593578568f8be189506c1021  tarballs/MacOSX10.4u.sdk.tar.xz' | sha256sum -c - \
    && UNATTENDED=1 OSX_VERSION_MIN=10.4 JOBS="$JOBS" DISABLE_LTO_SUPPORT=1 ./build.sh

# ---------------------------------------------------------------------------
FROM osxcross AS gcc-compiler
ARG JOBS=6
COPY downloads/gcc-5.5.0.tar.xz /archives/gcc-5.5.0.tar.xz
RUN echo '530cea139d82fe542b358961130c69cfde8b3d14556370b65823d2f91f0ced87  /archives/gcc-5.5.0.tar.xz' | sha256sum -c - \
    && mkdir -p /work/ppc-gcc-source /work/ppc-gcc-build \
    && tar -xJf /archives/gcc-5.5.0.tar.xz -C /work/ppc-gcc-source --strip-components=1
ENV PATH=/opt/osxcross-ppc/target/bin:$PATH
ENV DISABLE_ANNOYING_LD64_ASSERTION=1
COPY scripts/build/qt4-macos-ppc/gcc55-objcxx-legacy-eh.patch /scripts/gcc55-objcxx-legacy-eh.patch
RUN cd /work/ppc-gcc-source && patch -p1 --fuzz=0 < /scripts/gcc55-objcxx-legacy-eh.patch
RUN cd /work/ppc-gcc-build \
    && CXXFLAGS='-O2 -std=gnu++98' /work/ppc-gcc-source/configure \
       --target=powerpc-apple-darwin8 --prefix=/opt/osxcross-ppc/target \
       --with-sysroot=/opt/osxcross-ppc/target/SDK/MacOSX10.4u.sdk \
       --with-as=/opt/osxcross-ppc/target/bin/powerpc-apple-darwin8-as \
       --with-ld=/opt/osxcross-ppc/target/bin/powerpc-apple-darwin8-ld \
       --with-cpu=750 --enable-languages=c,c++,objc,obj-c++ \
       --enable-checking=release --disable-nls --disable-multilib \
       --disable-libsanitizer --disable-libquadmath --disable-libgomp \
       --disable-libssp --disable-libobjc --disable-libatomic --disable-libstdcxx-pch \
       --disable-shared --enable-static --with-system-zlib \
    && make -j "$JOBS" all-gcc all-target-libgcc \
    && make install-gcc install-target-libgcc -j "$JOBS"
FROM gcc-compiler AS gcc-runtime
RUN apt-get update && apt-get install -y --no-install-recommends gcc-multilib g++-multilib
RUN dpkg --add-architecture i386 && apt-get update && apt-get install -y --no-install-recommends uuid-dev:i386
RUN cp -a /opt/osxcross-ppc/build/cctools-877.8-ld64-253.9_e2c9d34/cctools /work/classic32 \
    && cd /work/classic32 && make distclean \
    && CC='clang-14 -m32' CXX='clang++-14 -m32' CFLAGS='-O2 -D_FILE_OFFSET_BITS=64' ./configure --target=x86_64-apple-darwin8 --prefix=/opt/osxcross-ppc/target --disable-lto-support --with-llvm-config=/bin/false \
    && make -C libstuff -j "$JOBS" \
    && make -C ld -j "$JOBS" \
    && make -C ld install
RUN ln -sf x86_64-apple-darwin8-ld_classic /opt/osxcross-ppc/target/bin/powerpc-apple-darwin8-ld \
    && powerpc-apple-darwin8-gcc -dumpspecs | sed '/^\*libgcc:$/ {n;s/.*/-lgcc/;}' > /opt/osxcross-ppc/target/lib/gcc/powerpc-apple-darwin8/5.5.0/specs
RUN printf 'int main(void){return 0;}\n' > /tmp/ppc.c \
    && powerpc-apple-darwin8-gcc -v -static-libgcc -mmacosx-version-min=10.4 /tmp/ppc.c -o /tmp/ppc \
    && file /tmp/ppc && powerpc-apple-darwin8-otool -l /tmp/ppc

# GCC 5.5 driver and CRT for Mac OS X 10.2 / PowerPC.
#
# A second compiler on the Tiger one's source tree and classic cctools linker,
# with the 10.2.8 SDK as sysroot. The Tiger compiler cannot serve Jaguar: its
# driver passes the 10.4u SDK as -syslibroot whatever --sysroot says, and its
# libstdc++ expects <wchar.h>, which 10.2 lacks. The unwinder and 64-bit
# division come from libgcc.a; without __cxa_atexit on 10.2, static
# destructors go through atexit().
FROM gcc-runtime AS jaguar-gcc
ARG JOBS=6
ENV PATH=/opt/osxcross-ppc/target/bin:$PATH
ENV DISABLE_ANNOYING_LD64_ASSERTION=1
ENV MACOSX_DEPLOYMENT_TARGET=10.2
COPY downloads/MacOSX10.2.8.sdk.tar.xz /archives/MacOSX10.2.8.sdk.tar.xz
RUN echo '8f30a969f8ae2be2ce9c2fae3a649f342a6b4aeceda9021f978af502fadeb13c  /archives/MacOSX10.2.8.sdk.tar.xz' | sha256sum -c - \
    && mkdir -p /opt/jaguar \
    && tar -xJf /archives/MacOSX10.2.8.sdk.tar.xz -C /opt/jaguar
# GCC's Darwin driver always links -lSystemStubs, which 10.2 lacks; a
# placeholder archive with one symbol (the classic linker needs a table of
# contents) satisfies it.
RUN echo 'char __jaguar_SystemStubs_placeholder = 1;' | powerpc-apple-darwin8-gcc -x c -c - -o /tmp/stubs.o \
    && powerpc-apple-darwin8-ar rcs /opt/jaguar/MacOSX10.2.8.sdk/usr/lib/libSystemStubs.a /tmp/stubs.o
# Jaguar's <sys/mman.h> needs <sys/types.h> first; libgcc's mprotect helper
# gets the include.
RUN sed -i 's|^#include <sys/mman.h>|#include <sys/types.h>\n#include <sys/mman.h>|' \
       /work/ppc-gcc-source/libgcc/enable-execute-stack-mprotect.c \
    && grep -q 'sys/types.h' /work/ppc-gcc-source/libgcc/enable-execute-stack-mprotect.c
COPY scripts/build/qt4-macos-jaguar/libgcc-dlfcn.h /work/ppc-gcc-source/libgcc/config/jaguar-dlfcn.h
RUN cd /work/ppc-gcc-source/libgcc/config \
    && sed -i 's|^#include <dlfcn.h>|#include "jaguar-dlfcn.h"|' darwin-crt3.c darwin-crt-tm.c \
    && grep -q 'jaguar-dlfcn.h' darwin-crt3.c && grep -q 'jaguar-dlfcn.h' darwin-crt-tm.c
# With no class or category in a unit, GCC emits a NULL symtab in
# __OBJC,__module_info, and Jaguar's libobjc 218 dereferences it in _objcInit.
# This compiler always emits one, as Apple's did.
RUN f=/work/ppc-gcc-source/gcc/objc/objc-next-runtime-abi-01.c \
    && sed -i '/^  if (imp_count || cat_count)$/{N;s#^  if (imp_count || cat_count)\n    generate_objc_symtab_decl ();#  /* Jaguar: always emit a symtab.  */\n    generate_objc_symtab_decl ();#}' "$f" \
    && grep -q 'Jaguar: always emit a symtab' "$f" \
    && test "$(grep -c '^  if (imp_count || cat_count)$' "$f")" = 2
RUN mkdir -p /work/jaguar-gcc-build && cd /work/jaguar-gcc-build \
    && CXXFLAGS='-O2 -std=gnu++98' /work/ppc-gcc-source/configure \
       --target=powerpc-apple-darwin8 --prefix=/opt/jaguar-gcc \
       --with-sysroot=/opt/jaguar/MacOSX10.2.8.sdk \
       --with-as=/opt/osxcross-ppc/target/bin/powerpc-apple-darwin8-as \
       --with-ld=/opt/osxcross-ppc/target/bin/powerpc-apple-darwin8-ld \
       --with-cpu=750 --enable-languages=c,c++,objc,obj-c++ \
       --enable-checking=release --disable-nls --disable-multilib \
       --disable-libsanitizer --disable-libquadmath --disable-libgomp \
       --disable-libssp --disable-libobjc --disable-libatomic --disable-libstdcxx-pch \
       --disable-shared --enable-static --with-system-zlib \
       --disable-wchar_t --disable-tls --disable-__cxa_atexit \
       --disable-libstdcxx-filesystem-ts \
    && make -j "$JOBS" all-gcc all-target-libgcc \
       CFLAGS_FOR_TARGET='-Os -mmacosx-version-min=10.2' \
    && make install-gcc install-target-libgcc
# Spec changes: libgcc linked statically (10.2 has no libgcc_s), and 64-bit
# long double, the 10.2 ABI (128-bit calls $LDBL128 functions from 10.4).
RUN /opt/jaguar-gcc/bin/powerpc-apple-darwin8-gcc -dumpspecs \
       | sed -e '/^\*libgcc:$/ {n;s/.*/-lgcc/;}' \
             -e '/^\*cc1:$/ {n;s/$/ %{!mlong-double-128:-mlong-double-64}/;}' \
       > /opt/jaguar-gcc/lib/gcc/powerpc-apple-darwin8/5.5.0/specs \
    && grep -q 'mlong-double-64' /opt/jaguar-gcc/lib/gcc/powerpc-apple-darwin8/5.5.0/specs \
    && cp /opt/jaguar-gcc/lib/gcc/powerpc-apple-darwin8/5.5.0/specs /work/jaguar-gcc-build/gcc/specs

FROM ${LLVM_COMPILER_IMAGE} AS compiler
ARG PARALLEL_JOBS=3

RUN --network=none \
    --mount=type=bind,source=downloads/llvm-project-21.1.8.src.tar.xz,target=/src/llvm.tar.xz \
    --mount=type=bind,source=patches/llvm/macos-jaguar,target=/src/patches \
    --mount=type=cache,id=qt4-jaguar-llvm21-compiler,target=/work/jaguar,sharing=locked <<'EOF'
set -eu
echo '4633a23617fa31a3ea51242586ea7fb1da7140e426bd62fc164261fe036aa142  /src/llvm.tar.xz' | sha256sum -c -
# Key the source and CMake cache by the entire ordered patch series.
set -- /src/patches/0*.patch /src/patches/10-*.patch /src/patches/11-*.patch
patch_key=$(sha256sum "$@" | sha256sum | cut -d ' ' -f 1)
work=/work/jaguar/$patch_key
src=$work/source
build=$work/build
if ! test -f "$src/.longreach-patched"; then
    rm -rf "$src"
    mkdir -p "$src"
    tar -xJf /src/llvm.tar.xz -C "$src" --strip-components=1
    cd "$src"
    for patch in "$@"; do
        git apply "$patch"
    done
    touch "$src/.longreach-patched"
fi
cmake -G Ninja -S "$src/llvm" -B "$build" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS_RELEASE='-O1 -DNDEBUG' -DCMAKE_CXX_FLAGS_RELEASE='-O1 -DNDEBUG' \
    -DCMAKE_INSTALL_PREFIX=/opt/jaguar-llvm21 -DLLVM_TARGETS_TO_BUILD=PowerPC -DLLVM_ENABLE_PROJECTS=clang \
    -DLLVM_DISTRIBUTION_COMPONENTS='clang;clang-resource-headers;llvm-ar;llvm-nm;llvm-objdump' \
    -DLLVM_PARALLEL_LINK_JOBS=1 -DLLVM_INCLUDE_TESTS=OFF -DCLANG_INCLUDE_TESTS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_DOCS=OFF \
    -DLLVM_ENABLE_TERMINFO=OFF -DLLVM_ENABLE_LIBEDIT=OFF -DLLVM_ENABLE_LIBXML2=OFF \
    -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF
cmake --build "$build" --target distribution --parallel "$PARALLEL_JOBS"
cmake --build "$build" --target install-distribution --parallel 1
/opt/jaguar-llvm21/bin/clang --version
/opt/jaguar-llvm21/bin/clang --print-targets
EOF

FROM jaguar-gcc AS jaguar-inputs
ENV PATH=/opt/jaguar-gcc/bin:$PATH
COPY scripts/build/qt4-macos-jaguar/check-imports.py /scripts/
# Only the 10.4u libSystem and libobjc stubs; see QMAKE_LFLAGS in qmake.conf.
RUN mkdir -p /opt/jaguar/link-10.4u && cd /opt/jaguar/link-10.4u && \
    for lib in libSystem.B.dylib libSystem.dylib libobjc.A.dylib libobjc.dylib; do \
        ln -s "/opt/osxcross-ppc/target/SDK/MacOSX10.4u.sdk/usr/lib/$lib" "$lib"; \
    done && ls -l
COPY downloads/openssl-1.0.2u.tar.gz /archives/openssl-1.0.2u.tar.gz
COPY scripts/build/qt4-macos-jaguar/build-openssl.sh /scripts/build-openssl.sh
RUN mkdir -p /out && JAGUAR_JOBS="$JOBS" bash /scripts/build-openssl.sh

FROM jaguar-inputs AS runtime
ARG PARALLEL_JOBS=3
COPY --from=compiler /opt/jaguar-llvm21 /opt/jaguar-llvm21
ENV PATH=/opt/jaguar-llvm21/bin:${PATH}
ENTRYPOINT ["/bin/bash", "-c"]
COPY scripts/build/qt4-macos-jaguar/llvm /scripts/jaguar-llvm
COPY --chmod=0755 scripts/build/qt4-macos-jaguar/llvm/jaguar-llvm-cc /usr/local/bin/
RUN --network=none \
    --mount=type=bind,source=downloads/llvm-project-21.1.8.src.tar.xz,target=/src/llvm.tar.xz \
    --mount=type=bind,source=patches/llvm,target=/src/patches \
    ln -s jaguar-llvm-cc /usr/local/bin/jaguar-llvm-cxx && \
    PARALLEL_JOBS="$PARALLEL_JOBS" bash /scripts/jaguar-llvm/build-runtime.sh /src/llvm.tar.xz /src/patches

FROM runtime AS probe
COPY scripts/build/qt4-macos-jaguar/check-imports.py /scripts/
COPY scripts/tests/qt6-llvm-probes/main.cpp /probe/scripts/tests/qt6-llvm-probes/
COPY tests/common/moderncpp_checks.h /probe/tests/common/
RUN --network=none mkdir -p /out && \
    jaguar-llvm-cxx -std=c++23 -O2 -c /probe/scripts/tests/qt6-llvm-probes/main.cpp -o /tmp/probe.o && \
    jaguar-llvm-cxx -mmacosx-version-min=10.2 -mcpu=750 /tmp/probe.o -o /out/cxx23-probe && \
    python3 /scripts/check-imports.py /out/cxx23-probe /out/cxx23-imports.txt

FROM runtime AS sdk
ARG PARALLEL_JOBS=3
COPY scripts/build/qt4-macos-jaguar/build-qt.sh scripts/build/qt4-macos-jaguar/qmake.conf \
     scripts/build/qt4-macos-jaguar/check-imports.py /scripts/
COPY scripts/build/qt4-macos-jaguar/qtcore-probe /scripts/qtcore-probe
COPY scripts/build/qt4-macos-jaguar/qtgui-probe /scripts/qtgui-probe
COPY patches/qt4/all /patches/all
COPY patches/qt4/macos /patches/macos
COPY patches/qt4/macos-tiger-llvm /patches/tiger-llvm
RUN --network=none \
    --mount=type=bind,source=downloads/qt-everywhere-opensource-src-4.8.7.tar.gz,target=/archives/qt-everywhere-opensource-src-4.8.7.tar.gz \
    mkdir -p /out && \
    sed -i -e '/^JAGUAR_GCC =/,/^QMAKE_CC =/c\QMAKE_CC = jaguar-llvm-cc' \
           -e 's|^QMAKE_CXX = .*|QMAKE_CXX = jaguar-llvm-cxx|' \
           -e 's|\$\$JAGUAR_INC ||g' -e 's/-mdynamic-no-pic //g' /scripts/qmake.conf && \
    JAGUAR_LLVM=1 JAGUAR_JOBS="$PARALLEL_JOBS" bash /scripts/build-qt.sh && \
    /opt/qt4-jaguar/bin/qmake -v && \
    find /opt/qt4-jaguar/lib -maxdepth 1 -name 'libQt*.a' -printf '%f\n' | sort > /out/qt-libraries.txt

ENV PATH=/opt/qt4-jaguar/bin:$PATH
LABEL org.openkaryon.longreach-qt.platform=macos-jaguar-ppc \
      org.openkaryon.longreach-qt.openssl="1.0.2u"

FROM ${SDK_IMAGE} AS examples
ARG PARALLEL_JOBS=3
COPY scripts/build/qt4-macos-jaguar/build-suite.sh scripts/build/qt4-macos/write-bundle.py /scripts/
COPY tests /input
RUN --network=none JAGUAR_JOBS="$PARALLEL_JOBS" bash /scripts/build-suite.sh && \
    JAGUAR_JOBS="$PARALLEL_JOBS" bash /scripts/jaguar-llvm/build-strict-selftest.sh
