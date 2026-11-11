#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Execute the Qt SDK console checks on a configured macOS SSH guest/host."""
from __future__ import annotations
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
REMOTE_COMMAND = r"""set -e
work=$(mktemp -d /tmp/longreach-cxx23.XXXXXX)
cd "$work"
trap 'rm -f ./modern-only; cd /; rmdir "$work"' EXIT
cat > ./modern-only
chmod 700 ./modern-only
/usr/bin/perl -e 'alarm 60; exec @ARGV' ./modern-only
"""


def run(target: str, suite: Path, toolchain: bool) -> dict:
    hosts_path = ROOT/"scripts/run/hosts.local.json"
    if not hosts_path.exists():
        return dict(runtime_status="PENDING", runtime="No local macOS SSH inventory")
    hosts = json.loads(hosts_path.read_text(encoding="utf-8"))
    key = os.environ.get("LONGREACH_MACOS_HOST", "highsierra" if target.endswith("amd64") else "macos-arm64")
    host = hosts.get(key)
    if not host or host.get("backend") != "ssh" or host.get("os") != "macos":
        return dict(runtime_status="PENDING", runtime="No matching macOS SSH host configured")
    return run_host(target, suite, toolchain, host)


def run_host(target: str, suite: Path, toolchain: bool, host: dict) -> dict:
    ssh = ["ssh", "-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=12",
           "-o", "ServerAliveInterval=10", "-o", "ServerAliveCountMax=2",
           *host.get("ssh_options", []), host["target"]]
    return run_ssh(target, suite, toolchain, ssh)


def run_ssh(target: str, suite: Path, toolchain: bool, ssh: list[str]) -> dict:
    transport_log = suite/"macos-ssh-probe.log"
    try:
        probe = subprocess.run(ssh+["uname -m; sw_vers -productVersion"], capture_output=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return dict(runtime_status="PENDING", runtime="macOS SSH preflight timed out or could not start")
    transport_log.write_bytes(probe.stdout+probe.stderr)
    lines = probe.stdout.decode("utf-8", "replace").strip().splitlines()
    expected = "x86_64" if target.endswith("amd64") else "arm64"
    if probe.returncode or len(lines) != 2 or lines[0] != expected:
        return dict(runtime_status="PENDING", runtime="macOS SSH host unreachable or architecture does not match")
    spec = importlib.util.spec_from_file_location("sdk_macos_modern_gate", ROOT/"scripts/tests/require-modern-cpp.py")
    gate = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = gate
    spec.loader.exec_module(gate)
    names = ["installed-toolchain-cxx23"] if toolchain else ["modern-cxx17", "modern-cxx20", "modern-cxx23"]
    records = []
    for name in names:
        log = suite/(name+".log")
        with log.open("wb") as output:
            result = subprocess.run(ssh+[REMOTE_COMMAND], input=(suite/name).read_bytes(),
                                    stdout=output, stderr=subprocess.STDOUT, timeout=100)
        text = log.read_text(encoding="utf-8", errors="replace")
        if result.returncode == 255:
            return dict(runtime_status="PENDING", runtime="macOS SSH transport lost", checks=records)
        if result.returncode or re.search(r"^FAIL:", text, re.MULTILINE):
            raise RuntimeError(f"macOS {name} failed; see {log.name}")
        summary = re.search(r"(\d+) passed, (\d+) failed, (\d+) skipped", text)
        if not summary:
            raise RuntimeError(f"Missing summary in {log.name}")
        passed, failed, skipped = map(int, summary.groups())
        if name.endswith("cxx23"):
            gate.require_modern_cpp(text)
        records.append(dict(program=name, passed=passed, failed=failed, skipped=skipped, log=log.name))
        print(f"{target} {name}: {passed} PASS, {failed} FAIL, {skipped} SKIP", flush=True)
    return dict(runtime_status="PASS", runtime=f"macOS {lines[1]} {lines[0]} via SSH", checks=records)
