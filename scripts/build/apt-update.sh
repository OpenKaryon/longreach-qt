#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# apt-get update for the Ubuntu 14.04-18.04 stages: it fails when an index
# could not be fetched. apt 1.1 to 1.6 report that as a warning and exit 0,
# and the install then takes older packages from the indexes it did get. (The
# Debian 12 and Ubuntu 22.04 stages get the same from apt-snapshot.sh, with
# apt's own APT::Update::Error-Mode.) Up to five tries, half a minute apart.
set -u
log=/tmp/apt-update.log
try=1
while :; do
    if apt-get -o Acquire::Retries=3 update "$@" > "$log" 2>&1 &&
        ! grep -qE '^(Err|[WE]: Failed to fetch|[WE]: Some index files failed|[WE]: GPG error|E: )' "$log"; then
        cat "$log"
        exit 0
    fi
    cat "$log"
    echo "apt-update: an index could not be fetched (try $try of 5)" >&2
    [ "$try" -lt 5 ] || exit 1
    try=$((try + 1))
    sleep 30
done
