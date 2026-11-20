#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

"""Stage each shared example with Qt's own Android dependency/QML deployer."""

import argparse
import json
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--abi", choices=("armeabi-v7a", "arm64-v8a"), default="armeabi-v7a")
    parser.add_argument("--repo", type=Path, default=Path("/repo"))
    parser.add_argument("--sdk", type=Path, default=None)
    parser.add_argument("--android-sdk", type=Path, default=Path("/work/android-sdk"))
    parser.add_argument("--build", type=Path, default=Path("/work/tests-qt5-android"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--apps", nargs="+")
    args = parser.parse_args()
    args.sdk = args.sdk or Path(f"/opt/qt5-android-{args.abi}-llvm")
    minimum, triple = {"armeabi-v7a": ("10", "arm-linux-androideabi"),
                       "arm64-v8a": ("21", "aarch64-linux-android")}[args.abi]
    expected = [line.strip() for line in (args.repo / "tests/expected-apps.txt").read_text().splitlines()
                if line.strip() and not line.lstrip().startswith("#")]
    expected.remove("smoke-runner")
    apps = args.apps or expected
    if any(app not in expected for app in apps):
        raise ValueError("Unknown shared example")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    ndk = Path("/opt/longreach-android/ndk")
    for app in apps:
        destination = output / app
        marker = destination / ".longreach-qt5-deployment"
        if destination.exists():
            if destination.resolve().parent != output or not marker.is_file():
                raise ValueError(f"Refusing to replace unowned deployment: {destination}")
            shutil.rmtree(destination)
        shutil.copytree(args.sdk / "src/android/templates", destination)
        marker.write_text(app + "\n")
        native = args.build / f"android-build/libs/{args.abi}" / f"lib{app}_{args.abi}.so"
        libraries = destination / f"libs/{args.abi}"
        libraries.mkdir(parents=True)
        shutil.copy2(native, libraries / native.name)
        # Scan only resources used by this Qt 5 build. The shared source
        # directory also contains Qt 4 QML and later-generation probe strings;
        # scanning it recursively deploys unrelated SDK module subtrees.
        scan_root = args.build / "android-qml-scan" / app
        scan_root.mkdir(parents=True, exist_ok=True)
        if app == "qt-selftest":
            (scan_root / "imports.qml").write_text("import QtQml 2.15\nQtObject {}\n")
        resources = sorted((args.build / app).glob("*.qrc"))
        source_resources = args.repo / "tests" / app / "qml.qrc"
        if app == "quick-qml-gallery":
            if not source_resources.is_file():
                raise FileNotFoundError(source_resources)
            resources.insert(0, source_resources)
        settings = {
            "_description": "Longreach shared example; native code and dependencies remain unchanged.",
            "application-binary": app,
            "architectures": {args.abi: triple},
            "android-min-sdk-version": minimum,
            "android-target-sdk-version": minimum,
            "ndk": str(ndk),
            "ndk-host": "linux-x86_64",
            "qml-root-path": str(scan_root),
            "qml-import-paths": str(args.build / app),
            "qrcFiles": ",".join(str(path) for path in resources),
            "qt": str(args.sdk),
            "sdk": str(args.android_sdk),
            "sdkBuildToolsRevision": "36.0.0",
            "stdcpp-path": str(ndk / "toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib"),
            "tool-prefix": "llvm",
            "toolchain-prefix": "llvm",
            "useLLVM": True,
        }
        configuration = destination / "deployment-settings.json"
        configuration.write_text(json.dumps(settings, indent=2) + "\n")
        subprocess.run([
            str(args.sdk / "bin/androiddeployqt"), "--input", str(configuration),
            "--output", str(destination), "--android-platform", "android-35",
            "--aux-mode", "--verbose",
        ], check=True)


if __name__ == "__main__":
    main()
