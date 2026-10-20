#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""
Qt 6 project builder - compile a CMake project against this kit's Qt 6 images.

This drives the images built from docker/qt6/. It is the Qt 6 counterpart to
`make qt5-extract-tests`, except that it builds *your* project rather than the
smoke suite: point it at a directory with a CMakeLists.txt and it configures,
compiles and copies the artifacts out of the container. The Qt image itself
comes from `make build-qt6-<platform>`, which fetches every input with its
pinned SHA256 and rebuilds the image only when those changed.

Usage:
    python scripts/build/qt6-build-project.py <platform> --project <path> [options]

Examples:
    python scripts/build/qt6-build-project.py win64 --project .
    python scripts/build/qt6-build-project.py linux64 --project /path/to/app
    python scripts/build/qt6-build-project.py macos-arm64 --project . --jobs 8

--project and --output are relative to the current directory; the kit is
found from this script's own path, so it can be run from anywhere.
"""

import argparse
import os
import platform
import subprocess
import sys
from pathlib import Path

# Platform aliases and configurations
PLATFORMS = {
    # Aliases -> canonical names
    "win64": "win-amd64",
    "win-amd64": "win-amd64",
    "win-arm64": "win-arm64",
    "linux64": "linux-amd64",
    "linux-amd64": "linux-amd64",
    "linux-arm64": "linux-arm64",
    "macos64": "macos-amd64",
    "macos-amd64": "macos-amd64",
    "macos-arm64": "macos-arm64",
}

# Image names match mk/qt6.mk's QT6_*_IMAGE variables for the default licence
# profile; another profile adds -<profile>, as there.
PLATFORM_CONFIG = {
    "win-amd64": {
        "image": "qt6-win-amd64",
        "qt_path": "/opt/qt6-amd64",
        "artifact_pattern": "*.exe",
    },
    "win-arm64": {
        "image": "qt6-win-arm64",
        "qt_path": "/opt/qt6-arm64",
        "artifact_pattern": "*.exe",
    },
    "linux-amd64": {
        "image": "qt6-linux-amd64",
        "qt_path": "/opt/qt6-linux-amd64",
        "artifact_pattern": None,  # executables without extension
    },
    "linux-arm64": {
        "image": "qt6-linux-arm64",
        "qt_path": "/opt/qt6-linux-arm64",
        "artifact_pattern": None,
    },
    "macos-amd64": {
        "image": "qt6-macos-amd64",
        "qt_path": "/opt/qt6-macos-amd64",
        "artifact_pattern": "*.app",
    },
    "macos-arm64": {
        "image": "qt6-macos-arm64",
        "qt_path": "/opt/qt6-macos-arm64",
        "artifact_pattern": "*.app",
    },
}

def print_step(msg: str):
    """Print a formatted step message."""
    print(f"\n{'=' * 60}")
    print(f"  {msg}")
    print(f"{'=' * 60}\n")


def print_error(msg: str):
    """Print an error message and exit."""
    print(f"\n[ERROR] {msg}\n", file=sys.stderr)
    sys.exit(1)


def check_docker():
    """Verify Docker is installed and running."""
    try:
        result = subprocess.run(
            ["docker", "info"],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode != 0:
            print_error(
                "Docker is not running. Please start Docker and try again.\n"
                f"Details: {result.stderr}"
            )
    except FileNotFoundError:
        print_error(
            "Docker is not installed. Please install Docker:\n"
            "  - Windows/macOS: https://www.docker.com/products/docker-desktop\n"
            "  - Linux: https://docs.docker.com/engine/install/"
        )
    except subprocess.TimeoutExpired:
        print_error("Docker is not responding. Please restart Docker and try again.")


def build_project(
    project_dir: Path, output_dir: Path, platform_name: str, config: dict, image_name: str
):
    """Build the user's project using the Qt Docker image."""
    print_step(f"Building project for {platform_name}...")

    qt_path = config["qt_path"]

    # Create output directory
    output_dir.mkdir(parents=True, exist_ok=True)

    # Convert paths for Docker (handle Windows paths)
    if platform.system() == "Windows":
        # Convert Windows paths to Docker-compatible format
        project_mount = project_dir.as_posix()
        output_mount = output_dir.as_posix()
    else:
        project_mount = str(project_dir)
        output_mount = str(output_dir)

    # Build command - compile project and copy artifacts
    if config["artifact_pattern"] == "*.exe":
        find_cmd = 'find /tmp/build -name "*.exe" ! -name "a.exe" -exec cp {} /out/ \\;'
    elif config["artifact_pattern"] == "*.app":
        find_cmd = 'find /tmp/build -maxdepth 1 -name "*.app" -exec cp -r {} /out/ \\;'
    else:
        # Linux executables (no extension)
        find_cmd = 'find /tmp/build -maxdepth 1 -type f -executable ! -name "*.so" ! -name "*.a" -exec cp {} /out/ \\;'

    build_script = f"""
        set -e
        echo "Configuring project..."
        mkdir -p /tmp/build
        cd /tmp/build
        {qt_path}/bin/qt-cmake -G Ninja -DCMAKE_BUILD_TYPE=Release /src
        echo "Building project..."
        cmake --build .
        echo "Copying artifacts..."
        {find_cmd}
        echo "Build complete!"
        ls -la /out/
    """

    cmd = [
        "docker",
        "run",
        "--rm",
        "-v",
        f"{project_mount}:/src:ro",
        "-v",
        f"{output_mount}:/out",
        image_name,
        "bash",
        "-c",
        build_script,
    ]

    result = subprocess.run(cmd)
    if result.returncode != 0:
        print_error(f"Build failed for {platform_name}")

    print(f"\nArtifacts saved to: {output_dir}")


