#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Report the effective open-source profile of SDK modules or smoke apps."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MATRIX = ROOT / "licenses" / "module-matrix.json"
RANK = {"lgpl-friendly": 0, "gpl-enabled": 1, "commercial-qt": 1}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("names", nargs="*", help="module or smoke-application names")
    parser.add_argument("--profile", choices=tuple(RANK), help="check names against this profile")
    parser.add_argument("--qt", choices=("4", "5", "6"), default="6",
                        help="Qt generation for per-application classification (default: 6)")
    parser.add_argument("--json", action="store_true", help="emit JSON")
    ns = parser.parse_args()

    data = json.loads(MATRIX.read_text(encoding="utf-8"))
    modules = data["modules"]
    applications = data["applications"]
    names = ns.names or sorted(applications)
    rows = []
    unknown = []

    for name in names:
        if name in modules:
            item = modules[name]
            rows.append({"name": name, "kind": "module", **item})
        elif name in applications:
            item = dict(applications[name])
            if "profile_by_qt" in item:
                item["profile"] = item.pop("profile_by_qt")[ns.qt]
                item["gpl_triggers"] = item.pop("gpl_triggers_by_qt")[ns.qt]
            rows.append({"name": name, "kind": "application", **item})
        else:
            unknown.append(name)

    if unknown:
        parser.error("unknown module/application: " + ", ".join(unknown))

    violations = []
    if ns.profile == "lgpl-friendly":
        violations = [row["name"] for row in rows if row["profile"] == "gpl-enabled"]

    result = {"qt": ns.qt, "requested_profile": ns.profile, "items": rows, "violations": violations}
    if ns.json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
    else:
        for row in rows:
            detail = row.get("oss", ", ".join(row.get("gpl_triggers", [])) or "no GPL-only module")
            print(f"{row['name']:<28} {row['profile']:<14} {detail}")
        if violations:
            print("\nERROR: GPL-only items are not permitted by profile lgpl-friendly:")
            for name in violations:
                print(f"  {name}")

    return 2 if violations else 0


if __name__ == "__main__":
    raise SystemExit(main())
