#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
# Build the tests/ applications against an installed Qt 4 SDK with qmake.
#
#   qt4-tests.sh <qt prefix> <tests dir> <output dir> [jobs] [qmake arguments...]
#
# One application per directory, the names listed in tests/expected-apps.txt;
# each directory holds <app>.pro. Every application is built, then the set of
# binaries is compared with the list, so a missing or extra one fails the
# build. Extra qmake arguments (a -spec, WIN95_CROSS=1) are passed to each.
set -euo pipefail
prefix=$1 tests=$2 out=$3 jobs=${4:-$(nproc)}
shift 4 2>/dev/null || shift $#
qmake=("$prefix/bin/qmake" "$@")
work=$(mktemp -d)
mkdir -p "$out"
apps=$(grep -v '^#' "$tests/expected-apps.txt" | grep .)
for app in $apps; do
    mkdir -p "$work/$app"
    (
        cd "$work/$app"
        extra=()
        # On Windows 95 the widgets gallery links the static accessibility
        # plugin and checks the bridge (see widgets-gallery.pro).
        if [ "$app" = widgets-gallery ] && [[ " $* " == *" WIN95_CROSS=1 "* ]]; then
            extra=(WIN95_ACCESSIBILITY=1)
        fi
        "${qmake[@]}" "$tests/$app/$app.pro" ${extra[@]+"${extra[@]}"}
        make -j "$jobs"
    )
    found=$(find "$work/$app" -maxdepth 2 -type f \( -name "$app" -o -name "$app.exe" \) | head -1)
    [ -n "$found" ] || { echo "qt4-tests.sh: $app produced no binary" >&2; exit 1; }
    cp "$found" "$out/"
done
built=$(cd "$out" && ls | sed 's/\.exe$//' | sort)
if [ "$built" != "$(echo "$apps" | sort)" ]; then
    echo "qt4-tests.sh: built set differs from tests/expected-apps.txt:" >&2
    diff <(echo "$apps" | sort) <(echo "$built") >&2 || true
    exit 1
fi
echo "qt4-tests.sh: $(echo "$apps" | wc -w) applications in $out"