def main():
    parser = argparse.ArgumentParser(
        description="Longreach Qt - Cross-platform Qt project builder",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Supported platforms:
  win64, win-amd64      Windows x86_64
  win-arm64             Windows ARM64
  linux64, linux-amd64  Linux x86_64
  linux-arm64           Linux ARM64
  macos64, macos-amd64  macOS x86_64
  macos-arm64           macOS ARM64

Examples:
  python scripts/build/qt6-build-project.py win64 --project .
  python scripts/build/qt6-build-project.py linux64 --project ../app
  python scripts/build/qt6-build-project.py macos-arm64 --project . --output ./dist
        """,
    )

    parser.add_argument(
        "platform",
        choices=list(PLATFORMS.keys()),
        help="Target platform to build for",
    )
    parser.add_argument(
        "--project",
        "-p",
        required=True,
        help="Path to the project directory containing CMakeLists.txt",
    )
    parser.add_argument(
        "--output",
        "-o",
        help="Output directory for artifacts (default: <project>/build/<platform>)",
    )
    parser.add_argument(
        "--jobs",
        "-j",
        type=int,
        default=0,
        help="Number of parallel build jobs (default: auto)",
    )
    parser.add_argument(
        "--license-profile",
        choices=["gpl-enabled", "lgpl-friendly", "commercial-qt"],
        default=os.environ.get("LICENSE_PROFILE", "gpl-enabled"),
        help="the Qt image's licence profile, as make's LICENSE_PROFILE (default: gpl-enabled)",
    )
    parser.add_argument(
        "--rebuild-qt",
        action="store_true",
        help="Force rebuild of Qt Docker image",
    )

    args = parser.parse_args()

    # The repository root, two levels up from scripts/build/, where make runs.
    # The project and output paths are the caller's, relative to its directory.
    kit_dir = Path(__file__).resolve().parents[2]
    project_dir = Path(args.project).resolve()

    # Validate project directory
    if not project_dir.exists():
        print_error(f"Project directory does not exist: {project_dir}")

    cmake_file = project_dir / "CMakeLists.txt"
    if not cmake_file.exists():
        print_error(f"CMakeLists.txt not found in: {project_dir}")

    # Resolve platform
    platform_name = PLATFORMS[args.platform]
    config = PLATFORM_CONFIG[platform_name]
    profile = args.license_profile
    image_name = config["image"] + ("" if profile == "gpl-enabled" else f"-{profile}")

    # Determine output directory
    if args.output:
        output_dir = Path(args.output).resolve()
    else:
        output_dir = project_dir / "build" / platform_name

    print("Longreach Qt")
    print(f"  Platform:   {platform_name}")
    print(f"  Project:    {project_dir}")
    print(f"  Output:     {output_dir}")
    print(f"  Kit:        {kit_dir}")
    print(f"  Image:      {image_name}")

    # Check Docker
    print_step("Checking Docker...")
    check_docker()
    print("Docker is running.")

    # Every platform through the Makefile's recipe: it fetches the inputs the
    # Dockerfile copies, checks their SHA256, builds qt6-host where needed and
    # skips an image whose inputs have not changed.
    print_step(f"Preparing the Qt image (make build-qt6-{platform_name})...")
    command = ["make", f"build-qt6-{platform_name}", f"LICENSE_PROFILE={profile}"]
    if args.jobs:
        command.append(f"PARALLEL_JOBS={args.jobs}")
    if args.rebuild_qt:
        command.append("NO_CACHE=1")
    if subprocess.run(command, cwd=kit_dir).returncode:
        print_error(f"Failed to prepare Qt image for {platform_name}")

    # Build the project
    build_project(project_dir, output_dir, platform_name, config, image_name)

    print_step("Build successful!")
    print(f"Artifacts are in: {output_dir}")


if __name__ == "__main__":
    main()
