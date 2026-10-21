#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Build an SDK image only when its own inputs have changed.

An image's fingerprint covers exactly what goes into its `docker build`
commands (as `make -n <target>` prints them): each Dockerfile, the build
arguments it declares, --platform and --target, and every file of the build
context it COPYs, ADDs or bind-mounts, read with the ARG values substituted. A target
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
# And the targets whose locks it and the builds around it hold, comma-separated
# (qt6-fetch-source.py leaves those out).
TARGET = "LONGREACH_IMAGE_TARGET"


def try_lock(stream) -> bool:
    """Lock an open file's first byte without waiting: False if another process holds it."""
    stream.seek(0)
    if sys.platform == "win32":
        import msvcrt
        try:
            msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
            return True
        except OSError:
            return False
    import fcntl
    try:
        fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        return True
    except OSError:
        return False


def unlock(stream) -> None:
    stream.seek(0)
    if sys.platform == "win32":
        import msvcrt
        msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
    else:
        import fcntl
        fcntl.flock(stream.fileno(), fcntl.LOCK_UN)


@contextmanager
def held(path: Path, wait: bool, busy: str):
    """Hold the lock file at path; if another process has it, wait (printing
    busy once) or exit with busy as the error."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a+b") as stream:
        if path.stat().st_size == 0:
            stream.write(b"0")
            stream.flush()
        if not try_lock(stream):
            if not wait:
                raise SystemExit(busy)
            print(busy + "; waiting", flush=True)
            while not try_lock(stream):
                time.sleep(1)
        try:
            yield
        finally:
            unlock(stream)


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
    with held(ROOT / "build" / ".sdk-build.lock", wait=True,
              busy="another SDK or example build is running"):
        yield


@contextmanager
def target_lock(target: str):
    """One build of a target at a time on this machine, whoever started it
    (make, build-all.py, another shell): a second one stops with an error. An
    image built as another's prerequisite (NESTED: qt6-host) waits instead,
    since the target that needs it cannot go on without it."""
    with held(ROOT / "build" / "locks" / f"{target}.lock", wait=os.environ.get(NESTED) == "1",
              busy=f"{target} is already being built on this machine"):
        yield


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
    result = subprocess.run([make, "-n", "--no-print-directory", target, "DOCKER_BUILD_FLAGS="],
                            cwd=ROOT, capture_output=True, text=True, check=False)
    if result.returncode:
        # make's own message, for example the licence profile guard.
        sys.stderr.write(result.stderr)
        raise SystemExit(result.returncode)
    printed = result.stdout
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


def declared_args(dockerfile: Path) -> set[str]:
    """The build arguments a Dockerfile declares; docker build ignores the rest."""
    return {item.partition("=")[0] for keyword, rest in instructions(dockerfile) if keyword == "ARG"
            for item in shlex.split(rest)}


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


MISSING = "<missing>"


def target_inputs(make: str, target: str, needs: list[str], hashes: Hashes) -> tuple[str, bool, dict[str, str]]:
    """A target's fingerprint, whether every input it names exists, and the
    inputs one by one (name: hash, or MISSING), for comparing them later."""
    digest = hashlib.sha256(b"longreach-qt-image-v2\0")
    complete = True
    items: dict[str, str] = {}
    builds = docker_builds(make, target)
    if not builds:
        raise SystemExit(f"make -n {target} runs no docker build")
    ignore = ROOT / ".dockerignore"
    ignored = ignore.read_bytes() if ignore.is_file() else b""
    digest.update(ignored)
    items[".dockerignore"] = hashlib.sha256(ignored).hexdigest()
    for number, words in enumerate(builds):
        build = parse_build(words)
        context = (ROOT / build["context"]).resolve()
        dockerfile = context / build["dockerfile"] if not Path(build["dockerfile"]).is_absolute() \
            else Path(build["dockerfile"])
        declared = declared_args(dockerfile)
        args = {k: v for k, v in build["args"].items() if k in declared and k not in SPEED_ARGS | SOURCE_ARGS}
        options = json.dumps({"dockerfile": dockerfile.relative_to(ROOT).as_posix(), "args": args,
                              "target": build["target"], "platform": build["platform"]}, sort_keys=True)
        digest.update(options.encode() + b"\0")
        digest.update(hashes.of(dockerfile).encode() + b"\0")
        items[f"docker build {number}"] = options + " " + hashes.of(dockerfile)
        for relative, path in context_files(context, context_sources(dockerfile, build["args"])):
            digest.update(relative.encode("utf-8") + b"\0")
            if path is None:
                complete = False
            value = hashes.of(path) if path else MISSING
            digest.update(value.encode() + b"\0")
            items[relative] = value
    for need in needs:
        need_digest, _, need_items = target_inputs(make, need, [], hashes)
        digest.update(f"needs {need} ".encode() + need_digest.encode() + b"\0")
        items.update({f"{need}: {name}": value for name, value in need_items.items()})
    return digest.hexdigest(), complete, items


# Where make puts what it fetches; nothing else may appear during a build.
FETCHED = "downloads/"


def changed_inputs(before: dict[str, str], after: dict[str, str]) -> list[str]:
    """Inputs that differ between before and after a build: changed, gone,
    or new. New is fine in downloads/, which is what the make fetched; so is
    a .part gone from there (an earlier version's, which fetch.py removes)."""
    def fetched(name: str) -> bool:  # "qt6-host: <path>" for an input of --needs
        return name.split(": ", 1)[-1].startswith(FETCHED)
    changed = [name for name, value in before.items()
               if value != MISSING and after.get(name) != value
               and not (name not in after and name.endswith(".part") and fetched(name))]
    changed += [name for name in after if name not in before and not fetched(name)]
    return sorted(changed)


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
    if args.print:
        hashes = Hashes()
        print(target_inputs(args.make, args.target, args.needs, hashes)[0])
        hashes.save()
        return 0
    if os.environ.get(NESTED) != "1":
        # make's own errors (a Qt 6 version without a pin, the licence
        # profile) now, not after waiting for the build lock.
        docker_builds(args.make, args.target)
        # A second build of the same target stops here, before it waits for
        # the build lock. Held while waiting, the target lock could block a
        # build that holds the build lock and needs this target (qt6-host).
        with target_lock(args.target):
            pass
    with build_lock(), target_lock(args.target):
        # The inputs are read under the locks: no other build replaces one
        # (qt6-fetch-source.py and QT6_SOURCE) between this and the build.
        # Loaded here: builds that ran while this one waited added to it.
        hashes = Hashes()
        expected, complete, inputs = target_inputs(args.make, args.target, args.needs, hashes)
        hashes.save()
        if not force and complete and image_fingerprint(args.image) == expected:
            print(f"{args.image}: image is current ({expected[:12]})", flush=True)
        else:
            print(f"{args.image}: building from current inputs ({expected[:12]})", flush=True)
            result = subprocess.run(
                [args.make, "--no-print-directory", "-j1", args.target,
                 f"DOCKER_BUILD_FLAGS={flags} --label={LABEL}={expected}"],
                cwd=ROOT, check=False,
                env=dict(os.environ, **{NESTED: "1", TARGET: ",".join(
                    t for t in (os.environ.get(TARGET, ""), args.target) if t)}),
            )
            if result.returncode:
                return result.returncode
            built, _, after = target_inputs(args.make, args.target, args.needs, hashes)
            hashes.save()
            changed = changed_inputs(inputs, after)
            if changed:
                # Something the build reads changed while it ran (BuildKit reads
                # the context step by step): the image may hold old and new, and
                # the label would name inputs it was not built from.
                relabel(args.image, "inputs-changed-during-build")
                print(f"{args.image}: changed while it was built: {', '.join(changed[:5])}"
                      f"{' ...' if len(changed) > 5 else ''}; build it again", file=sys.stderr)
                return 1
            if built != expected and image_fingerprint(args.image) == expected:
                # The make fetched inputs that were missing: label what they are now.
                relabel(args.image, built)
                expected = built
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
