#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Write provenance for an extracted tests/ artifact directory."""

from __future__ import annotations

import argparse
import datetime as _dt
import hashlib
import json
import os
import platform
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_LICENSE_MATRIX = ROOT / "licenses" / "module-matrix.json"


def run_git(args: list[str]) -> str | None:
    try:
        return subprocess.check_output(["git", *args], text=True, stderr=subprocess.DEVNULL).strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def executable_files(out_dir: Path) -> list[dict[str, object]]:
    files: list[dict[str, object]] = []
    for path in sorted(out_dir.iterdir(), key=lambda p: p.name.lower()):
        if not path.is_file():
            continue
        if path.name == "manifest.json":
            continue
        if path.suffix.lower() == ".txt":
            continue
        if path.suffix and path.suffix.lower() != ".exe":
            continue
        files.append({
            "name": path.name,
            "size": path.stat().st_size,
            "sha256": sha256_file(path),
        })
    return files


def smoke_block(runner: str) -> dict[str, str]:
    """Describe how to run what was extracted.

    Only smoke-runner writes a report file and only its output is what
    docs/expected-smoke-warnings.md classifies, so naming either of those beside
    a different runner would point a reader at a file that will not be there.
    """
    block = {"runner": runner}
    if runner == "smoke-runner":
        block["report"] = "smoke-report.txt"
        block["expected_warnings"] = "docs/expected-smoke-warnings.md"
    return block


def license_block(profile: str, qt_version: str, matrix_path: Path,
                  binaries: list[dict[str, object]]) -> dict[str, object]:
    matrix = json.loads(matrix_path.read_text(encoding="utf-8"))
    applications = matrix["applications"]
    qt_major = qt_version.split(".", 1)[0]
    classified = {}
    for binary in binaries:
        name = Path(str(binary["name"])).stem
        if name in applications:
            item = dict(applications[name])
            if "profile_by_qt" in item:
                item["profile"] = item.pop("profile_by_qt")[qt_major]
                item["gpl_triggers"] = item.pop("gpl_triggers_by_qt")[qt_major]
            classified[name] = item
    return {
        "profile": profile,
        "matrix_schema": matrix["schema"],
        "notice": (
            "The repository's MIT license does not replace Qt module licenses. "
            "Classification is per linked executable; see docs/licensing.md."
        ),
        "applications": classified,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, help="artifact directory")
    parser.add_argument("--image", required=True, help="Docker image the tests were extracted from")
    parser.add_argument("--qt-version", required=True)
    parser.add_argument("--openssl-version", required=True)
    parser.add_argument("--manifest-name", default="manifest.json")
    # --kind names the kit that built the artifact. --runner keeps the report
    # file and expected-warnings document pointing at smoke-runner's.
    parser.add_argument("--kind", default="qt5-build-kit-tests")
    parser.add_argument("--runner", default="smoke-runner")
    parser.add_argument("--license-profile", choices=("lgpl-friendly", "gpl-enabled", "commercial-qt"),
                        default="gpl-enabled")
    parser.add_argument("--license-matrix", type=Path, default=DEFAULT_LICENSE_MATRIX)
    ns = parser.parse_args()

    out_dir = Path(ns.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    status = run_git(["status", "--porcelain"])
    binaries = executable_files(out_dir)
    manifest = {
        "schema": 1,
        "kind": ns.kind,
        "generated_at": _dt.datetime.now(_dt.timezone.utc).replace(microsecond=0).isoformat(),
        "image": ns.image,
        "qt_version": ns.qt_version,
        "openssl_version": ns.openssl_version,
        "git": {
            "commit": run_git(["rev-parse", "HEAD"]),
            "branch": run_git(["rev-parse", "--abbrev-ref", "HEAD"]),
            "dirty": bool(status),
        },
        "host": {
            "system": platform.system(),
            "release": platform.release(),
            "machine": platform.machine(),
        },
        "artifact": {
            "path": os.fspath(out_dir),
            "binaries": binaries,
        },
        "smoke": smoke_block(ns.runner),
        "licensing": license_block(ns.license_profile, ns.qt_version,
                                   ns.license_matrix, binaries),
    }

    target = out_dir / ns.manifest_name
    target.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"manifest written to {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
