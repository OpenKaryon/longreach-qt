#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Builds longreach/ubuntu:10.04-i386, the Ubuntu 10.04 Lucid i386 userland
# that `run.py --host docker:ubuntu-10.04-i386` runs the i386 suites in.
# Docker Hub's ubuntu:10.04 is an image format containerd no longer reads, so
# it is made with debootstrap from old-releases.ubuntu.com, checked against
# Ubuntu's archive key. 32-bit glibc 2.11 needs no vsyscall page, so unlike the
# 64-bit Lucid it runs in an ordinary container.
#
#   bash scripts/run/lucid-i386-image.sh [WORK_DIR]
#
# debootstrap's first stage runs in an Ubuntu 16.04 container (which has the
# lucid script and the 2004 archive key); the second stage runs in a container
# of the result itself, with mount stubbed, since /proc is already mounted
# there and a container may not mount it.
set -eu
work=${1:-build/lucid-i386-image}
mkdir -p "$work"
work=$(cd "$work" && pwd)
# docker.exe takes Windows paths under Git Bash.
host_dir=$work
if command -v cygpath > /dev/null; then host_dir=$(cygpath -w "$work"); fi
export MSYS_NO_PATHCONV=1

docker run --rm -v "$host_dir:/out" ubuntu:16.04 bash -c '
    set -e
    apt-get update -qq > /dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq debootstrap ubuntu-keyring > /dev/null
    debootstrap --arch=i386 --variant=minbase --include=gpgv,ubuntu-keyring --foreign \
        --keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg \
        lucid /rootfs http://old-releases.ubuntu.com/ubuntu > /out/stage1.log
    tar -C /rootfs -cf /out/stage1.tar .'
docker import --platform linux/386 "$host_dir/stage1.tar" longreach/ubuntu:10.04-i386-stage1

docker rm -f longreach-lucid-stage2 > /dev/null 2>&1 || true
docker run --platform linux/386 --name longreach-lucid-stage2 --entrypoint /bin/sh \
    longreach/ubuntu:10.04-i386-stage1 -c '
    mv /bin/mount /bin/mount.real
    printf "#!/bin/sh\nexit 0\n" > /bin/mount
    chmod +x /bin/mount
    /debootstrap/debootstrap --second-stage > /tmp/stage2.log 2>&1; rc=$?
    [ -e /bin/mount.real ] && mv -f /bin/mount.real /bin/mount
    tail -3 /tmp/stage2.log
    [ $rc = 0 ] || exit $rc
    for pocket in lucid lucid-updates lucid-security; do
        echo "deb http://old-releases.ubuntu.com/ubuntu $pocket main universe"
    done > /etc/apt/sources.list'
# Exported and imported again rather than committed, which would keep the
# entrypoint the second stage ran with.
docker export longreach-lucid-stage2 -o "$host_dir/lucid-i386.tar"
docker import --platform linux/386 --change 'CMD ["/bin/bash"]' "$host_dir/lucid-i386.tar" longreach/ubuntu:10.04-i386
docker rm longreach-lucid-stage2 > /dev/null
docker rmi longreach/ubuntu:10.04-i386-stage1 > /dev/null
rm "$work/stage1.tar" "$work/lucid-i386.tar"
docker run --rm --platform linux/386 longreach/ubuntu:10.04-i386 sh -c 'cat /etc/lsb-release; ldd --version | head -1'
