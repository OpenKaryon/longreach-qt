#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Boot the staged Sarge i386 examples in QEMU and require both test runs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]


def run_guest():
    def timed_out(signum, frame):
        raise TimeoutError("Sarge guest did not finish within 600 seconds")

    with subprocess.Popen([
        "qemu-system-i386", "-machine", "pc", "-accel", "tcg", "-cpu", "pentium3",
        "-m", "384", "-smp", "1", "-display", "none", "-monitor", "none",
        "-serial", "stdio", "-nic", "none", "-no-reboot",
        "-kernel", "/out/vmlinuz-2.6.8-4-386", "-initrd", "/out/sarge-initramfs.cpio.gz",
        "-append", "console=ttyS0 rdinit=/init panic=1 quiet",
    ], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True) as qemu:
        signal.signal(signal.SIGALRM, timed_out)
        signal.alarm(600)
        try:
            with Path("/out/qemu.log").open("w", encoding="utf-8") as log:
                for line in qemu.stdout:
                    log.write(line)
                    print(line, end="", flush=True)
                    if line.strip() == "SARGE_VM_DONE":
                        return
            raise RuntimeError("Sarge guest exited before reporting completion")
        finally:
            signal.alarm(0)
            if qemu.poll() is None:
                qemu.kill()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--sarge-image", default="qt4-linux-i386:latest")
    parser.add_argument("--qemu-image", default="longreach-run-qemu:lucid-i386-bookworm")
    args = parser.parse_args()
    output = args.out.resolve()
    try:
        audit = json.loads((output / "elf-audit.json").read_text(encoding="utf-8"))
        binaries = {entry["binary"]: entry["sha256"] for entry in audit["binaries"]}
        actual = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in (output / "bin").iterdir() if p.is_file()}
    except (OSError, ValueError, KeyError, TypeError):
        parser.error("Build and audit the examples with make qt4-linux-i386-llvm-examples first")
    if "qt-selftest-cxx23" not in binaries or actual != binaries:
        parser.error("Exported examples do not match the ELF audit")
    mounts = [
        "--mount", f"type=bind,source={ROOT},target=/repo,readonly",
        "--mount", f"type=bind,source={output},target=/out",
    ]
    subprocess.run([
        "docker", "run", "--rm", "--network", "none", *mounts,
        "-e", "SARGE_LLVM_SUITE=1",
        "--entrypoint", "bash", args.sarge_image, "-ec",
        "ln -s /repo/scripts/build/qt4-sarge /scripts; "
        "ln -s /repo/downloads/debian-sarge-kernel /kernels; "
        "bash /scripts/pack-vm.sh",
    ], check=True)
    subprocess.run([
        "docker", "run", "--rm", "--network", "none", "--cpus", "1", "--memory", "1g", *mounts,
        "-e", "SARGE_IN_QEMU_CONTAINER=1",
        "--entrypoint", "python3", args.qemu_image, f"/repo/{Path(__file__).relative_to(ROOT).as_posix()}",
    ], check=True)

    log = (output / "qemu.log").read_text(encoding="utf-8")
    modern = re.search(r"^SARGE_MODERN_BEGIN\n(.*?)^SARGE_MODERN_END$", log, re.M | re.S)
    if not modern:
        raise SystemExit("Missing C++23 guest output")
    (output / "cxx23.log").write_text(modern[1], encoding="utf-8")
    subprocess.run([sys.executable, str(ROOT / "scripts/tests/require-modern-cpp.py"),
                    str(output / "cxx23.log")], check=True)
    if not all(marker in log for marker in (
        "8 passed, 0 failed, 0 not built for this platform", "SARGE_SUITE_RESULT=0", "SARGE_MODERN_RESULT=0",
    )):
        raise SystemExit("The Sarge examples or the C++23 selftest failed")


if __name__ == "__main__":
    if os.environ.get("SARGE_IN_QEMU_CONTAINER") == "1":
        run_guest()
    else:
        main()
