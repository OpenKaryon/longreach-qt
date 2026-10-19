#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Build an SDK image only when its own inputs have changed.

An image's fingerprint covers exactly what goes into its `docker build`
commands (as `make -n <target>` prints them): each Dockerfile, its build
arguments, --platform and --target, and every file of the build context it
COPYs, ADDs or bind-mounts, read with the ARG values substituted. A target
that builds FROM another SDK image (`--needs`, qt6-host for the Qt 6 cross
targets) adds that image's fingerprint. So a patch under patches/qt6/macos
changes the macOS images only, and a Makefile edit only the images whose
build arguments it changes. PARALLEL_JOBS and DOCKER_BUILD_FLAGS are left
out: they do not change what is built.

The fingerprint is stored as an image label; when the label matches, the
docker build is skipped altogether, which does not need the Docker cache.
"""

from __future__ import annotations

import argparse
from contextlib import contextmanager
import fnmatch
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LABEL = "org.openkaryon.longreach-qt.input-sha256"
# Build arguments that set how fast, not what, is built.
SPEED_ARGS = {"PARALLEL_JOBS", "JOBS"}
# Build arguments that say where pinned inputs come from (a digest, a commit,
# a SHA256 fixes what they are), so switching to the copies rebuilds nothing.
SOURCE_ARGS = {"BASE_REGISTRY", "LAB_GIT", "LONGREACH_MIRROR"}
# Content hashes of large inputs (the downloads), by path, size and mtime.
HASH_CACHE = ROOT / "build" / ".input-hashes.json"
# For fingerprint() below, which the Qt 4 -examples scripts use for their stamp.
INPUT_PREFIXES = ("scripts/build/", "scripts/audit/", "scripts/fetch/", "tests/", "licenses/")
# Set for the make that builds an image, so that an image it depends on
# (qt6-host) is checked without waiting on the lock or being forced again.
NESTED = "LONGREACH_NESTED_IMAGE_BUILD"


@contextmanager
def build_lock():
    """Serialize SDK and example builds started through the short targets.

    scripts/build/build-all.py sets LONGREACH_BUILDS_COORDINATED=1: it limits
    concurrent builds itself, so each one skips the lock. So does an image
    built as a prerequisite of another (NESTED), under that one's lock.
    """
    if "1" in (os.environ.get("LONGREACH_BUILDS_COORDINATED"), os.environ.get(NESTED)):
        yield
        return
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
    """A whole Qt generation's files: the stamp the Qt 4 -examples scripts
    keep next to their test applications. Includes local edits and new
    files, not just the last Git commit."""
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


class Hashes:
    """File content hashes, remembered by path, size and mtime."""

    def __init__(self):
        try:
            self.known = json.loads(HASH_CACHE.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            self.known = {}
        self.changed = False

    def of(self, path: Path) -> str:
        stat = path.stat()
        key = path.relative_to(ROOT).as_posix()
        entry = self.known.get(key)
        if entry and entry[:2] == [stat.st_size, stat.st_mtime_ns]:
            return entry[2]
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        self.known[key] = [stat.st_size, stat.st_mtime_ns, digest.hexdigest()]
        self.changed = True
        return digest.hexdigest()

    def save(self):
        if not self.changed:
            return
        # Builds run side by side: write whole, and a lost race only costs a re-hash.
        HASH_CACHE.parent.mkdir(parents=True, exist_ok=True)
        partial = HASH_CACHE.with_name(f"{HASH_CACHE.name}.{os.getpid()}")
        partial.write_text(json.dumps(self.known, indent=0, sort_keys=True), encoding="utf-8")
        try:
            os.replace(partial, HASH_CACHE)
        except OSError:
            partial.unlink(missing_ok=True)
        self.changed = False


def docker_builds(make: str, target: str) -> list[list[str]]:
    """The docker build commands `make <target>` would run, in order."""
    printed = subprocess.run([make, "-n", "--no-print-directory", target, "DOCKER_BUILD_FLAGS="],
                             cwd=ROOT, capture_output=True, text=True, check=True).stdout
    return [words for words in (shlex.split(line) for line in printed.splitlines() if "docker build" in line)
            if words[:2] == ["docker", "build"]]


# docker build options that take a value; the rest are switches.
VALUE_OPTIONS = {"-f", "--file", "-t", "--tag", "--build-arg", "--target", "--platform", "--label",
                 "--progress", "--network", "--cache-from", "--cache-to", "--secret", "--ssh",
                 "--add-host", "--build-context", "--iidfile", "--output", "-o", "--shm-size",
                 "--ulimit", "--metadata-file", "--provenance", "--sbom"}


def parse_build(words: list[str]) -> dict:
    options: dict[str, list[str]] = {}
    positional = []
    i = 2
    while i < len(words):
        word = words[i]
        if word.startswith("-") and "=" in word and word.split("=", 1)[0] in VALUE_OPTIONS:
            name, value = word.split("=", 1)
        elif word in VALUE_OPTIONS:
            name, value = word, words[i + 1]
            i += 1
        elif word.startswith("-"):
            name, value = word, ""
        else:
            positional.append(word)
            i += 1
            continue
        options.setdefault({"--file": "-f", "--tag": "-t"}.get(name, name), []).append(value)
        i += 1
    args = dict(item.split("=", 1) if "=" in item else (item, "") for item in options.get("--build-arg", []))
    return {"dockerfile": options.get("-f", ["Dockerfile"])[-1], "args": args,
            "tags": options.get("-t", []), "target": options.get("--target", [""])[-1],
            "platform": options.get("--platform", [""])[-1], "context": (positional or ["."])[-1]}


def substitute(text: str, values: dict[str, str]) -> str:
    """Dockerfile variable substitution: $VAR, ${VAR}, ${VAR:-word}, ${VAR:+word}."""
    out, i = [], 0
    while i < len(text):
        if text[i] != "$":
            out.append(text[i])
            i += 1
        elif text.startswith("${", i):
            depth, j = 1, i + 2
            while j < len(text) and depth:
                depth += {"{": 1, "}": -1}.get(text[j], 0)
                j += 1
            body = text[i + 2:j - 1]
            name, op, word = re.match(r"([A-Za-z_][A-Za-z0-9_]*)(:?[-+]?)(.*)", body, re.S).groups()
            value = values.get(name, "")
            if op in (":-", "-"):
                value = value if value else substitute(word, values)
            elif op in (":+", "+"):
                value = substitute(word, values) if value else ""
            out.append(value)
            i = j
        else:
            match = re.match(r"\$([A-Za-z_][A-Za-z0-9_]*)", text[i:])
            if match:
                out.append(values.get(match.group(1), ""))
                i += len(match.group())
            else:
                out.append("$")
                i += 1
    return "".join(out)


def instructions(dockerfile: Path):
    """(KEYWORD, rest) for each instruction, continuation lines joined."""
    logical = ""
    for line in dockerfile.read_text(encoding="utf-8").splitlines():
        if line.lstrip().startswith("#"):
            continue
        if line.endswith("\\"):
            logical += line[:-1] + " "
            continue
        logical += line
        if logical.strip():
            keyword, _, rest = logical.strip().partition(" ")
            yield keyword.upper(), rest.strip()
        logical = ""


def context_sources(dockerfile: Path, build_args: dict[str, str]) -> list[str]:
    """The build-context paths a Dockerfile copies or bind-mounts."""
    values = dict(build_args)
    stages: set[str] = set()
    sources = []
    for keyword, rest in instructions(dockerfile):
        if keyword == "ARG":
            for item in shlex.split(rest):
                name, has_default, default = item.partition("=")
                if has_default and name not in build_args:
                    values[name] = substitute(default, values)
        elif keyword == "FROM":
            words = rest.split()
            if len(words) >= 3 and words[-2].upper() == "AS":
                stages.add(words[-1])
        elif keyword in ("COPY", "ADD"):
            words = rest.split()
            flags = [w for w in words if w.startswith("--")]
            if any(f.startswith("--from=") for f in flags):
                continue
            items = [w for w in words if not w.startswith("--")]
            if items and items[0].startswith("["):
                items = json.loads(" ".join(items))
            sources += [substitute(item, values) for item in items[:-1]
                        if not re.match(r"[a-z]+://", substitute(item, values))]
        elif keyword == "RUN":
            for mount in re.findall(r"--mount=(\S+)", rest):
                fields = dict(f.split("=", 1) if "=" in f else (f, "") for f in mount.split(","))
                if fields.get("type") == "bind" and "from" not in fields:
                    sources.append(substitute(fields.get("source", fields.get("src", ".")), values))
    return sources


def context_files(context: Path, sources: list[str]) -> list[tuple[str, Path | None]]:
    """Each source expanded to files. In folders Git tracks, only the files
    Git knows (not __pycache__ or editor droppings); elsewhere (downloads/)
    everything."""
    known = {name for name in subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=ROOT,
        text=True, encoding="utf-8").split("\0") if name}
    tracked_tops = {name.split("/", 1)[0] for name in known}
    files: dict[str, Path | None] = {}
    for source in sources:
        source = source.lstrip("/").rstrip("/") or "."
        matches = sorted(context.glob(source)) if any(c in source for c in "*?[") else [context / source]
        if not any(m.exists() for m in matches):
            files[f"<missing>/{source}"] = None
        for match in matches:
            for path in ([match] if match.is_file() else sorted(p for p in match.rglob("*") if p.is_file())):
                relative = path.relative_to(ROOT).as_posix()
                if relative in known or relative.split("/", 1)[0] not in tracked_tops:
                    files[relative] = path
    return sorted(files.items())


def target_inputs(make: str, target: str, needs: list[str], hashes: Hashes) -> tuple[str, bool]:
    """A target's fingerprint, and whether every input it names exists."""
    digest = hashlib.sha256(b"longreach-qt-image-v2\0")
    complete = True
    builds = docker_builds(make, target)
    if not builds:
        raise SystemExit(f"make -n {target} runs no docker build")
    ignore = ROOT / ".dockerignore"
    digest.update(ignore.read_bytes() if ignore.is_file() else b"")
    for words in builds:
        build = parse_build(words)
        context = (ROOT / build["context"]).resolve()
        dockerfile = context / build["dockerfile"] if not Path(build["dockerfile"]).is_absolute() \
            else Path(build["dockerfile"])
        args = {k: v for k, v in build["args"].items() if k not in SPEED_ARGS | SOURCE_ARGS}
        digest.update(json.dumps({"dockerfile": dockerfile.relative_to(ROOT).as_posix(), "args": args,
                                  "target": build["target"], "platform": build["platform"]},
                                 sort_keys=True).encode() + b"\0")
        digest.update(hashes.of(dockerfile).encode() + b"\0")
        for relative, path in context_files(context, context_sources(dockerfile, build["args"])):
            digest.update(relative.encode("utf-8") + b"\0")
            if path is None:
                complete = False
            digest.update((hashes.of(path) if path else "<missing>").encode() + b"\0")
    for need in needs:
        digest.update(f"needs {need} ".encode() + target_inputs(make, need, [], hashes)[0].encode() + b"\0")
    return digest.hexdigest(), complete


