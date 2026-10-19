# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Tools for run.py's qemu backend: QEMU and a current Ubuntu kernel with its
# e1000 driver. The guest's userland is an old distribution's, but its kernel
# is this one, which emulates the vsyscall page that 64-bit glibc before 2.14
# calls; container hosts without that emulation cannot run such userlands.

# Pinned by digest like the build images (docs/sources.md).
ARG BASE_REGISTRY=ghcr.io/openkaryonlab
FROM ${BASE_REGISTRY}/ubuntu:22.04@sha256:5ec03bb3441e8b0bf3b4f9cd4629a1ae763010dc3035bb8da3ae6cf026486401
# apt from the archive as it was then (scripts/build/apt-snapshot.sh does the
# same for the build images).
ARG APT_SNAPSHOT=20261019T000000Z
RUN apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends ca-certificates && \
    sed -i "s#http://\(archive\|security\).ubuntu.com/ubuntu/#https://snapshot.ubuntu.com/ubuntu/$APT_SNAPSHOT/#" /etc/apt/sources.list && \
    printf 'Acquire::Check-Valid-Until "false";\nAcquire::Retries "5";\n' > /etc/apt/apt.conf.d/99longreach-snapshot && \
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        qemu-system-x86 cpio linux-image-generic && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /opt/qemu && \
    cp "$(ls /boot/vmlinuz-* | sort | tail -1)" /opt/qemu/vmlinuz && \
    cp "$(find /lib/modules -name 'e1000.ko' | head -1)" /opt/qemu/e1000.ko
COPY init boot.sh /opt/qemu/
