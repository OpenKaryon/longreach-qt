#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Resolve the Qt 6 source archive for a given version, downloading if it can.

The kit targets Qt 6.8 LTS as its Qt 6 baseline, and an LTS series is where
"just download it" stops being enough. Patch releases of an LTS go to commercial
customers first and reach the public archive about a year later, so at any given
moment some 6.8.x exist that this kit can build but cannot fetch. A customer with
a Qt commercial licence has those sources; this repository does not, and has no
business redistributing them.

So the version and the source are two separate questions:

    QT6_VERSION   what to build      6.8.4
    QT6_SOURCE    where to get it    /path/to/qt-everywhere-src-6.8.8.tar.xz

and the resolution order is

    1. QT6_SOURCE, if given
    2. an archive already in downloads/, under either upstream name
    3. the public Qt archive
    4. an error that says how to supply it

Deliberately no table of which versions are commercial-only. Such a list is
wrong the moment Qt publishes the next patch, and the check it would perform is
one an HTTP request already answers.

Two upstream naming schemes have to be tried, which is not a detail that can be
derived from the version number:

    qt-everywhere-src-6.8.3.tar.xz              6.8.0 - 6.8.3, 6.10.x, 6.11.x
    qt-everywhere-opensource-src-6.8.4.tar.xz   6.8.4

6.8.4 is the LTS patch that was commercial-only first and later released to
everyone; it carries "opensource" in the name the way the Qt 5 archives do.
Whether every future delayed LTS patch follows that pattern is not something to
guess at, so both names are simply tried.

Usage:
    qt6-fetch-source.py <version> <download-dir> [--source PATH]

