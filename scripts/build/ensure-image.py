#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Build an SDK image only when its build-kit inputs have changed."""

from __future__ import annotations

import argparse
from contextlib import contextmanager
import hashlib
import json
import subprocess
import sys
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LABEL = "org.openkaryon.longreach-qt.input-sha256"
INPUT_PREFIXES = ("scripts/build/", "scripts/audit/", "scripts/fetch/", "tests/", "licenses/")


@contextmanager
def build_lock():
    """Serialize SDK and example builds started through the short targets."""
    lock_path = ROOT / "build" / ".sdk-build.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("a+b") as lock:
        if lock_path.stat().st_size == 0:
            lock.write(b"0")
            lock.flush()
        lock.seek(0)
        if sys.platform == "win32":
            import msvcrt
            waiting = False
            while True:
                try:
                    msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
                    break
                except OSError:
                    if not waiting:
                        print("another SDK or example build is running; waiting", flush=True)
                        waiting = True
                    time.sleep(1)
            try:
                yield
            finally:
                lock.seek(0)
                msvcrt.locking(lock.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            import fcntl
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(lock.fileno(), fcntl.LOCK_UN)


def build_input(relative: str, family: str) -> bool:
    if relative in ("Makefile", f"mk/{family}.mk") or relative.startswith(INPUT_PREFIXES):
        return True
    if relative.startswith(("docker/", "cmake/", "patches/")):
        return relative.startswith((f"docker/{family}/", f"cmake/{family}/", f"patches/{family}/"))
    return False


def fingerprint(config: str, family: str, source_files: list[str]) -> str:
    """Include local edits and new files, not just the last Git commit."""
    names = subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=ROOT
    ).split(b"\0")
    paths = sorted({Path(name.decode("utf-8", "surrogateescape")) for name in names if name})
    digest = hashlib.sha256()
    digest.update(b"longreach-qt-image-v1\0")
    digest.update(config.encode("utf-8"))
    digest.update(b"\0")
    for path in paths:
        relative = path.as_posix()
        if not build_input(relative, family):
            continue
        full_path = ROOT / path
        digest.update(relative.encode("utf-8", "surrogateescape"))
        digest.update(b"\0")
        if full_path.is_file():
            with full_path.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
        else:
            digest.update(b"<deleted>")
        digest.update(b"\0")
    for source_name in sorted(source_files):
        source = Path(source_name)
        digest.update(source_name.encode("utf-8"))
        digest.update(b"\0")
        if source.is_file():
            with source.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
        else:
            digest.update(b"<missing>")
        digest.update(b"\0")
    return digest.hexdigest()


def image_fingerprint(image: str) -> str | None:
    # Docker Desktop can briefly report an existing tag as missing. Retry a
    # failed lookup before treating the SDK as absent and starting a rebuild.
    # A successful lookup with a missing/mismatched label is still stale.
    for attempt in range(2):
        result = subprocess.run(
            ["docker", "image", "inspect", image], capture_output=True, text=True, check=False
        )
        if not result.returncode:
            break
        if attempt == 0:
            time.sleep(0.5)
    if result.returncode:
        return None
    try:
        return json.loads(result.stdout)[0]["Config"]["Labels"].get(LABEL)
    except (IndexError, KeyError, TypeError, ValueError):
        return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--config", required=True)
    parser.add_argument("--make", default="make")
    parser.add_argument("--docker-build-flags", default="")
    parser.add_argument("--source-file", action="append", default=[])
    parser.add_argument("--examples-target")
    parser.add_argument("--examples-args", default="")
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    family = args.image.split("-", 1)[0]
    expected = fingerprint(args.config + "\0" + args.docker_build_flags,
                           family, args.source_file)
    with build_lock():
        if not args.force and image_fingerprint(args.image) == expected:
            print(f"{args.image}: image is current ({expected[:12]})", flush=True)
        else:
            print(f"{args.image}: building from current inputs ({expected[:12]})", flush=True)
            result = subprocess.run(
                [args.make, "--no-print-directory", "-j1", args.target,
                 f"DOCKER_BUILD_FLAGS={args.docker_build_flags} --label={LABEL}={expected}"],
                cwd=ROOT, check=False,
            )
            if result.returncode:
                return result.returncode
            if image_fingerprint(args.image) != expected:
                print(f"{args.image}: built image has no matching input label", file=sys.stderr)
                return 1
        if args.examples_target:
            return subprocess.run(
                [args.make, "--no-print-directory", "-j1", args.examples_target,
                 *args.examples_args.split()], cwd=ROOT, check=False
            ).returncode
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
