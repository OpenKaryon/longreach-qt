#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

"""Apply the full patch stack while preserving unchanged source timestamps."""

import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

ARCHIVE_SHA256 = "c0537548bb3871cbb3cac85fb55813430d45ac4d5d4daa64bdf41f3c2ae65ff9"


def safe_path(root, relative):
    path = PurePosixPath(relative)
    if path.is_absolute() or ".." in path.parts or not path.parts:
        raise ValueError(f"Invalid patch path: {relative}")
    destination = root.joinpath(*path.parts)
    if not destination.resolve().is_relative_to(root.resolve()):
        raise ValueError(f"Patch path leaves source tree: {relative}")
    return destination


def main():
    repo, source, archive = map(Path, sys.argv[1:])
    source = source.resolve()
    if source == Path("/work") or not source.is_relative_to(Path("/work")):
        raise ValueError("Only generated Qt source trees under /work are supported")
    if not (source / "configure").is_file():
        raise ValueError("Expected an extracted Qt source tree")
    digest = hashlib.sha256()
    with archive.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != ARCHIVE_SHA256:
        raise ValueError("Qt archive SHA256 mismatch")

    patches = sorted((repo / "patches/qt6/all").glob("*.patch"))
    patches += sorted((repo / "patches/qt6/android").glob("*.patch"))
    records = [(str(path.relative_to(repo)), hashlib.sha256(path.read_bytes()).hexdigest())
               for path in patches]
    fingerprint = hashlib.sha256(json.dumps(
        [1, ARCHIVE_SHA256, records], separators=(",", ":")).encode()).hexdigest()
    state_path = source / ".longreach-patches.json"
    pending_path = source / ".longreach-patches.pending.json"
    previous = json.loads(state_path.read_text()) if state_path.exists() else {}
    if previous.get("fingerprint") == fingerprint and not pending_path.exists():
        print("Qt patch stack unchanged; preserving source timestamps")
        return

    paths = set(previous.get("files", []))
    if pending_path.exists():
        paths.update(json.loads(pending_path.read_text())["files"])
    for patch in patches:
        for line in patch.read_text().splitlines():
            match = re.match(r"^(?:---|\+\+\+) [ab]/([^\t]+)", line)
            if match:
                paths.add(match.group(1))
    for relative in paths:
        safe_path(source, relative)

    with tempfile.TemporaryDirectory(prefix="qt6-patch-stack-", dir="/work") as temporary:
        prepared = Path(temporary)
        with tarfile.open(archive, "r|xz") as package:
            for member in package:
                parts = PurePosixPath(member.name).parts
                if len(parts) < 2:
                    continue
                relative = "/".join(parts[1:])
                if relative not in paths:
                    continue
                if not member.isfile():
                    raise ValueError(f"Expected a regular source file: {relative}")
                destination = safe_path(prepared, relative)
                destination.parent.mkdir(parents=True, exist_ok=True)
                with package.extractfile(member) as incoming, destination.open("wb") as outgoing:
                    shutil.copyfileobj(incoming, outgoing)
                destination.chmod(member.mode)
        for patch in patches:
            subprocess.run(["git", "apply", str(patch.resolve())], cwd=prepared, check=True)

        # Retain the affected path set across an interrupted source update.
        pending_path.write_text(json.dumps({"files": sorted(paths)}) + "\n")
        changed = 0
        for relative in sorted(paths):
            incoming = safe_path(prepared, relative)
            destination = safe_path(source, relative)
            if incoming.is_file():
                if not destination.is_file() or incoming.read_bytes() != destination.read_bytes():
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(incoming, destination)
                    changed += 1
                shutil.copymode(incoming, destination)
            elif destination.is_file():
                destination.unlink()
                changed += 1
        state = {"fingerprint": fingerprint, "archive_sha256": ARCHIVE_SHA256,
                 "patches": records, "files": sorted(paths)}
        pending_path.write_text(json.dumps(state, indent=2) + "\n")
        pending_path.replace(state_path)
        print(f"Prepared Qt patch stack: {len(patches)} patches, {changed} changed source files")


if __name__ == "__main__":
    main()
