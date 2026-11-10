#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Require every named C++23 behavior to PASS; absent checks are failures too."""
import argparse
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]


def required_checks():
    lines = (ROOT / "tests/common/moderncpp-required.txt").read_text(encoding="utf-8").splitlines()
    names = [line for line in lines if not line.startswith("#")]
    if not names or len(names) != len(set(names)) or any(not name.strip() for name in names):
        raise RuntimeError("The required modern-C++ manifest is empty or contains duplicate/blank names")
    return names


def require_modern_cpp(output, allow_other_checks=False):
    required = required_checks()
    outcomes = re.findall(r"^(PASS|FAIL|SKIP): (.+)$", output, re.MULTILINE)
    levels = re.findall(r"^__cplusplus: (\d+)$", output, re.MULTILINE)
    if len(levels) != 1 or int(levels[0]) < 202302:
        raise RuntimeError("Required C++23 run has no C++23 language-mode record")
    for name in required:
        matching = [(status, text) for status, text in outcomes
                    if text == name or text.startswith(name + " - ")]
        if matching != [("PASS", name)]:
            raise RuntimeError("Required modern-C++ check must PASS exactly once: " + name)
    if any(status == "FAIL" for status, _ in outcomes):
        raise RuntimeError("The run contains a failed check")
    if not allow_other_checks and (len(outcomes) != len(required)
                                   or any(status != "PASS" for status, _ in outcomes)):
        raise RuntimeError("The required modern-only run must contain exactly the manifest checks and no SKIP")
    totals = re.findall(r"^(?:SUMMARY: |---- [^\n]*: )(\d+) passed, (\d+) failed, (\d+) skipped(?: ----)?$",
                        output, re.MULTILINE)
    actual = tuple(sum(status == kind for status, _ in outcomes) for kind in ("PASS", "FAIL", "SKIP"))
    if len(totals) != 1 or tuple(map(int, totals[0])) != actual:
        raise RuntimeError("Missing or inconsistent modern-C++ summary")
    return len(required)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--allow-other-checks", action="store_true",
                        help="Gate the modern section of a complete Qt run; unrelated Qt SKIP is allowed")
    args = parser.parse_args()
    try:
        count = require_modern_cpp(args.log.read_text(encoding="utf-8", errors="replace"), args.allow_other_checks)
    except (OSError, RuntimeError) as error:
        print("error: " + str(error), file=sys.stderr)
        return 1
    print("Required C++23 behaviors: {} PASS, 0 FAIL, 0 SKIP".format(count))
    return 0


if __name__ == "__main__":
    sys.exit(main())
