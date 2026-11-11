#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
# Run inside the Ubuntu 14.04 arm64 container, with /suite and /src read-only.
set -euo pipefail

. /etc/os-release
test "$ID" = ubuntu
test "$VERSION_ID" = 14.04
test "$(dpkg --print-architecture)" = arm64
{
    cat /etc/os-release
    ldd --version
} > /out/system.log

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
    libgl1-mesa-glx libegl1-mesa libx11-6 libxext6 libxrender1 libsm6 libice6 libfontconfig1 \
    libfreetype6 libx11-xcb1 libxcb1 libxcb-glx0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 \
    libxcb-randr0 libxcb-render-util0 libxcb-render0 libxcb-shape0 libxcb-shm0 libxcb-sync1 \
    libxcb-xfixes0 libxcb-xkb1 fonts-dejavu-core xvfb xauth ca-certificates
[ -s /etc/machine-id ] || tr -d - < /proc/sys/kernel/random/uuid > /etc/machine-id

apps=()
while read -r app; do
    case "$app" in ''|\#*) continue ;; esac
    apps+=("$app")
done < /src/tests/expected-apps.txt
work=$(mktemp -d)
cd "$work"
for app in "${apps[@]}"; do
    install -m 755 "/suite/$app" "$app"
done
sha256sum "${apps[@]}" > /out/SHA256SUMS

export DISPLAY=:99
Xvfb "$DISPLAY" -screen 0 1280x1024x24 -nolisten tcp > /out/xvfb.log 2>&1 &
xvfb=$!
trap 'kill "$xvfb" 2>/dev/null || true; rm -rf -- "$work"' EXIT
for attempt in $(seq 30); do
    if [ -S /tmp/.X11-unix/X99 ]; then break; fi
    sleep 1
done
test -S /tmp/.X11-unix/X99

status=0
timeout 180 ./qt-selftest --modern-cpp > /out/qt-selftest-modern-cpp.log 2>&1 || status=1
for app in "${apps[@]}"; do
    case "$app" in qt-selftest|smoke-runner) continue ;; esac
    log="/out/$app-runner.log"
    timeout 200 ./smoke-runner --only="$app" > "$log" 2>&1 || status=1
    grep -E "^PASS[[:space:]]+$app[[:space:]]" "$log" || status=1
    if [ -f "smoke-$app.log" ]; then
        cp "smoke-$app.log" /out/
    fi
done
exit "$status"
