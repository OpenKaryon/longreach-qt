# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
# Shared Android host tools; build context is the repository root.
FROM ghcr.io/openkaryonlab/ubuntu:22.04@sha256:5ec03bb3441e8b0bf3b4f9cd4629a1ae763010dc3035bb8da3ae6cf026486401 AS base
ARG APT_SNAPSHOT
COPY scripts/build/apt-snapshot.sh /usr/local/bin/apt-snapshot
RUN sh /usr/local/bin/apt-snapshot "$APT_SNAPSHOT" \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates cmake g++ make ninja-build patch perl python3 xz-utils \
    && rm -rf /var/lib/apt/lists/*

FROM base AS compiler
ARG PARALLEL_JOBS=2
ENV LLVM_ROOT=/opt/llvm-21
COPY scripts/build/qt6-llvm-probes/build-compiler.sh /tmp/build-compiler.sh
RUN --network=none \
    --mount=type=bind,source=downloads/llvm-project-21.1.8.src.tar.xz,target=/tmp/llvm.tar.xz \
    --mount=type=cache,id=android-llvm21-compiler,target=/work \
    LLVM_TARGETS='X86;ARM;AArch64' PARALLEL_JOBS="${PARALLEL_JOBS}" \
    bash /tmp/build-compiler.sh /tmp/llvm.tar.xz

FROM base AS tools
COPY --from=compiler /opt/llvm-21 /opt/llvm-21
RUN --network=none set -e; \
    for tool in clang clang++ ld.lld lld llvm-ar llvm-ranlib llvm-nm llvm-objcopy \
            llvm-objdump llvm-readobj llvm-readelf llvm-strip; do \
        test -x "/opt/llvm-21/bin/$tool"; \
        ln -s "/opt/llvm-21/bin/$tool" "/usr/bin/$tool-21"; \
    done; \
    clang-21 --version | grep -E 'clang version 21\.1\.8([[:space:]]|$)'; \
    for target in arm aarch64 x86-64; do \
        clang-21 --print-targets | grep -E "^[[:space:]]+$target[[:space:]]"; \
    done
LABEL org.openkaryon.longreach-qt.role="android-llvm-tools" \
      org.openkaryon.longreach-qt.llvm="21.1.8"
