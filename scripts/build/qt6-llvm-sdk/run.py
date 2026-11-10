#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Build one upstream LLVM Qt SDK at a time, retaining resumable build volumes."""
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
PROFILES = {"linux-arm64": {"image": "qt6-linux-arm64", "dockerfile": "docker/qt6/linux/arm64/Dockerfile-llvm",
                             "prefix": "/opt/qt6-linux-arm64-llvm"}}


def docker(*args: str) -> str:
    return subprocess.check_output(["docker", *args], text=True).strip()


def idle(wait: bool) -> None:
    notified = False
    while docker("ps", "--quiet"):
        if not wait:
            raise RuntimeError("Another container is running; refusing concurrent SDK work")
        if not notified:
            print("Waiting for Docker to become idle", flush=True)
            notified = True
        time.sleep(2)


def environment(image: str) -> dict[str, str]:
    values = json.loads(docker("image", "inspect", "--format", "{{json .Config.Env}}", image))
    return dict(item.split("=", 1) for item in values)


def stage(target: str, phase: str, suite: Path, wait: bool, resume: bool) -> dict:
    idle(wait)
    profile = PROFILES[target]
    name = f"longreach-qt6-{target}-llvm21-{phase}"
    tag = profile["image"] + ":llvm21"
    log = ROOT / f"build/qt6-{target}-llvm21-{phase}.log"
    if log.exists() and not resume:
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%f")
        log.rename(log.with_name(log.stem+f"-previous-{stamp}.log"))
    started = time.monotonic()
    result = dict(target=target, phase=phase, cpus=4, memory="8g", network="none", log=log.name)
    if phase == "inputs":
        arguments = ["docker", "build", "--network=none", "--pull=false", "--progress=plain", "--target", "inputs",
                     "-f", profile["dockerfile"], "-t", tag + "-inputs", "."]
        with log.open("wb") as stream:
            subprocess.run(arguments, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, check=True)
        result.update(status="PASS", image=tag+"-inputs", image_id=docker("image", "inspect", "--format", "{{.Id}}", tag+"-inputs"),
                      resource_scope="Image assembly and host dependency inventory; no compiler process")
    elif phase == "checks":
        image_id = docker("image", "inspect", "--format", "{{.Id}}", tag)
        arguments = ["docker", "run", "--rm", "--pull", "never", "--name", name,
                     "--cpus", "4", "--memory", "8g", "--network", "none", "--entrypoint", "/bin/bash",
                     "--mount", f"type=bind,source={ROOT},target=/src,readonly",
                     "--mount", f"type=bind,source={suite},target=/out", image_id,
                     "/src/scripts/tests/qt6-llvm-sdk/build-checks.sh", target]
        print(f"{target}: checking SDK; {log.name}", flush=True)
        with log.open("wb") as stream:
            subprocess.run(arguments, stdout=stream, stderr=subprocess.STDOUT, check=True)
        result.update(status="PASS", image=tag, image_id=image_id, runtime="QEMU with CentOS 7 sysroot")
    else:
        base = tag + ("-inputs" if phase == "toolchain" else "-toolchain")
        base_id = docker("image", "inspect", "--format", "{{.Id}}", base)
        output = tag + "-toolchain" if phase == "toolchain" else tag
        helper = "prepare.sh" if phase == "toolchain" else "build-qt.sh"
        destination = "/work" if phase == "toolchain" else "/build"
        volume = "longreach-llvm21-probes-build" if phase == "toolchain" else f"longreach-qt6-{target}-llvm21-build"
        arguments = ["create", "--pull", "never", "--name", name, "--cpus", "4", "--memory", "8g", "--network", "none",
                     "--entrypoint", "/bin/bash", "--env", "PARALLEL_JOBS=4", "--env", "LLVM_ROOT=/opt/llvm-21",
                     "--mount", f"type=bind,source={ROOT},target=/src,readonly",
                     "--mount", f"type=bind,source={suite},target=/out",
                     "--mount", f"type=volume,source={volume},target={destination}", base_id,
                     f"/src/scripts/build/qt6-llvm-sdk/{helper}", target]
        if resume:
            state = json.loads(docker("inspect", name))[0]
            if state["State"]["Running"] or state["Image"] != base_id:
                raise RuntimeError("Cannot resume a running container or one from a different base image")
            if state["Config"]["Cmd"] != [f"/src/scripts/build/qt6-llvm-sdk/{helper}", target]:
                raise RuntimeError("The retained container has an unexpected command")
        else:
            docker(*arguments)
        print(f"{target} {phase}: running; {log.name}", flush=True)
        mode = "ab" if resume else "wb"
        with log.open(mode) as stream:
            subprocess.run(["docker", "start", "-a", name], stdout=stream, stderr=subprocess.STDOUT, check=True)
        state = json.loads(docker("inspect", name))[0]
        if state["State"]["ExitCode"] != 0 or state["State"]["OOMKilled"]:
            raise RuntimeError(f"{target} {phase} failed; see {log}")
        env = environment(base_id)
        env.update(LLVM_ROOT="/opt/llvm-21", QT_HOST_PATH="/opt/qt6-host-llvm21",
                   PATH="/opt/longreach-llvm/bin:/opt/llvm-21/bin:/opt/qt6-host-llvm21/bin:"+env["PATH"],
                   CC="/opt/longreach-llvm/bin/target-cc", CXX="/opt/longreach-llvm/bin/target-cxx",
                   AR="/opt/llvm-21/bin/llvm-ar", RANLIB="/opt/llvm-21/bin/llvm-ranlib", NM="/opt/llvm-21/bin/llvm-nm")
        if phase == "qt":
            env["QT_INSTALL_DIR"] = profile["prefix"]
        changes = []
        for key, value in env.items():
            changes += ["--change", f"ENV {key}={value}"]
        changes += ["--change", "ENTRYPOINT []", "--change", 'CMD ["/opt/llvm-21/bin/clang", "--version"]']
        image_id = docker("commit", *changes, name, output)
        result.update(status="PASS", image=output, image_id=image_id, base_image=base, base_image_id=base_id,
                      volume=volume, state={key:state["State"][key] for key in ["StartedAt","FinishedAt","ExitCode","OOMKilled"]})
    result["seconds"] = round(time.monotonic()-started, 3)
    print(f"{target} {phase}: PASS", flush=True)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", choices=PROFILES, required=True)
    parser.add_argument("--stage", choices=["inputs","toolchain","qt","checks","all"], default="all")
    parser.add_argument("--wait", action="store_true")
    parser.add_argument("--resume", action="store_true", help="Restart the retained stopped build container")
    args = parser.parse_args()
    if args.resume and args.stage not in ["toolchain","qt"]:
        parser.error("--resume requires one toolchain or qt stage")
    suite = ROOT / f"artifacts/tests-qt6-{args.target}-llvm21"
    suite.mkdir(parents=True, exist_ok=True)
    (ROOT/"build").mkdir(exist_ok=True)
    spec = importlib.util.spec_from_file_location("sdk_build_lock", ROOT/"scripts/build/ensure-image.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    sources = [p for folder in ["scripts/build/qt6-llvm-sdk","scripts/build/qt6-llvm-probes","scripts/tests/qt6-llvm-sdk"]
               for p in (ROOT/folder).iterdir() if p.is_file()]
    sources += [ROOT/PROFILES[args.target]["dockerfile"], ROOT/"tests/common/moderncpp_checks.h",
                ROOT/"tests/common/moderncpp-required.txt", ROOT/"scripts/tests/require-modern-cpp.py"]
    os_family = args.target.split("-", 1)[0]
    sources.extend((ROOT/"patches/qt6/all").glob("*.patch"))
    sources.extend((ROOT/f"patches/qt6/{os_family}").glob("*.patch"))
    source_base, source_dirty = None, None
    if (ROOT/".git").exists():
        source_base = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
        source_dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True))
    record = dict(target=args.target, source_base=source_base,
                  source_dirty=source_dirty, llvm="21.1.8", qt="6.8.5", stages=[],
                  source_sha256={str(p.relative_to(ROOT)).replace("\\","/"):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources})
    try:
        with module.build_lock():
            for phase in (["inputs","toolchain","qt","checks"] if args.stage=="all" else [args.stage]):
                record["stages"].append(stage(args.target, phase, suite, args.wait, args.resume))
                record["updated_utc"] = datetime.now(timezone.utc).isoformat()
                (suite/f"build-{phase}.json").write_text(json.dumps(record,indent=2)+"\n",encoding="utf-8")
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        record["error"] = str(error)
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%f")
        (suite/f"error-{stamp}.json").write_text(json.dumps(record,indent=2)+"\n",encoding="utf-8")
        print(f"error: {error}",file=sys.stderr)
        return 1
    return 0


if __name__=="__main__":
    raise SystemExit(main())
