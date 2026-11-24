# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Fingerprint compile inputs separately from target archives in retained Qt4 caches."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def tree_inputs(base):
    if not base.is_dir():
        raise ValueError("Missing cache input directory: " + str(base))
    files = {str(p): digest(p) for p in sorted(base.rglob("*")) if p.is_file()}
    if not files:
        raise ValueError("Empty cache input directory: " + str(base))
    return files


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
        result.update(tree_inputs(base))
    return result


def client_compile_inputs(prefix, runtime):
    result = compiler_inputs(runtime, prefix / "mkspecs/android-longreach-clang")
    result.update(tree_inputs(prefix / "include"))
    for tool in ("qmake", "moc", "rcc", "uic"):
        p = prefix / "bin" / tool
        if p.is_file():
            result[str(p)] = digest(p)
    return result


def client_link_inputs(runtime, archives, abi):
    # Hash the bytes incorporated by the wrapper as well as the SDK archives.
    # A producer report alone cannot detect a changed CRT, builtins or linker.
    result = {str(p): digest(p) for p in archives}
    result.update(tree_inputs(runtime / "lib"))
    platform = runtime / "sysroot/usr/lib"
    if abi in ("x86_64", "arm64-v8a"):
        triple = {"x86_64": "x86_64-linux-android", "arm64-v8a": "aarch64-linux-android"}[abi]
        platform = platform / triple / "21"
    elif abi != "x86":
        raise ValueError("Unsupported Qt4 installed-SDK ABI: " + abi)
    result.update(tree_inputs(platform))
    for name in ("target.sh", "bin/cxx", "bin/cc"):
        p = runtime / name
        result[str(p)] = digest(p)
    compiler = shutil.which("clang++-21")
    if not compiler:
        raise ValueError("Missing compiler: clang++-21")
    compiler = Path(compiler).resolve()
    linker = compiler.parent / "ld.lld"
    if not linker.is_file():
        raise ValueError("Missing compiler-adjacent linker: " + str(linker))
    result["linker_executable"] = digest(linker.resolve())
    return result


COMPILE_VARIABLES = ("CC", "CXX", "DEFINES", "CFLAGS", "CXXFLAGS", "INCPATH")


def makefile_compile_inputs(text):
    # qmake emits these expanded assignments even when their values are empty.
    # Ignore generation dates and link-only variables to retain useful objects.
    text = re.sub(r"[ \t]*\\\r?\n[ \t]*", " ", text)
    result = {}
    for line in text.splitlines():
        match = re.match(r"^([A-Za-z_][A-Za-z_0-9]*)\s*=\s*(.*)$", line)
        if match and match[1] in COMPILE_VARIABLES:
            result[match[1]] = match[2].strip()
    missing = set(COMPILE_VARIABLES) - result.keys()
    if missing:
        raise ValueError("Missing qmake compile assignments: " + ", ".join(sorted(missing)))
    return result


def makefile_link_inputs(text):
    text = re.sub(r"[ \t]*\\\r?\n[ \t]*", " ", text)
    result = {}
    for line in text.splitlines():
        match = re.match(r"^(LINK|LFLAGS|LIBS)\s*=\s*(.*)$", line)
        if match:
            result[match[1]] = match[2].strip()
    if set(result) != {"LINK", "LFLAGS", "LIBS"}:
        raise ValueError("Missing qmake link assignments")
    return result


def build_client(directory, profile, qmake_command, compile_inputs, link_inputs, jobs, run):
    # Evaluate .pro/.pri/features first. A newly generated Makefile is not an
    # object dependency in qmake builds, so flag changes require an explicit clean.
    run(qmake_command, directory)
    text = (directory / "Makefile").read_text()
    compile_key = fingerprint([compile_inputs, makefile_compile_inputs(text)])
    link_key = fingerprint([link_inputs, makefile_link_inputs(text)])
    saved_compile = directory / ".longreach-sdk-compile-inputs"
    saved_link = directory / ".longreach-sdk-link-inputs"
    if needs_clean(saved_compile, compile_key):
        run(["make", "clean"], directory)
    if needs_clean(saved_link, link_key):
        for output in directory.glob("lib" + profile + ".so*"):
            output.unlink()
    run(["make", f"-j{jobs}"], directory)
    # Keep previous identities if compilation/linking fails; the next attempt
    # must still perform the necessary clean/relink.
    saved_compile.write_text(compile_key + "\n")
    saved_link.write_text(link_key + "\n")


def needs_clean(saved, current):
    return not saved.is_file() or saved.read_text().strip() != current


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--mkspec", type=Path, required=True)
    parser.add_argument("--client-project", type=Path)
    parser.add_argument("--prefix", type=Path)
    parser.add_argument("--profile", default="core")
    parser.add_argument("--abi", choices=("x86", "x86_64", "arm64-v8a"))
    parser.add_argument("--jobs", type=int, default=2)
    args = parser.parse_args()
    if args.client_project:
        if not args.prefix or not args.abi or args.jobs < 1:
            parser.error("Client build requires --prefix, --abi and positive --jobs")
        lease_spec = importlib.util.spec_from_file_location('qt4_core_cache_lease', Path(__file__).with_name('client-cache-lock.py'))
        lease_module = importlib.util.module_from_spec(lease_spec)
        lease_spec.loader.exec_module(lease_module)
        with lease_module.CacheLease(Path('/work')) as client_lease:
            compile_key = fingerprint(client_compile_inputs(args.prefix, args.runtime))
            archives = sorted((args.prefix / "lib").glob("libQt*.a"))
            if not archives:
                raise ValueError("Installed SDK has no Qt archives")
            link_key = fingerprint(client_link_inputs(args.runtime, archives, args.abi))
            project = args.client_project.resolve()
            def run(arguments, directory):
                subprocess.run(list(map(str, arguments)), cwd=directory, check=True, env=client_lease.child_environment(), **client_lease.child_options())
            build_client(project.parent, args.profile,
                         [args.prefix / "bin/qmake", "-spec", args.mkspec, project],
                         compile_key, link_key, args.jobs, run)
    else:
        print(fingerprint(compiler_inputs(args.runtime, args.mkspec)))


if __name__ == "__main__":
    main()
