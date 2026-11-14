#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail
root=/work/sysroot
arch=${SARGE_ARCH:-i386}
case "$arch" in
    i386) kernel=2.6.8-4-386 ;;
    amd64) kernel=2.6.8-12-amd64-generic ;;
    *) echo "Unsupported Sarge architecture: $arch" >&2; exit 2 ;;
esac
mkdir -p /work/kernel "$root/dev"
if [ "${SARGE_LLVM_SUITE:-0}" = 1 ]; then
    mkdir -p "$root/opt/apps"
    install -m 755 /out/bin/* "$root/opt/apps/"
    for directory in "$root"/usr/X11R6/lib/X11/fonts/*; do
        [ -d "$directory" ] || continue
        mkfontdir "$directory"
        aliases="$root/etc/X11/fonts/$(basename "$directory")"
        if compgen -G "$aliases/*.alias" > /dev/null; then
            cat "$aliases"/*.alias > "$directory/fonts.alias"
        fi
    done
fi
if [ "${SARGE_LLVM_PROBE:-0}" = 1 ]; then
    install -Dm755 /out/bin/cxx23-probe "$root/opt/apps/cxx23-probe"
    touch "$root/opt/apps/.llvm-probe"
fi
dpkg-deb -x /kernels/kernel-image-"$kernel"_*_"$arch".deb /work/kernel
dpkg-deb -x /kernels/net-tools_1.60-10_"$arch".deb "$root"
for package in /kernels/mount_*.deb /kernels/libblkid1_*.deb /kernels/libuuid1_*.deb; do
    dpkg-deb -x "$package" "$root"
done
dpkg-deb -x /kernels/module-init-tools_3.2-pre1-2_"$arch".deb "$root"
mkdir -p "${root}/lib/modules/${kernel}/kernel/net/unix" "${root}/lib/modules/${kernel}/kernel/net/ipv6"
cp /work/kernel/lib/modules/${kernel}/kernel/net/unix/unix.ko "${root}/lib/modules/${kernel}/kernel/net/unix/"
cp /work/kernel/lib/modules/${kernel}/kernel/net/ipv6/ipv6.ko "${root}/lib/modules/${kernel}/kernel/net/ipv6/"
if [ "${SARGE_LLVM_SUITE:-0}" = 1 ]; then
    printf '%s\n' /lib/modules/${kernel}/kernel/net/{unix/unix,ipv6/ipv6}.ko: \
        > "$root/lib/modules/$kernel/modules.dep"
fi
python /scripts/relativize-sysroot.py
cp /work/kernel/boot/vmlinuz-"$kernel" /out/
cp /work/kernel/boot/config-"$kernel" /out/
for item in 'console 5 1 600' 'ttyS0 4 64 600' 'null 1 3 666' 'zero 1 5 666' 'random 1 8 666' 'urandom 1 9 666'; do
    read -r name major minor mode <<< "$item"
    [ -e "$root/dev/$name" ] || mknod -m "$mode" "$root/dev/$name" c "$major" "$minor"
done
mkdir -p "$root/proc" "$root/sys"
if [ "${SARGE_LLVM_SUITE:-0}" = 1 ]; then
    touch "$root/opt/apps/.llvm-suite"
fi
cat > "$root/init" <<'EOF'
#!/bin/bash
export LD_LIBRARY_PATH=/lib/tls:/lib:/usr/lib:/usr/X11R6/lib
export PATH=/bin:/usr/bin:/sbin:/usr/sbin:/usr/X11R6/bin
export HOME=/root LANG=C DISPLAY=:91
exec </dev/console >/dev/console 2>&1
mkdir -p /proc /sys /tmp /root /var/cache/fontconfig
chmod 1777 /tmp
mount -n -t proc proc /proc
mount -n -t sysfs sysfs /sys
if [ -f /opt/apps/.llvm-suite ]; then
    echo /bin/false > /proc/sys/kernel/modprobe
fi
insmod /lib/modules/"$(uname -r)"/kernel/net/unix/unix.ko
insmod /lib/modules/"$(uname -r)"/kernel/net/ipv6/ipv6.ko
/sbin/ifconfig lo 127.0.0.1 up
echo SARGE_KERNEL_BEGIN
uname -a
cat /proc/meminfo | head -3
cd /opt/apps
if [ -f .llvm-probe ]; then
    echo SARGE_MODERN_BEGIN
    ./cxx23-probe
    modern=$?
    echo SARGE_MODERN_END
    echo SARGE_MODERN_RESULT=$modern
    sync
    echo SARGE_VM_DONE
    while true; do sleep 60; done
fi
Xvfb :91 -screen 0 1280x1024x24 -nolisten tcp > xvfb-vm.log 2>&1 &
xpid=$!
sleep 3
if ! kill -0 "$xpid" 2>/dev/null; then
    cat xvfb-vm.log
    echo SARGE_SUITE_RESULT=1
    echo SARGE_VM_DONE
    while true; do sleep 60; done
fi
echo SARGE_SUITE_BEGIN
./smoke-runner --timeout=90
result=$?
echo SARGE_SUITE_RESULT=$result
echo SARGE_REPORT_BEGIN
cat smoke-report.txt
echo SARGE_REPORT_END
if [ -f .llvm-suite ]; then
    echo SARGE_MODERN_BEGIN
    ./qt-selftest-cxx23 --modern-cpp
    modern=$?
    echo SARGE_MODERN_END
    echo SARGE_MODERN_RESULT=$modern
fi
kill "$xpid"
sync
echo SARGE_VM_DONE
while true; do sleep 60; done
EOF
chmod +x "$root/init"
# mount is in util-linux on Sarge. The host binary must never enter the guest.
test -x "$root/bin/mount" || { echo 'missing Sarge mount binary'; exit 1; }
python /scripts/pack-initramfs.py
