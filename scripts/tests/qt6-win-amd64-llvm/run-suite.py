#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Run Windows smoke checks sequentially and stop on the first failure."""

from __future__ import annotations

import argparse
import ctypes
import os
import re
import subprocess
import sys
from collections.abc import Iterator
from contextlib import contextmanager
from ctypes import wintypes
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
DEFAULT_SUITE = ROOT / "artifacts/tests-qt6-win-amd64-llvm19"
EXTRA_APPLICATIONS = (
    "qt-selftest-experimental",
    "modern-cxx23-ordinary",
    "modern-cxx23-experimental",
)
EXPERIMENTAL_APPLICATIONS = {"qt-selftest-experimental", "modern-cxx23-experimental"}
REQUIRED_THREAD_CHECKS = (
    "C++20 std::jthread",
    "C++20 std::stop_token and callbacks",
)
SEM_FAILCRITICALERRORS = 0x0001
SEM_NOGPFAULTERRORBOX = 0x0002
SEM_NOOPENFILEERRORBOX = 0x8000


def ordinary_applications() -> list[str]:
    lines = (ROOT / "tests/expected-apps.txt").read_text(encoding="utf-8").splitlines()
    names = (line.strip() for line in lines)
    return [name for name in names
            if name and not name.startswith("#") and name != "smoke-runner"]


@contextmanager
def child_error_mode() -> Iterator[None]:
    """Keep crash dialogs out of our children without changing system policy."""
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.GetErrorMode.argtypes = []
    kernel.GetErrorMode.restype = wintypes.UINT
    kernel.SetErrorMode.argtypes = [wintypes.UINT]
    kernel.SetErrorMode.restype = wintypes.UINT
    previous = kernel.GetErrorMode()
    flags = SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX
    kernel.SetErrorMode(previous | flags)
    try:
        yield
    finally:
        kernel.SetErrorMode(previous)


def require_cpp_threads(output: str) -> None:
    lines = set(output.splitlines())
    for check in REQUIRED_THREAD_CHECKS:
        if f"PASS: {check}" not in lines:
            raise RuntimeError(f"Required experimental check did not PASS: {check}")


def run_check(suite: Path, application: str, environment: dict[str, str]) -> str:
    language_probe = application.startswith("modern-cxx23-")
    arguments = [] if language_probe else ["--selftest"]
    timeout = 60 if language_probe else 180
    log = suite / f"smoke-{application}.log"
    with log.open("wb") as stream:
        result = subprocess.run(
            [str(suite / f"{application}.exe"), *arguments],
            cwd=suite, env=environment, stdout=stream, stderr=subprocess.STDOUT,
            timeout=timeout, creationflags=subprocess.CREATE_NO_WINDOW,
        )
    output = log.read_text(encoding="utf-8", errors="replace")
    if result.returncode or re.search(r"^FAIL:", output, re.MULTILINE):
        code = result.returncode & 0xFFFFFFFF
        raise RuntimeError(f"{application}.exe: exit 0x{code:08x}; stopped, see {log.name}")
    if application in EXPERIMENTAL_APPLICATIONS:
        require_cpp_threads(output)
    print(f"{application}.exe: PASS", flush=True)
    return output


def write_report(suite: Path, results: list[tuple[str, str]]) -> None:
    report = "".join(f"=== {name} --selftest ===\n{output}\n" for name, output in results)
    report += f"\n{len(results)} passed, 0 failed, 0 not built for this platform\n"
    (suite / "smoke-report.txt").write_text(report, encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    applications = ordinary_applications()
    parser.add_argument("--suite", type=Path, default=DEFAULT_SUITE)
    parser.add_argument("--only", choices=[*applications, *EXTRA_APPLICATIONS],
                        help="Run one named ordinary, experimental or language executable")
    args = parser.parse_args(argv)
    if os.name != "nt":
        parser.error("Run this script on Windows, after cross-compilation finishes")

    suite = args.suite.resolve()
    environment = os.environ.copy()
    environment.update(QT_QPA_PLATFORM="windows", QT_FORCE_STDERR_LOGGING="1",
                       QT_ASSUME_STDERR_HAS_CONSOLE="1")
    selected = [args.only] if args.only else [*applications, *EXTRA_APPLICATIONS]
    results = []
    try:
        with child_error_mode():
            for application in selected:
                output = run_check(suite, application, environment)
                if application in applications:
                    results.append((application, output))
        if not args.only:
            write_report(suite, results)
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
