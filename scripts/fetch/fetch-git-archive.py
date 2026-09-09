#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Fetch a pinned Git tree (including submodules) into a deterministic tarball."""

import argparse
import os
import pathlib
import shutil
import stat
import subprocess
import tarfile
import tempfile


def run(*args, cwd=None):
    subprocess.run(args, cwd=cwd, check=True)


def remove_readonly(function, path, _error):
    os.chmod(path, stat.S_IWRITE)
    function(path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("url")
    parser.add_argument("commit")
    parser.add_argument("output")
    parser.add_argument("root")
    args = parser.parse_args()

    output = pathlib.Path(args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="qt-addon-") as temporary:
        checkout = pathlib.Path(temporary) / args.root
        run("git", "clone", "--filter=blob:none", "--no-checkout", args.url, str(checkout))
        run("git", "checkout", "--detach", args.commit, cwd=checkout)
        run("git", "submodule", "update", "--init", "--recursive", cwd=checkout)
        shutil.rmtree(checkout / ".git", onerror=remove_readonly)
        for git_marker in checkout.rglob(".git"):
            if git_marker.is_dir():
                shutil.rmtree(git_marker, onerror=remove_readonly)
            else:
                git_marker.unlink()

        temporary_output = output.with_suffix(output.suffix + ".part")
        with tarfile.open(temporary_output, "w:xz") as archive:
            def normalise(info):
                info.uid = info.gid = 0
                info.uname = info.gname = "root"
                info.mtime = 0
                return info
            archive.add(checkout, arcname=args.root, filter=normalise)
        os.replace(temporary_output, output)


if __name__ == "__main__":
    main()
