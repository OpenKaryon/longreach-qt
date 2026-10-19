#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Copy the tests/ binaries built in an image to /out (make qt5-extract-tests).
set -u

src=${1:-/opt/qt-smoke-bin}

if [ ! -d "$src" ]; then
    echo "no $src in this image: the tests/ suite was not built here." >&2
    echo "only the images whose final stage runs scripts/build/tests.sh have it." >&2
    exit 1
fi

n=0
failed=0
while IFS= read -r f; do
    if cp "$f" "/out/$(basename "$f")"; then
        chmod 755 "/out/$(basename "$f")" 2>/dev/null || true
        n=$((n + 1))
    else
        failed=$((failed + 1))
    fi
done < <(find "$src" -maxdepth 1 -type f 2>/dev/null)

echo "extracted $n test binaries -> /out"
[ "$n" -gt 0 ] || { echo "nothing extracted - $src is empty?" >&2; exit 1; }
# A partial copy would be packaged as if it were the whole suite.
[ "$failed" -eq 0 ] || { echo "$failed binaries could not be copied" >&2; exit 1; }
