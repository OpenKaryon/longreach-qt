#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Build and run tests/ headless against the host image's Qt 6 (make
# qt6-host-smoke): quick, as the host image exists anyway. It has no Qt3D or
# DataVisualization, so gl-heavy-gallery is reported as SKIP; qt6-linux-amd64
# is the full run.
set -e

SRC=${SMOKE_TESTS_SRC:-/src}
QT_PREFIX=${SMOKE_QT_PREFIX:-/opt/qt6-host}
JOBS=${PARALLEL_JOBS:-$(nproc)}

export DEBIAN_FRONTEND=noninteractive

# The image is a stripped final stage with no toolchain: it ships Qt and
# nothing else. Everything installed here lives in the container's writable
# layer and goes away with it.
echo "installing a toolchain into the throwaway container..."
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
    g++ cmake ninja-build \
    libgl1-mesa-dev libglx-dev libxkbcommon-dev libfontconfig1 libfreetype6 \
    > /dev/null

cp -r "$SRC" /tmp/qt-smoke-tests
mkdir -p /tmp/qt-smoke-build
cd /tmp/qt-smoke-build

echo "configuring..."
cmake -G Ninja /tmp/qt-smoke-tests \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$QT_PREFIX" \
    > /tmp/configure.log 2>&1 || { tail -40 /tmp/configure.log; exit 1; }
grep -E "qt-smoke:" /tmp/configure.log || true

echo "building with $JOBS jobs..."
cmake --build . -j "$JOBS" -- -k 0 > /tmp/build.log 2>&1 || true

# Not anchored to /tmp/qt-smoke-tests: a #error inside a Qt header is
# reported against an SDK path (as for QtCharts with QtGraphs).
errors=$(grep -E ": (error|fatal error):" /tmp/build.log \
         | sed 's#/tmp/qt-smoke-tests/##' | sort -u)
if [ -n "$errors" ]; then
    echo "=== build errors ==="
    echo "$errors" | head -40
fi

mkdir -p /tmp/qt-smoke-bin
find . -maxdepth 2 -type f -perm -u+x ! -name "*.o" ! -name "*.so*" \
    -exec cp {} /tmp/qt-smoke-bin/ \;
cd /tmp/qt-smoke-bin

# No display, no compositor, no GPU: the offscreen platform plugin is what
# makes the GUI apps runnable in a container at all.
export QT_QPA_PLATFORM=offscreen
echo
./smoke-runner