On success the archive is at <download-dir>/qt-everywhere-src-<version>.tar.xz,
under that canonical name whichever way it arrived, so nothing downstream has to
care where it came from.
"""

import argparse
from contextlib import contextmanager
import glob
import json
import os
import shutil
import sys
import urllib.error
import urllib.request

import fetch  # scripts/fetch/fetch.py: the per-file download lock

MIRROR = "https://qt.mirror.constant.com/archive/qt"
OFFICIAL = "https://download.qt.io/archive/qt"
MIRROR_COPY = os.environ.get("LONGREACH_MIRROR",
                             "https://github.com/OpenKaryonLab/longreach-qt-sources/releases/download/sources/").rstrip("/") + "/"


def archive_names(version):
    """Both upstream spellings, newest convention first."""
    return [
        "qt-everywhere-src-%s.tar.xz" % version,
        "qt-everywhere-opensource-src-%s.tar.xz" % version,
    ]


def series(version):
    return ".".join(version.split(".")[:2])


BUILD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "build")
HASHES = os.path.join(BUILD, ".qt6-source-hashes.json")


def content_hash(path):
    """SHA256 of path, kept in build/ by path, size and mtime of that same file
    (as ensure-image.py does): each make of a build compares the archives again."""
    stat = os.stat(path)
    key = os.path.abspath(path)
    stamp = [stat.st_size, stat.st_mtime_ns]
    try:
        with open(HASHES, encoding="utf-8") as stream:
            known = json.load(stream)
    except (OSError, ValueError):
        known = {}
    if not isinstance(known, dict):
        known = {}
    entry = known.get(key)
    if isinstance(entry, dict) and entry.get("stamp") == stamp and isinstance(entry.get("sha256"), str):
        return entry["sha256"]
    digest = fetch.sha256(path)
    known[key] = {"stamp": stamp, "sha256": digest}
    partial = "%s.%d" % (HASHES, os.getpid())
    try:
        os.makedirs(BUILD, exist_ok=True)
        with open(partial, "w", encoding="utf-8") as stream:
            json.dump(known, stream)
        os.replace(partial, HASHES)
    except OSError:
        # Another make has the file open: this one only re-hashes next time.
        try:
            os.remove(partial)
        except OSError:
            pass
    return digest


def same_content(a, b):
    if os.path.samefile(a, b):
        return True
    # By content: two different files written within one clock tick have the
    # same time on Windows, so times are compared only for one file over time.
    return os.path.getsize(a) == os.path.getsize(b) and content_hash(a) == content_hash(b)


# The Qt 6 image targets (mk/qt6.mk), whose builds read the archive; ensure-image.py
# holds build/locks/<target>.lock while it fingerprints and builds one.
QT6_TARGETS = ("qt6-host", "qt6-win-amd64", "qt6-win-arm64", "qt6-linux-amd64",
               "qt6-linux-arm64", "qt6-macos-amd64", "qt6-macos-arm64")


@contextmanager
def no_qt6_builds():
    """Held while the archive is replaced: the lock of every Qt 6 target but
    those of the build this make runs in (ensure-image.py names them), so that
    none starts meanwhile. One that another build holds stops this instead.
    A plain `make qt6-<target>` is a bare docker build and takes no lock."""
    locks = os.path.join(BUILD, "locks")
    os.makedirs(locks, exist_ok=True)
    names = set(QT6_TARGETS) | {os.path.basename(path)[:-len(".lock")]
                                for path in glob.glob(os.path.join(locks, "qt6-*.lock"))}
    names -= set(os.environ.get("LONGREACH_IMAGE_TARGET", "").split(","))
    held, busy = [], []
    try:
        for name in sorted(names):
            stream = open(os.path.join(locks, name + ".lock"), "a+b")
            if os.fstat(stream.fileno()).st_size == 0:
                stream.write(b"0")
                stream.flush()
            if fetch.try_lock(stream):
                held.append(stream)
            else:
                stream.close()
                busy.append(name)
        if busy:
            sys.exit("the Qt 6 archive cannot be replaced while %s %s being built from it; wait for %s"
                     % (", ".join(busy), "is" if len(busy) == 1 else "are",
                        "it" if len(busy) == 1 else "them"))
        yield
    finally:
        for stream in held:
            fetch.unlock(stream)
            stream.close()


def put(src, dest):
    """src at dest in one step: linked or copied to a part (fetch.partial),
    then moved over dest, so that an interrupted copy leaves no short archive."""
    # Windows does not rename over a read-only file (POSIX does). Not cleared
    # here, and said before a gigabyte is copied: dest may be a hard link to
    # someone's own archive, which shares the attribute.
    if sys.platform == "win32" and os.path.exists(dest) and not os.access(dest, os.W_OK):
        sys.exit("%s is read-only, so it cannot be replaced. It may be a hard link to an "
                 "archive of yours, which clearing the attribute (attrib -r) would change "
                 "too; delete it instead, or clear and set the attribute again." % dest)
    part = fetch.partial(dest)
    if os.path.exists(part):
        os.remove(part)
    try:
        # A link to a read-only file is read-only too, and Windows does not
        # delete one: such a source is copied.
        if not os.access(src, os.W_OK):
            raise PermissionError(src)
        os.link(src, part)
        how = "linked"
    except OSError:
        shutil.copyfile(src, part)
        how = "copied"
    try:
        fetch.finish(part, dest)
    except OSError as error:
        try:
            os.remove(part)
        except OSError:
            pass
        if sys.platform != "win32":
            sys.exit("%s cannot be replaced (%s)" % (dest, error))
        sys.exit("%s cannot be replaced (%s); a program still has it open, perhaps a plain "
                 "make qt6-<target> (docker build) reading it" % (dest, error))
    print("%s %s -> %s" % (how, src, dest))


def place(src, dest):
    """Put src at dest without copying a gigabyte when it can be avoided."""
    if os.path.abspath(src) == os.path.abspath(dest):
        return
    if not os.path.exists(dest):
        put(src, dest)
        return
    # Each make of a build runs this again (QT6_SOURCE makes the archive
    # phony): an archive already in place stays as it is.
    if same_content(src, dest):
        print("%s is already %s" % (dest, src))
        return
    with no_qt6_builds():
        put(src, dest)


def try_download(url, dest):
    """-> True if it downloaded. A 404 is an answer, not a failure to report."""
    part = fetch.partial(dest)
    try:
        print("trying %s" % url)
        # A .part left behind by an interrupted put() is a hard link to the
        # QT6_SOURCE archive: opening it for writing would truncate that.
        if os.path.exists(part):
            os.remove(part)
        with urllib.request.urlopen(url, timeout=60) as response, \
                open(part, "wb") as out:
            total = int(response.headers.get("content-length") or 0)
            done = 0
            while True:
                chunk = response.read(1 << 20)
                if not chunk:
                    break
                out.write(chunk)
                done += len(chunk)
                if total:
                    sys.stdout.write("\r  %.0f%% (%d/%d MB)"
                                     % (100.0 * done / total,
                                        done >> 20, total >> 20))
                    sys.stdout.flush()
        if total:
            sys.stdout.write("\n")
        fetch.complete(response, done)
        fetch.finish(part, dest)
        return True
    except urllib.error.HTTPError as e:
        if os.path.exists(part):
            os.remove(part)
        if e.code == 404:
            print("  not published here (404)")
            return False
        raise
    except Exception:
        if os.path.exists(part):
            os.remove(part)
        raise


# Failures other than 404 (a timeout, a 5xx): the next source is tried and
# these are reported if none had the archive.
ERRORS = []


def attempt(url, dest):
    """try_download, with any failure an answer too: the next source is tried."""
    try:
        return try_download(url, dest)
    except Exception as error:
        print("  failed: %s" % error)
        ERRORS.append("%s: %s" % (url, error))
        return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    parser.add_argument("download_dir")
    parser.add_argument("--source", default=os.environ.get("QT6_SOURCE", ""),
                        help="path to a source archive to use instead of downloading")
    args = parser.parse_args()

    os.makedirs(args.download_dir, exist_ok=True)
    canonical = os.path.join(args.download_dir,
                             "qt-everywhere-src-%s.tar.xz" % args.version)
    # Another build fetching the same archive (qt6-host next to a cross
    # target) finishes first; this one then finds it in step 2.
    with fetch.downloading(canonical):
        obtain(args, canonical)


def obtain(args, canonical):
    # 1. an explicitly supplied archive
    if args.source:
        if not os.path.isfile(args.source):
            sys.exit("QT6_SOURCE does not exist: %s" % args.source)
        print("using QT6_SOURCE %s" % args.source)
        place(args.source, canonical)
        return

    # 2. anything already downloaded, under either name
    for name in archive_names(args.version):
        local = os.path.join(args.download_dir, name)
        if os.path.isfile(local):
            print("using local %s" % local)
            place(local, canonical)
            return

    # 3. the OpenKaryonLab copy, kept under the canonical name (not with
    #    LONGREACH_UPSTREAM_FIRST=1, for a version not copied yet).
    upstream_first = os.environ.get("LONGREACH_UPSTREAM_FIRST") == "1"
    if not upstream_first and attempt(MIRROR_COPY + os.path.basename(canonical), canonical):
        print("saved %s" % canonical)
        return

    # 3a. the public archive: mirror first, then the canonical host, each under
    #    both names. The mirror is preferred for bandwidth but does not always
    #    carry a release as promptly as download.qt.io.
    for host in (MIRROR, OFFICIAL):
        for name in archive_names(args.version):
            url = "%s/%s/%s/single/%s" % (host, series(args.version),
                                          args.version, name)
            if attempt(url, canonical):
                if not upstream_first:
                    print("WARNING: %s is not in the OpenKaryonLab copy "
                          "(python scripts/fetch/mirror.py archives)" % os.path.basename(canonical))
                print("saved %s" % canonical)
                return

    # 3b. the copy, when upstream went first.
    if upstream_first and attempt(MIRROR_COPY + os.path.basename(canonical), canonical):
        print("saved %s" % canonical)
        return

    if ERRORS:
        sys.exit("Qt %s could not be downloaded:\n  " % args.version + "\n  ".join(ERRORS))

    # 4. It is not public. Say what to do, without claiming to know why - the
    #    same 404 covers a commercial-only LTS patch and a typo in the version.
    sys.exit(
        "\n"
        "Qt %(v)s is not available from the public Qt source archive.\n"
        "\n"
        "This can mean the version does not exist, or that it is a Qt LTS patch\n"
        "release that has not reached the public archive yet - those go to\n"
        "commercial licence holders first. If you have the sources, supply them:\n"
        "\n"
        "    cp qt-everywhere-src-%(v)s.tar.xz %(d)s/\n"
        "\n"
        "or point at them directly:\n"
        "\n"
        "    make qt6-linux-amd64 QT6_VERSION=%(v)s QT6_SOURCE=/path/to/archive.tar.xz\n"
        % {"v": args.version, "d": args.download_dir})


if __name__ == "__main__":
    main()
