# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Fingerprint compile inputs separately from target archives in retained Qt4 caches."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def compiler_inputs(runtime, mkspec, compiler="clang++-21"):
    executable = shutil.which(compiler)
    if not executable:
        raise ValueError("Missing compiler: " + compiler)
    executable = Path(executable).resolve()
    paths = [runtime / "target.sh", runtime / "bin/cxx", runtime / "bin/cc",
             mkspec / "qmake.conf", mkspec / "qplatformdefs.h"]
    result = {str(p): digest(p) for p in paths}
    result["compiler_executable"] = digest(executable)
    result["compiler_version"] = subprocess.check_output([str(executable), "--version"], text=True)
    # Header changes affect object ABI even if copied timestamps are older.
    for base in (runtime / "include", runtime / "sysroot/usr/include"):
        for p in sorted(base.rglob("*")):
            if p.is_file():
                result[str(p)] = digest(p)
    return result


def client_compile_inputs(prefix, runtime):
    result = compiler_inputs(runtime, prefix / "mkspecs/android-longreach-clang")
    for p in sorted((prefix / "include").rglob("*")):
        if p.is_file():
            result[str(p)] = digest(p)
    for tool in ("qmake", "moc", "rcc", "uic"):
        p = prefix / "bin" / tool
        if p.is_file():
            result[str(p)] = digest(p)
    return result


def needs_clean(saved, current):
    return not saved.is_file() or saved.read_text().strip() != current


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--mkspec", type=Path, required=True)
    args = parser.parse_args()
    print(fingerprint(compiler_inputs(args.runtime, args.mkspec)))


if __name__ == "__main__":
    main()
