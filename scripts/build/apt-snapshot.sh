#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Point apt at the distribution's archive as it was at one moment, so that an
# image built later installs the same package versions:
#
#   apt-snapshot <YYYYMMDDTHHMMSSZ>     (make passes APT_SNAPSHOT)
#   apt-snapshot none                   the live archive, unpinned
#
# Debian 12 (bookworm) and Ubuntu 22.04 (jammy) still get updates, so they go
# to snapshot.debian.org and snapshot.ubuntu.com. Older releases are frozen
# already and keep their archive. apt checks the archive's signatures either
# way, so plain http does for Debian (its base image has no CA certificates).
# Snapshots keep their Release files' long-past Valid-Until.
set -eu
snapshot=${1:?usage: apt-snapshot <YYYYMMDDTHHMMSSZ>|none}
[ "$snapshot" = none ] && { echo "apt-snapshot: the live archive"; exit 0; }
. /etc/os-release
case "${VERSION_CODENAME:-}" in
    bookworm)
        sources=/etc/apt/sources.list.d/debian.sources
        sed -i -e "s#^URIs: http://deb.debian.org/debian-security\$#URIs: http://snapshot.debian.org/archive/debian-security/$snapshot#" \
               -e "s#^URIs: http://deb.debian.org/debian\$#URIs: http://snapshot.debian.org/archive/debian/$snapshot#" "$sources"
        grep -q "snapshot.debian.org/archive/debian/$snapshot" "$sources"
        ! grep -q '^URIs: http://deb.debian.org' "$sources"
        ;;
    jammy)
        # snapshot.ubuntu.com answers http with a redirect to https, which apt
        # needs CA certificates for: those come from the live archive first.
        if [ ! -s /etc/ssl/certs/ca-certificates.crt ]; then
            apt-get update -qq
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends ca-certificates > /dev/null
        fi
        sources=/etc/apt/sources.list
        sed -i -e "s#http://archive.ubuntu.com/ubuntu/#https://snapshot.ubuntu.com/ubuntu/$snapshot/#" \
               -e "s#http://security.ubuntu.com/ubuntu/#https://snapshot.ubuntu.com/ubuntu/$snapshot/#" "$sources"
        grep -q "snapshot.ubuntu.com/ubuntu/$snapshot" "$sources"
        ! grep -qE '^deb http://(archive|security).ubuntu.com' "$sources"
        ;;
    *)
        echo "apt-snapshot: ${VERSION_CODENAME:-this release} is frozen; its archive is used as it is"
        exit 0
        ;;
esac
printf 'Acquire::Check-Valid-Until "false";\nAcquire::Retries "5";\n' > /etc/apt/apt.conf.d/99longreach-snapshot
echo "apt-snapshot: $VERSION_CODENAME as of $snapshot"