def relabel(image: str, value: str) -> None:
    """Put a new input label on an image that is already built."""
    subprocess.run(["docker", "build", "-q", "--label", f"{LABEL}={value}", "-t", image, "-"],
                   input=f"FROM {image}\n", text=True, check=True, capture_output=True)


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
    parser.add_argument("--target", required=True, help="the make target that runs the docker build")
    parser.add_argument("--needs", action="append", default=[], metavar="TARGET",
                        help="the make target of an image this one is built FROM (repeatable)")
    parser.add_argument("--make", default="make")
    parser.add_argument("--docker-build-flags", default="")
    parser.add_argument("--examples-target")
    parser.add_argument("--examples-args", default="")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--print", action="store_true", help="print the fingerprint and exit")
    args = parser.parse_args()

    # A nested build inherits the outer image's label in DOCKER_BUILD_FLAGS.
    flags = " ".join(f for f in args.docker_build_flags.split() if not f.startswith(f"--label={LABEL}="))
    force = args.force and os.environ.get(NESTED) != "1"
    hashes = Hashes()
    expected, complete = target_inputs(args.make, args.target, args.needs, hashes)
    hashes.save()
    if args.print:
        print(expected)
        return 0
    with build_lock():
        if not force and complete and image_fingerprint(args.image) == expected:
            print(f"{args.image}: image is current ({expected[:12]})", flush=True)
        else:
            print(f"{args.image}: building from current inputs ({expected[:12]})", flush=True)
            result = subprocess.run(
                [args.make, "--no-print-directory", "-j1", args.target,
                 f"DOCKER_BUILD_FLAGS={flags} --label={LABEL}={expected}"],
                cwd=ROOT, check=False, env=dict(os.environ, **{NESTED: "1"}),
            )
            if result.returncode:
                return result.returncode
            if not complete:
                # The make fetched inputs that were missing: label what they are now.
                fetched, _ = target_inputs(args.make, args.target, args.needs, hashes)
                hashes.save()
                if fetched != expected and image_fingerprint(args.image) == expected:
                    relabel(args.image, fetched)
                    expected = fetched
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
