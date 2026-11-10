#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
set -euo pipefail
mkdir -p /opt/longreach-host-libs
ldd /opt/qt6-linux-amd64-llvm/bin/qsb > /opt/longreach-host-libs/source-dependencies.txt
while read -r name arrow path rest; do
    case "$name" in
        libGL*|libEGL*|libOpenGL*|libglapi*|libxcb-glx*|libxcb-dri*|libxcb-present*|libXdamage*|libXext*|libXxf86vm*|libxshmfence*|libdrm*|libgbm*)
            test "$arrow" = '=>'
            test -f "$path"
            cp -L "$path" "/opt/longreach-host-libs/$name"
            ;;
    esac
done < /opt/longreach-host-libs/source-dependencies.txt
