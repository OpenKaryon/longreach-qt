# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Tools for run.py's qemu backend: QEMU and a current Ubuntu kernel with its
# e1000 driver. The guest's userland is an old distribution's, but its kernel
# is this one, which emulates the vsyscall page that 64-bit glibc before 2.14
# calls; container hosts without that emulation cannot run such userlands.
FROM ubuntu:22.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        qemu-system-x86 cpio linux-image-generic && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /opt/qemu && \
    cp "$(ls /boot/vmlinuz-* | sort | tail -1)" /opt/qemu/vmlinuz && \
    cp "$(find /lib/modules -name 'e1000.ko' | head -1)" /opt/qemu/e1000.ko
COPY init boot.sh /opt/qemu/
