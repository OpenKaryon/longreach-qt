#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Build the Linux LLVM SDK sequentially with hard container resource limits."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
COMPILER_IMAGE = "longreach-llvm:21.1.8-compiler"
TOOLCHAIN_IMAGE = "qt6-linux-amd64:llvm21-toolchain"
SDK_IMAGE = "qt6-linux-amd64:llvm21"


def docker(*args: str) -> str:
    return subprocess.check_output(["docker", *args], text=True).strip()


def image_environment(image: str) -> dict[str, str]:
    entries = json.loads(docker("image", "inspect", "--format", "{{json .Config.Env}}", image))
    return dict(entry.split("=", 1) for entry in entries)


def build_stage(stage: str, suite: Path) -> dict:
    if docker("ps", "--quiet"):
        raise RuntimeError("Another container is running; refusing concurrent SDK builds")
    name = f"longreach-qt6-linux-amd64-llvm21-{stage}"
    base = COMPILER_IMAGE if stage == "toolchain" else TOOLCHAIN_IMAGE
    image = TOOLCHAIN_IMAGE if stage == "toolchain" else SDK_IMAGE
    base_id = docker("image", "inspect", "--format", "{{.Id}}", base)
    helper = "prepare-toolchain.sh" if stage == "toolchain" else "build-qt.sh"
    volume = "longreach-llvm21-probes-build" if stage == "toolchain" else "longreach-qt6-linux-amd64-llvm21-build"
    destination = "/work" if stage == "toolchain" else "/opt/qt-build-llvm"
    command = ["create", "--pull", "never", "--name", name,
               "--cpus", "4", "--memory", "8g", "--network", "none", "--entrypoint", "/bin/bash",
               "--env", "LLVM_ROOT=/opt/llvm-21", "--env", "PARALLEL_JOBS=4",
               "--mount", f"type=bind,source={ROOT},target=/src,readonly",
               "--mount", f"type=bind,source={suite},target=/out",
               "--mount", f"type=volume,source={volume},target={destination}", base_id,
               f"/src/scripts/build/qt6-linux-amd64/{helper}"]
    docker(*command)
    log = ROOT / f"build/qt6-linux-amd64-llvm21-{stage}.log"
    print(f"Building {stage}: {log.name}", flush=True)
    started = time.monotonic()
    with log.open("wb") as stream:
        subprocess.run(["docker", "start", "-a", name], stdout=stream, stderr=subprocess.STDOUT, check=True)
    if docker("inspect", "--format", "{{.State.ExitCode}}", name) != "0":
        raise RuntimeError(f"{stage} failed; see {log}")
    environment = image_environment(base_id)
    if stage == "toolchain":
        environment.update(LLVM_ROOT="/opt/llvm-21",
                           PATH="/opt/longreach-llvm/bin:/opt/llvm-21/bin:" + environment["PATH"],
                           CC="/opt/longreach-llvm/bin/clang-c", CXX="/opt/longreach-llvm/bin/clang-cxx",
                           AR="/opt/llvm-21/bin/llvm-ar", RANLIB="/opt/llvm-21/bin/llvm-ranlib", NM="/opt/llvm-21/bin/llvm-nm")
    else:
        environment["QT_INSTALL_DIR"] = "/opt/qt6-linux-amd64-llvm"
    changes = []
    for key, value in environment.items():
        changes.extend(["--change", f"ENV {key}={value}"])
    command = ["/opt/llvm-21/bin/clang", "--version"]
    if stage == "qt":
        command = ["sh", "-c", "clang-cxx --version | head -1; /opt/qt6-linux-amd64-llvm/bin/qtpaths --qt-version"]
    changes.extend(["--change", "ENTRYPOINT []", "--change", "CMD " + json.dumps(command)])
    image_id = docker("commit", *changes, name, image)
    result = dict(stage=stage, status="PASS", base_image=base,
                  base_image_id=base_id,
                  image=image, image_id=image_id, seconds=round(time.monotonic()-started, 3),
                  log=log.name, volume=volume, cpus=4, memory="8g", network="none")
    print(f"{stage}: PASS; {image_id}", flush=True)
    return result


def check_sdk(suite: Path) -> dict:
    if docker("ps", "--quiet"):
        raise RuntimeError("Another container is running; refusing concurrent SDK checks")
    image_id = docker("image", "inspect", "--format", "{{.Id}}", SDK_IMAGE)
    log = ROOT / "build/qt6-linux-amd64-llvm21-checks.log"
    command = ["docker", "run", "--rm", "--pull", "never",
               "--name", "longreach-qt6-linux-amd64-llvm21-checks",
               "--cpus", "4", "--memory", "8g", "--network", "none", "--entrypoint", "/bin/bash",
               "--mount", f"type=bind,source={ROOT},target=/src,readonly",
               "--mount", f"type=bind,source={suite},target=/out", image_id,
               "/src/scripts/tests/qt6-linux-amd64-llvm/run-sdk-checks.sh"]
    print(f"Checking SDK: {log.name}", flush=True)
    started = time.monotonic()
    with log.open("wb") as stream:
        subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, check=True)
    result = dict(stage="checks", status="PASS", image=SDK_IMAGE, image_id=image_id,
                  seconds=round(time.monotonic()-started, 3), log=log.name,
                  cpus=4, memory="8g", network="none")
    print("SDK checks: PASS; required C++23 runs passed without FAIL/SKIP", flush=True)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", choices=["toolchain", "qt", "checks", "all"], default="all")
    parser.add_argument("--suite", type=Path, default=ROOT / "artifacts/tests-qt6-linux-amd64-llvm21")
    args = parser.parse_args()
    suite = args.suite.resolve()
    suite.mkdir(parents=True, exist_ok=True)
    (ROOT / "build").mkdir(exist_ok=True)
    spec = importlib.util.spec_from_file_location("sdk_build_tools", ROOT / "scripts/build/ensure-image.py")
    build_tools = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = build_tools
    spec.loader.exec_module(build_tools)
    source_base = None
    source_dirty = None
    if (ROOT / ".git").exists():
        source_base = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
        source_dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True))
    record = {"llvm":"21.1.8", "qt":"6.8.5", "stages":[],
              "source_base":source_base, "source_dirty":source_dirty,
              "source_sha256":{str(p.relative_to(ROOT)).replace("\\", "/"):hashlib.sha256(p.read_bytes()).hexdigest()
                               for folder in ["scripts/build/qt6-linux-amd64", "scripts/build/qt6-llvm-probes"]
                               for p in (ROOT / folder).iterdir() if p.is_file()}}
    try:
        with build_tools.build_lock():
            for stage in (["toolchain", "qt", "checks"] if args.stage == "all" else [args.stage]):
                result = check_sdk(suite) if stage == "checks" else build_stage(stage, suite)
                record["stages"].append(result)
                record["updated_utc"] = datetime.now(timezone.utc).isoformat()
                (suite / f"build-{stage}.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        record["error"] = str(error)
        (suite / "build-error.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
        print(f"error: {error}", file=sys.stderr)
        return 1
    error_record = suite / "build-error.json"
    if error_record.exists():
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%f")
        error_record.rename(suite / f"build-error-previous-{stamp}.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
