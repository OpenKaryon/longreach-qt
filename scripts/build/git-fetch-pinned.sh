#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Check out one commit of a Git project into <dir>, from the first repository
# that has it:
#
#   bash git-fetch-pinned.sh <dir> <commit> <url> [<url>...]
#
# The build names the OpenKaryonLab copy (docs/sources.md); more than one
# URL is tried in order. A branch name works too, for trying another
# osxcross (OSXCROSS_REF=master; the copy's branches are as fresh as the
# last mirror.py repos, and LAB_GIT can name another organisation).
set -euo pipefail
usage='usage: git-fetch-pinned.sh <dir> <commit> <url> [<url>...]'
dir=${1:?$usage}
ref=${2:?$usage}
shift 2
[ $# -gt 0 ] || { echo "$usage" >&2; exit 2; }
# A repository that is gone asks for a login instead of failing.
export GIT_TERMINAL_PROMPT=0
rm -rf "${dir:?}"
git init -q "$dir"
# Three tries per repository, half a minute apart: one failed request should
# not end an image build.
for url in "$@"; do
    for try in 1 2 3; do
        if git -C "$dir" fetch -q --depth 1 "$url" "$ref"; then
            git -C "$dir" checkout -q FETCH_HEAD
            echo "git-fetch-pinned: $(basename "$dir") at $(git -C "$dir" rev-parse HEAD) from $url"
            exit 0
        fi
        echo "git-fetch-pinned: $ref not fetched from $url (try $try of 3)" >&2
        [ "$try" = 3 ] || sleep 30
    done
done
echo "git-fetch-pinned: no repository had $ref" >&2
exit 1
