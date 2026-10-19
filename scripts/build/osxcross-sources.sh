#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Lay out the projects osxcross's build.sh would clone, each at a pinned
# commit, for TP_OSXCROSS_DEV:
#
#   bash osxcross-sources.sh <dir> cctools-port=<commit> xar=<commit> ...
#   bash osxcross-sources.sh <dir> compiler-rt=archive:/path/llvm-project-14.0.6.src.tar.xz
#   TP_OSXCROSS_DEV=<dir> ./build.sh
#
# build.sh then copies <dir>/<project> instead of cloning a branch of the
# upstream repository, which can move or go away. Older osxcross (the 10.4
# SDK branch) copies every project from there, so name all it builds.
# Each commit comes from the OpenKaryonLab copy in LAB_GIT
# (git-fetch-pinned.sh, next to this script). The upstream repositories are
# on GitHub too, so they would be no fallback; mirror.py copies from them.
set -euo pipefail
dir=${1:?usage: osxcross-sources.sh <dir> <project>=<commit>|archive:<file> ...}
shift
lab=${LAB_GIT:-https://github.com/OpenKaryonLab}
here=$(dirname "$0")
mkdir -p "$dir"
for pin in "$@"; do
    project=${pin%%=*}
    ref=${pin#*=}
    rm -rf "${dir:?}/$project"
    case "$ref" in
        archive:*)
            # compiler-rt is built from the LLVM monorepo: the release
            # archive's tree, under the project name build_compiler_rt.sh uses.
            mkdir "$dir/$project"
            tar -xf "${ref#archive:}" -C "$dir/$project" --strip-components=1
            echo "osxcross-sources: $project from $(basename "${ref#archive:}")"
            ;;
        *)
            bash "$here/git-fetch-pinned.sh" "$dir/$project" "$ref" "$lab/$project.git"
            ;;
    esac
done
