#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail
root=/work/sysroot
mkdir -p "$root/opt/apps" "$root/dev" "$root/proc" "$root/tmp" "$root/root" "$root/var/cache/fontconfig"
chmod 1777 "$root/tmp"
mount -t proc proc "$root/proc"
trap 'umount "$root/proc"' EXIT
cp /out/bin/* "$root/opt/apps/"
for item in 'null 3' 'zero 5' 'random 8' 'urandom 9'; do
    read -r name minor <<< "$item"
    [ -e "$root/dev/$name" ] || mknod -m 666 "$root/dev/$name" c 1 "$minor"
done
for directory in "$root"/usr/X11R6/lib/X11/fonts/*; do
    [ -d "$directory" ] || continue
    mkfontdir "$directory"
    aliases="$root/etc/X11/fonts/$(basename "$directory")"
    if compgen -G "$aliases/*.alias" > /dev/null; then
        cat "$aliases"/*.alias > "$directory/fonts.alias"
    fi
done
# No host libc, X11 or font libraries enter this chroot. Only the kernel is
# shared with Docker; a separate old-kernel VM check is still necessary.
cat > "$root/opt/apps/run.sh" <<'EOF'
#!/bin/bash
export LD_LIBRARY_PATH=/lib/tls:/lib:/usr/lib:/usr/X11R6/lib
export HOME=/root DISPLAY=:91 LANG=C
export PATH=/bin:/usr/bin:/usr/X11R6/bin
cd /opt/apps
/usr/X11R6/bin/Xvfb :91 -screen 0 1280x1024x24 -nolisten tcp > xvfb.log 2>&1 &
xpid=$!
trap 'kill "$xpid" 2>/dev/null' EXIT
sleep 2
kill -0 "$xpid" || { cat xvfb.log; exit 1; }
./smoke-runner --timeout=60 > smoke-console.txt 2>&1
result=$?
cat smoke-console.txt
exit "$result"
EOF
result=0
timeout 600 chroot "$root" /bin/bash /opt/apps/run.sh || result=$?
mkdir -p /out/runtime
find "$root/opt/apps" -maxdepth 1 -type f \( -name '*.txt' -o -name '*.log' -o -name '*.json' -o -name '*.png' \) -exec cp -t /out/runtime/ {} +
exit "$result"
