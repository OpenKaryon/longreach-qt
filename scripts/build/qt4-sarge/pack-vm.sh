#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail
root=/work/sysroot
mkdir -p /work/kernel
dpkg-deb -x /kernels/kernel-image-2.6.8-4-386_2.6.8-17sarge1_i386.deb /work/kernel
dpkg-deb -x /kernels/net-tools_1.60-10_i386.deb "$root"
for package in /kernels/mount_*.deb /kernels/libblkid1_*.deb /kernels/libuuid1_*.deb; do
    dpkg-deb -x "$package" "$root"
done
dpkg-deb -x /kernels/module-init-tools_3.2-pre1-2_i386.deb "$root"
mkdir -p "$root/lib/modules/2.6.8-4-386/kernel/net/unix" "$root/lib/modules/2.6.8-4-386/kernel/net/ipv6"
cp /work/kernel/lib/modules/2.6.8-4-386/kernel/net/unix/unix.ko "$root/lib/modules/2.6.8-4-386/kernel/net/unix/"
cp /work/kernel/lib/modules/2.6.8-4-386/kernel/net/ipv6/ipv6.ko "$root/lib/modules/2.6.8-4-386/kernel/net/ipv6/"
python /scripts/relativize-sysroot.py
cp /work/kernel/boot/vmlinuz-2.6.8-4-386 /out/
cp /work/kernel/boot/config-2.6.8-4-386 /out/
for item in 'console 5 1' 'ttyS0 4 64'; do
    read -r name major minor <<< "$item"
    [ -e "$root/dev/$name" ] || mknod -m 600 "$root/dev/$name" c "$major" "$minor"
done
mkdir -p "$root/proc" "$root/sys"
cat > "$root/init" <<'EOF'
#!/bin/bash
export LD_LIBRARY_PATH=/lib/tls:/lib:/usr/lib:/usr/X11R6/lib
export PATH=/bin:/usr/bin:/sbin:/usr/sbin:/usr/X11R6/bin
export HOME=/root LANG=C DISPLAY=:91
exec </dev/console >/dev/console 2>&1
mkdir -p /proc /sys /tmp /root /var/cache/fontconfig
chmod 1777 /tmp
mount -t proc proc /proc
mount -t sysfs sysfs /sys
insmod /lib/modules/2.6.8-4-386/kernel/net/unix/unix.ko
insmod /lib/modules/2.6.8-4-386/kernel/net/ipv6/ipv6.ko
/sbin/ifconfig lo 127.0.0.1 up
echo SARGE_KERNEL_BEGIN
uname -a
cat /proc/meminfo | head -3
cd /opt/apps
Xvfb :91 -screen 0 1280x1024x24 -nolisten tcp > xvfb-vm.log 2>&1 &
xpid=$!
sleep 3
echo SARGE_SUITE_BEGIN
./smoke-runner --timeout=90
result=$?
echo SARGE_SUITE_RESULT=$result
echo SARGE_REPORT_BEGIN
cat smoke-report.txt
echo SARGE_REPORT_END
kill "$xpid"
sync
echo SARGE_VM_DONE
while true; do sleep 60; done
EOF
chmod +x "$root/init"
# mount is in util-linux on Sarge. The host binary must never enter the guest.
test -x "$root/bin/mount" || { echo 'missing Sarge mount binary'; exit 1; }
python /scripts/pack-initramfs.py
