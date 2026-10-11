#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Inside the qemu tools image: the guest's root file system arrives as a tar
# on stdin (docker export), /out holds suite.tar.gz, setup.sh and
# runner-args. Builds the initramfs, boots it, and unpacks the logs the guest
# prints into /out.
set -eu
root=/tmp/root
mkdir -p "$root"
tar -xf - -C "$root" 2>/dev/null || true
cp /out/suite.tar.gz /out/setup.sh /out/runner-args "$root/"
cp /opt/qemu/e1000.ko "$root/e1000.ko"
sed 's/\r$//' /opt/qemu/init > "$root/init"
sed -i 's/\r$//' "$root/setup.sh"
chmod 755 "$root/init"
(cd "$root" && find . | cpio -o -H newc --quiet | gzip -1) > /tmp/initrd.gz
rm -rf "$root"
timeout "${QEMU_TIMEOUT:-5400}" qemu-system-x86_64 -accel tcg,thread=multi -smp 4 -m 3072 \
    -kernel /opt/qemu/vmlinuz -initrd /tmp/initrd.gz \
    -append "console=ttyS0 rdinit=/init panic=-1 quiet" \
    -nic user,model=e1000 -nographic -no-reboot > /out/console.log 2>&1 || true
tr -d '\r' < /out/console.log | sed -n '/^=== BEGIN RESULTS/,/^=== END RESULTS/p' > /tmp/results.txt
# base64, or od's hex where the guest has no base64.
if head -1 /tmp/results.txt | grep -q ' od$'; then
    sed '1d;$d' /tmp/results.txt | perl -ne 's/\s+//g; print pack("H*", $_)' | tar -xz -C /out
else
    sed '1d;$d' /tmp/results.txt | base64 -d | tar -xz -C /out
fi
