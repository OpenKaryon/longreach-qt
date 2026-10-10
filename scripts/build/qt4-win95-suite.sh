#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
# The tests/ applications against the installed Windows 95 SDK.
set -euo pipefail
jobs="${1:-6}"
sdk=/usr/local/Qt-4.8
mkdir -p /tmp/suite && cp -R /input/. /tmp/suite/
bash "$(dirname "$0")/qt4-tests.sh" "$sdk" /tmp/suite /out "$jobs" \
    -spec "$sdk/mkspecs/win32-g++" -unix WIN95_CROSS=1
# After the check of the built set, which counts every file in /out.
cp /opt/openssl-1.0.2u/LICENSE /out/OPENSSL-LICENSE.txt
