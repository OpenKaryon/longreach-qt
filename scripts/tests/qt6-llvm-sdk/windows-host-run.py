#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Run only LLVM SDK console consumers on a matching Windows host."""
from __future__ import annotations
import importlib.util
import os
from pathlib import Path
import platform
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def run(target: str, suite: Path, toolchain: bool) -> dict:
    machine = platform.machine().lower()
    native = {"amd64":"windows-amd64", "x86_64":"windows-amd64",
              "arm64":"windows-arm64", "aarch64":"windows-arm64"}.get(machine)
    if os.name != "nt" or target != native:
        return {"runtime_status":"PENDING", "runtime":"No matching Windows host configured"}
    support = load("windows_child_error_mode", ROOT/"scripts/tests/qt6-win-amd64-llvm/run-suite.py")
    gate = load("required_sdk_modern_cpp", ROOT/"scripts/tests/require-modern-cpp.py")
    env = os.environ.copy()
    env.update(QT_QPA_PLATFORM="windows", QT_FORCE_STDERR_LOGGING="1", QT_ASSUME_STDERR_HAS_CONSOLE="1")
    programs = (["installed-toolchain-cxx23"] if toolchain else
                ["modern-cxx17", "modern-cxx20", "modern-cxx23"])
    records = []
    with support.child_error_mode():
        for name in programs:
            binary = suite/(name+".exe")
            log = suite/(name+".log")
            with log.open("wb") as stream:
                process = subprocess.run([str(binary)], cwd=suite, env=env, stdout=stream,
                                         stderr=subprocess.STDOUT, timeout=60,
                                         creationflags=subprocess.CREATE_NO_WINDOW)
            output = log.read_text(encoding="utf-8", errors="replace")
            if process.returncode or re.search(r"^FAIL:", output, re.MULTILINE):
                raise RuntimeError(f"{name} failed on Windows host; see {log.name}")
            summary = re.search(r"(\d+) passed, (\d+) failed, (\d+) skipped", output)
            if not summary:
                raise RuntimeError(f"Missing summary in {log.name}")
            passed, failed, skipped = map(int, summary.groups())
            if name.endswith("cxx23"):
                gate.require_modern_cpp(output)
            records.append(dict(program=name, passed=passed, failed=failed, skipped=skipped, log=log.name))
            print(f"{target} {name}: {passed} PASS, {failed} FAIL, {skipped} SKIP", flush=True)
    return {"runtime_status":"PASS", "runtime":f"Native Windows console ({platform.version()})", "checks":records}
