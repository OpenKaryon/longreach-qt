#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Boot Sarge in QEMU and verify the standalone probe or the SDK suite."""
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

    arch = os.environ["SARGE_ARCH"]
    kernel = "2.6.8-4-386" if arch == "i386" else "2.6.8-12-amd64-generic"
    machine = "i386" if arch == "i386" else "x86_64"
    cpu = "pentium3" if arch == "i386" else "qemu64,phys-bits=32"
    boot_args = "console=ttyS0 rdinit=/init panic=1 quiet"
    if arch == "amd64":
        boot_args += " memmap=exactmap memmap=636K@0 memmap=383M@1M"

    with subprocess.Popen([
        f"qemu-system-{machine}", "-machine", "pc", "-accel", "tcg", "-cpu", cpu,
        "-m", "384", "-smp", "1", "-display", "none", "-monitor", "none",
        "-serial", "stdio", "-nic", "none", "-no-reboot",
        "-kernel", f"/out/vmlinuz-{kernel}", "-initrd", "/out/sarge-initramfs.cpio.gz",
        "-append", boot_args,
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
    parser.add_argument("--arch", choices=("i386", "amd64"), default="i386")
    parser.add_argument("--probe-only", action="store_true")
    parser.add_argument("--sarge-image")
    parser.add_argument("--qemu-image")
    args = parser.parse_args()
    output = args.out.resolve()
    sarge_image = args.sarge_image or f"qt4-linux-{args.arch}:latest"
    qemu_image = args.qemu_image or f"longreach-run-qemu:lucid-{args.arch}-bookworm"
    packages = "debian-sarge-kernel" if args.arch == "i386" else "debian-sarge-kernel-amd64"
    kernel_path = ROOT / "downloads" / packages
    if not kernel_path.is_dir():
        parser.error(f"Stage the {args.arch} Sarge kernel packages under downloads/{packages}")
    if args.probe_only:
        if not (output / "bin/cxx23-probe").is_file():
            parser.error("Missing standalone probe in the output directory")
    else:
        verify_examples(output, args.arch, parser)
    mounts = [
        "--mount", f"type=bind,source={ROOT},target=/repo,readonly",
        "--mount", f"type=bind,source={output},target=/out",
        "-e", f"SARGE_ARCH={args.arch}",
    ]
    subprocess.run([
        "docker", "run", "--rm", "--network", "none", *mounts,
        "-e", "SARGE_LLVM_PROBE=1" if args.probe_only else "SARGE_LLVM_SUITE=1",
        "--mount", f"type=bind,source={kernel_path},target=/kernels,readonly",
        "--entrypoint", "bash", sarge_image, "-ec",
        "ln -s /repo/scripts/build/qt4-sarge /scripts; "
        "bash /scripts/pack-vm.sh",
    ], check=True)
    subprocess.run([
        "docker", "run", "--rm", "--network", "none", "--cpus", "1", "--memory", "1g", *mounts,
        "-e", "SARGE_IN_QEMU_CONTAINER=1",
        "--entrypoint", "python3", qemu_image, f"/repo/{Path(__file__).relative_to(ROOT).as_posix()}",
    ], check=True)

    log = (output / "qemu.log").read_text(encoding="utf-8")
    modern = re.search(r"^SARGE_MODERN_BEGIN\n(.*?)^SARGE_MODERN_END$", log, re.M | re.S)
    if not modern:
        raise SystemExit("Missing C++23 guest output")
    (output / "cxx23.log").write_text(modern[1], encoding="utf-8")
    subprocess.run([sys.executable, str(ROOT / "scripts/tests/require-modern-cpp.py"),
                    str(output / "cxx23.log")], check=True)
    if "SARGE_MODERN_RESULT=0" not in log.splitlines():
        raise SystemExit("The Sarge C++23 run failed")
    if not args.probe_only and (
        "8 passed, 0 failed, 0 not built for this platform" not in log.splitlines()
        or "SARGE_SUITE_RESULT=0" not in log.splitlines()
    ):
        raise SystemExit("The Sarge examples failed")


def verify_examples(output, arch, parser):
    try:
        audit = json.loads((output / "elf-audit.json").read_text(encoding="utf-8"))
        binaries = {entry["binary"]: entry["sha256"] for entry in audit["binaries"]}
        actual = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in (output / "bin").iterdir() if p.is_file()}
    except (OSError, ValueError, KeyError, TypeError):
        parser.error(f"Build and audit the examples with make qt4-linux-{arch}-llvm-examples first")
    if "qt-selftest-cxx23" not in binaries or actual != binaries:
        parser.error("Exported examples do not match the ELF audit")


if __name__ == "__main__":
    if os.environ.get("SARGE_IN_QEMU_CONTAINER") == "1":
        run_guest()
    else:
        main()
