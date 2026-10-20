# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Tools for run.py's qemu backend: QEMU and a current Ubuntu kernel with its
# e1000 driver. The guest's userland is an old distribution's, but its kernel
# is this one, which emulates the vsyscall page that 64-bit glibc before 2.14
# calls; container hosts without that emulation cannot run such userlands.

# Pinned by digest like the build images (docs/sources.md). amd64 on any
# host: the guest kernel is x86_64, and snapshot.ubuntu.com has no ports.
ARG BASE_REGISTRY=ghcr.io/openkaryonlab
FROM --platform=linux/amd64 ${BASE_REGISTRY}/ubuntu:22.04@sha256:5ec03bb3441e8b0bf3b4f9cd4629a1ae763010dc3035bb8da3ae6cf026486401
# apt from the archive as it was at the build images' snapshot date (run.py
# passes this script in, and APT_SNAPSHOT when it is set).
ARG APT_SNAPSHOT
COPY --from=build-scripts apt-snapshot.sh /usr/local/bin/apt-snapshot
RUN sh /usr/local/bin/apt-snapshot "$APT_SNAPSHOT" && \
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        qemu-system-x86 cpio linux-image-generic && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /opt/qemu && \
    cp "$(ls /boot/vmlinuz-* | sort | tail -1)" /opt/qemu/vmlinuz && \
    cp "$(find /lib/modules -name 'e1000.ko' | head -1)" /opt/qemu/e1000.ko
COPY init boot.sh /opt/qemu/
