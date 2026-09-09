#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
# Print configure arguments which enforce the requested SDK license profile.
set -eu
generation=${1:?Qt generation is required}
profile=${2:?license profile is required}
case "$profile" in
    gpl-enabled|commercial-qt) exit 0 ;;
    lgpl-friendly) ;;
    *) echo "unknown license profile: $profile" >&2; exit 2 ;;
esac
case "$generation" in
    qt5)
        for module in qtcharts qtdatavis3d qtquick3d qtnetworkauth qtvirtualkeyboard; do
            printf '%s ' "-skip $module"
        done
        ;;
    qt6)
        for module in qtcharts qtdatavis3d qtgraphs qtquick3d qtquick3dphysics \
                      qtnetworkauth qtvirtualkeyboard qtmqtt qtcoap qthttpserver; do
            printf '%s ' "-skip $module"
        done
        ;;
    *) echo "unknown Qt generation: $generation" >&2; exit 2 ;;
esac
