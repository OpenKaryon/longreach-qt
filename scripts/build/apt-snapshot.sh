#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Point apt at the distribution's archive as it was at one moment, so that an
# image built later installs the same package versions:
#
#   apt-snapshot                        the date below
#   apt-snapshot <YYYYMMDDTHHMMSSZ>     another date (make passes APT_SNAPSHOT)
#   apt-snapshot none                   the live archive, unpinned
#
# Debian 12 (bookworm) and Ubuntu 22.04 (jammy) still get updates, so they go
# to snapshot.debian.org and snapshot.ubuntu.com. Older releases are frozen
# already and keep their archive. apt checks the archive's signatures either
# way, so plain http does for Debian (its base image has no CA certificates).
# Snapshots keep their Release files' long-past Valid-Until.
set -eu
# Moving this date is a deliberate update: it rebuilds the images that run
# this script.
snapshot=${1:-20261019T000000Z}
# apt-get update only warns about an index it could not fetch and exits 0;
# the install would then take older packages from the indexes it did get.
# Error-Mode makes that an error, after retries with a growing delay. For
# the live archive too.
printf 'Acquire::Retries "10";\nAPT::Update::Error-Mode "any";\n' > /etc/apt/apt.conf.d/99longreach-update
[ "$snapshot" = none ] && { echo "apt-snapshot: the live archive"; exit 0; }
. /etc/os-release
case "${VERSION_CODENAME:-}" in
    bookworm)
        sources=/etc/apt/sources.list.d/debian.sources
        sed -i -e "s#^URIs: http://deb.debian.org/debian-security\$#URIs: http://snapshot.debian.org/archive/debian-security/$snapshot#" \
               -e "s#^URIs: http://deb.debian.org/debian\$#URIs: http://snapshot.debian.org/archive/debian/$snapshot#" "$sources"
        live='^URIs: http://deb.debian.org'
        ;;
    jammy)
        # snapshot.ubuntu.com has the amd64 archive, not ubuntu-ports.
        sources=/etc/apt/sources.list
        sed -i -e "s#http://archive.ubuntu.com/ubuntu/#https://snapshot.ubuntu.com/ubuntu/$snapshot/#" \
               -e "s#http://security.ubuntu.com/ubuntu/#https://snapshot.ubuntu.com/ubuntu/$snapshot/#" "$sources"
        live='^deb .*(archive|security|ports)\.ubuntu\.com'
        ;;
    *)
        echo "apt-snapshot: ${VERSION_CODENAME:-this release} is frozen; its archive is used as it is"
        exit 0
        ;;
esac
if ! grep -q "/$snapshot" "$sources" || grep -qE "$live" "$sources"; then
    echo "apt-snapshot: $sources has sources this script cannot pin (APT_SNAPSHOT=none takes the live archive):" >&2
    grep -E '^(deb|URIs)' "$sources" >&2
    exit 1
fi
printf 'Acquire::Check-Valid-Until "false";\n' > /etc/apt/apt.conf.d/99longreach-snapshot
if [ "$VERSION_CODENAME" = jammy ] && [ ! -s /etc/ssl/certs/ca-certificates.crt ]; then
    # snapshot.ubuntu.com is https only, and the base image has no CA
    # certificates. They come from the snapshot too, fetched once without
    # checking the server: apt still checks the archive's signatures.
    apt-get -o Acquire::https::Verify-Peer=false update -qq
    DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::https::Verify-Peer=false \
        install -y -qq --no-install-recommends ca-certificates > /dev/null
fi
echo "apt-snapshot: $VERSION_CODENAME as of $snapshot"
