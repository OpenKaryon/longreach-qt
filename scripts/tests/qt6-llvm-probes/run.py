#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Build the upstream LLVM 21 target probes sequentially, stopping on failure."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import struct
import sys
import time


ROOT = Path(__file__).resolve().parents[3]
COMPILER_IMAGE = "longreach-llvm:21.1.8-compiler"
TARGET_IMAGES = {
    "linux-amd64": COMPILER_IMAGE,
    "linux-arm64": "qt6-linux-arm64:latest",
    "windows-amd64": COMPILER_IMAGE,
    "windows-arm64": COMPILER_IMAGE,
    "macos-amd64": "qt6-macos-amd64:latest",
    "macos-arm64": "qt6-macos-arm64:latest",
}


def docker_output(*arguments: str) -> str:
    return subprocess.check_output(["docker", *arguments], text=True).strip()


def load_tool(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def verify_architecture(data: bytes, target: str) -> str:
    arch = "amd64" if target.endswith("amd64") else "arm64"
    if target.startswith("linux-"):
        valid = data[:6] == b"\x7fELF\x02\x01"
        machine = struct.unpack_from("<H", data, 18)[0]
        expected = 62 if arch == "amd64" else 183
    elif target.startswith("windows-"):
        offset = struct.unpack_from("<I", data, 60)[0]
        valid = data[:2] == b"MZ" and data[offset:offset + 4] == b"PE\0\0"
        machine = struct.unpack_from("<H", data, offset + 4)[0]
        expected = 0x8664 if arch == "amd64" else 0xAA64
    else:
        valid = data[:4] == b"\xcf\xfa\xed\xfe"
        machine = struct.unpack_from("<I", data, 4)[0]
        expected = 0x01000007 if arch == "amd64" else 0x0100000C
    if not valid or machine != expected:
        raise RuntimeError(f"Unexpected binary format or architecture for {target}")
    return arch


MODERN_GATE = load_tool("required_modern_cpp", ROOT / "scripts/tests/require-modern-cpp.py")

def native_windows_check(binary: Path, log: Path) -> None:
    runner = load_tool("windows_error_mode", ROOT / "scripts/tests/qt6-win-amd64-llvm/run-suite.py")
    with runner.child_error_mode(), log.open("wb") as stream:
        result = subprocess.run(
            [str(binary)], cwd=binary.parent, stdout=stream, stderr=subprocess.STDOUT,
            timeout=60, creationflags=subprocess.CREATE_NO_WINDOW,
        )
    output = log.read_text(encoding="utf-8", errors="replace")
    if result.returncode:
        raise RuntimeError(f"Windows probe failed; see {log}")
    MODERN_GATE.require_modern_cpp(output)


def run_target(target: str, suite: Path, volume: str) -> dict:
    if docker_output("ps", "--quiet"):
        raise RuntimeError("Another container is running; refusing concurrent probe builds")
    image = TARGET_IMAGES[target]
    result = {
        "target": target,
        "build_host_image": image,
        "build_host_image_id": docker_output("image", "inspect", "--format", "{{.Id}}", image),
        "runtime": "NOT_RUN",
    }
    inputs = [
        "scripts/build/qt6-llvm-probes/inputs.json",
        "scripts/build/qt6-llvm-probes/build-compiler.sh",
        "scripts/build/qt6-llvm-probes/prepare-host-tools.sh",
        "scripts/build/qt6-llvm-probes/build-runtime.sh",
        "scripts/build/qt6-llvm-probes/build-windows-sysroot.sh",
        "scripts/tests/qt6-llvm-probes/CMakeLists.txt",
        "scripts/tests/qt6-llvm-probes/main.cpp",
        "scripts/tests/qt6-llvm-probes/run.py",
        "tests/common/moderncpp_checks.h",
        "tests/common/moderncpp-required.txt",
        "scripts/tests/require-modern-cpp.py",
    ]
    result["source_sha256"] = {
        name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in inputs
    }
    log = ROOT / "build/llvm21-probes" / f"{target}.log"
    if log.exists():
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S")
        log.rename(log.with_name(f"{target}-previous-{stamp}.log"))
    command = [
        "docker", "run", "--rm", "--pull", "never", "--name", f"longreach-llvm21-{target}",
        "--cpus", "4", "--memory", "8g", "--network", "none", "--entrypoint", "/bin/bash",
        "--env", "PARALLEL_JOBS=4", "--env", "LLVM_ROOT=/work/toolchain",
        "--mount", f"type=bind,source={ROOT},target=/src,readonly",
        "--mount", f"type=bind,source={suite},target=/out",
        "--mount", f"type=volume,source={volume},target=/work",
        image, "/src/scripts/build/qt6-llvm-probes/build-runtime.sh", target,
    ]
    print(f"Building {target}; log: {log.name}", flush=True)
    started = time.monotonic()
    with log.open("wb") as stream:
        subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, check=True)
    result["build_seconds"] = round(time.monotonic() - started, 3)
    result["build"] = "PASS"
    extension = ".exe" if target.startswith("windows-") else ""
    binary = suite / target / f"cxx23-probe{extension}"
    data = binary.read_bytes()
    result["architecture"] = verify_architecture(data, target)
    result["binary_sha256"] = hashlib.sha256(data).hexdigest()
    if target.startswith("linux-"):
        result["runtime"] = "PASS"
        result["runtime_method"] = "native CentOS 7 userland" if target == "linux-amd64" else "QEMU with CentOS 7 sysroot"
    elif target == "windows-amd64" and os.name == "nt":
        native_windows_check(binary, binary.parent / "run.log")
        result["runtime"] = "PASS"
        result["runtime_method"] = "native Windows host console; not Windows 7 certification"
    if result["runtime"] == "PASS":
        MODERN_GATE.require_modern_cpp((binary.parent / "run.log").read_text(encoding="utf-8"))
        result.update(passed=len(MODERN_GATE.required_checks()), failed=0, skipped=0)
    print(f"{target}: build PASS; runtime {result['runtime']}", flush=True)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", choices=TARGET_IMAGES, nargs="+", default=list(TARGET_IMAGES))
    parser.add_argument("--suite", type=Path, default=ROOT / "artifacts/probes-qt6-llvm21")
    parser.add_argument("--volume", default="longreach-llvm21-probes-build")
    args = parser.parse_args()
    suite = args.suite.resolve()
    suite.mkdir(parents=True, exist_ok=True)
    (ROOT / "build/llvm21-probes").mkdir(parents=True, exist_ok=True)
    record = {"llvm": "21.1.8", "results": []}
    build_tools = load_tool("llvm_probe_build_tools", ROOT / "scripts/build/ensure-image.py")
    with build_tools.build_lock():
        for target in args.target:
            try:
                record["results"].append(run_target(target, suite, args.volume))
            except (OSError, RuntimeError, struct.error, subprocess.SubprocessError) as error:
                record["error"] = {"target": target, "message": str(error)}
                print(f"error: {error}", file=sys.stderr)
            record["updated_utc"] = datetime.now(timezone.utc).isoformat()
            (suite / f"result-{target}.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
            if "error" in record:
                return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
