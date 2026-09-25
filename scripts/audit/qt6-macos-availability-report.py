#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Summarize Clang's macOS deployment-target availability warnings in a build log."""

import argparse
from collections import Counter
from pathlib import Path
import re


VERSION = re.compile(r"macOS (\d+(?:\.\d+){1,2}) or newer")
SOURCE = re.compile(r"/workspace/qt-src/([^:]+):\d+:\d+: warning:")
DIAGNOSTIC = "[-Wunguarded-availability-new]"


def summarize(path: Path) -> None:
    versions: Counter[str] = Counter()
    modules: Counter[str] = Counter()
    files: Counter[str] = Counter()
    unmatched = 0

    with path.open(encoding="utf-8", errors="replace") as log:
        for line in log:
            if DIAGNOSTIC not in line:
                continue
            version = VERSION.search(line)
            source = SOURCE.search(line)
            if not version or not source:
                unmatched += 1
                continue
            versions[version.group(1)] += 1
            source_file = source.group(1)
            modules[source_file.split("/", 1)[0]] += 1
            files[source_file] += 1

    print(f"{path}: {sum(versions.values())} unguarded availability warnings")
    for version, count in sorted(versions.items(), key=lambda item: tuple(map(int, item[0].split(".")))):
        print(f"  macOS {version}: {count}")
    print("  modules:")
    for module, count in modules.most_common():
        print(f"    {module}: {count}")
    print("  most affected files:")
    for source_file, count in files.most_common(12):
        print(f"    {source_file}: {count}")
    if unmatched:
        print(f"  unmatched diagnostics: {unmatched}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logs", nargs="+", type=Path)
    args = parser.parse_args()
    for path in args.logs:
        summarize(path)


if __name__ == "__main__":
    main()
