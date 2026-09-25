#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""
Qt 6 project builder - compile a CMake project against this kit's Qt 6 images.

This drives the images built from docker/qt6/. It is the Qt 6 counterpart to
`make qt5-extract-tests`, except that it builds *your* project rather than the
smoke suite: point it at a directory with a CMakeLists.txt and it configures,
compiles and copies the artifacts out of the container.

Usage:
    python scripts/build/qt6-build-project.py <platform> --project <path> [options]

Examples:
    python scripts/build/qt6-build-project.py win64 --project .
    python scripts/build/qt6-build-project.py linux64 --project /path/to/app --download
    python scripts/build/qt6-build-project.py macos-arm64 --project . --jobs 8

Paths are resolved against the repository root, so it can be run from anywhere.
"""

import argparse
import platform
import re
import subprocess
import sys
import urllib.request
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

# Image names match the Makefile's QT6_*_IMAGE variables, and the Dockerfile
# paths follow this repository's docker/<kit>/<platform>/<arch>/ layout. Keep
# both in step with the Makefile - the two entry points build the same images.
PLATFORM_CONFIG = {
    "win-amd64": {
        "image": "qt6-win-amd64-gpl-enabled",
        "qt_path": "/opt/qt6-amd64",
        "dockerfile": "docker/qt6/windows/amd64/Dockerfile",
        "artifact_pattern": "*.exe",
        "needs_host": True,
    },
    "win-arm64": {
        "image": "qt6-win-arm64-gpl-enabled",
        "qt_path": "/opt/qt6-arm64",
        "dockerfile": "docker/qt6/windows/arm64/Dockerfile",
        "artifact_pattern": "*.exe",
        "needs_host": True,
    },
    "linux-amd64": {
        "image": "qt6-linux-amd64",
        "qt_path": "/opt/qt6-linux-amd64",
        "dockerfile": "docker/qt6/linux/amd64/Dockerfile",
        "artifact_pattern": None,  # executables without extension
        "needs_host": False,
    },
    "linux-arm64": {
        "image": "qt6-linux-arm64",
        "qt_path": "/opt/qt6-linux-arm64",
        "dockerfile": "docker/qt6/linux/arm64/Dockerfile",
        "artifact_pattern": None,
        "needs_host": True,
    },
    "macos-amd64": {
        "image": "qt6-macos-amd64",
        "qt_path": "/opt/qt6-macos-amd64",
        "dockerfile": "docker/qt6/macos/amd64/Dockerfile",
        "artifact_pattern": "*.app",
        "needs_host": True,
    },
    "macos-arm64": {
        "image": "qt6-macos-arm64",
        "qt_path": "/opt/qt6-macos-arm64",
        "dockerfile": "docker/qt6/macos/arm64/Dockerfile",
        "artifact_pattern": "*.app",
        "needs_host": True,
    },
}

# Where downloaded build inputs live, matching DOWNLOAD_DIR in the Makefile.
DOWNLOAD_DIR = "downloads"

# Read from mk/qt6.mk rather than repeated here. Two copies of a version
# number drift, and the way they drift is silent: this script would go on
# downloading and naming one archive while `make qt6-*` built another.
def _qt6_version_from_makefile():
    makefile = Path(__file__).resolve().parents[2] / "mk" / "qt6.mk"
    try:
        text = makefile.read_text(encoding="utf-8")
    except OSError:
        return None
    m = re.search(r"^QT6_VERSION\s*\?=\s*(\S+)", text, re.MULTILINE)
    return m.group(1) if m else None


QT_VERSION = _qt6_version_from_makefile() or "6.8.4"
QT_SERIES = ".".join(QT_VERSION.split(".")[:2])
QT_ARCHIVE_NAME = f"qt-everywhere-src-{QT_VERSION}.tar.xz"
QT_DOWNLOAD_URL = (
    f"https://download.qt.io/archive/qt/{QT_SERIES}/{QT_VERSION}/single/{QT_ARCHIVE_NAME}"
)


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


def docker_image_exists(image_name: str) -> bool:
    """Check if a Docker image exists locally."""
    result = subprocess.run(
        ["docker", "images", "-q", image_name],
        capture_output=True,
        text=True,
    )
    return bool(result.stdout.strip())


def find_qt_archive(kit_dir: Path, download: bool) -> Path:
    """Find or download the Qt source archive.

    It has to end up in downloads/. That is the repository convention, and it
    is also the only place that works: .dockerignore excludes a top-level
    `/qt-everywhere-*.tar.xz`, so an archive left in the repository root never
    reaches the build context and the image build fails looking for it.
    """
    downloads_dir = kit_dir / DOWNLOAD_DIR
    archive_path = downloads_dir / QT_ARCHIVE_NAME
    if archive_path.exists():
        print(f"Found Qt archive: {archive_path}")
        return archive_path

    if not download:
        print_error(
            f"Qt source archive not found: {archive_path}\n\n"
            f"Options:\n"
            f"  1. Download manually from: {QT_DOWNLOAD_URL}\n"
            f"     and place it in: {downloads_dir}\n\n"
            f"  2. Use --download to fetch it automatically (~1.3GB):\n"
            f"     python scripts/build/qt6-build-project.py <platform> "
            f"--project <path> --download"
        )

    downloads_dir.mkdir(parents=True, exist_ok=True)

    # Download Qt archive
    print_step(f"Downloading Qt {QT_VERSION} (~1.3GB, this may take a while)...")
    print(f"URL: {QT_DOWNLOAD_URL}")
    print(f"Destination: {archive_path}")

    try:

        def progress_hook(block_num, block_size, total_size):
            downloaded = block_num * block_size
            if total_size > 0:
                percent = min(100, downloaded * 100 / total_size)
                mb_down = downloaded / (1024 * 1024)
                mb_total = total_size / (1024 * 1024)
                print(
                    f"\r  Progress: {percent:.1f}% ({mb_down:.0f}/{mb_total:.0f} MB)",
                    end="",
                    flush=True,
                )

        urllib.request.urlretrieve(QT_DOWNLOAD_URL, archive_path, progress_hook)
        print("\n  Download complete!")
        return archive_path

    except Exception as e:
        # Clean up partial download
        if archive_path.exists():
            archive_path.unlink()
        print_error(f"Failed to download Qt archive: {e}")


def build_qt_image(
    kit_dir: Path, platform_name: str, config: dict, qt_archive: Path, jobs: int
):
    """Build the Qt Docker image for the target platform."""
    image_name = config["image"]

    if docker_image_exists(image_name):
        print(f"Qt image already exists: {image_name}")
        return

    print_step(f"Building Qt image for {platform_name} (this takes 30-60 minutes)...")

    # Build host image first if needed
    if config["needs_host"] and not docker_image_exists("qt6-host"):
        print("Building host Qt image first...")
        cmd = [
            "docker",
            "build",
            "--build-arg",
            f"QT_VERSION={QT_VERSION}",
            "--build-arg",
            f"QT_ARCHIVE={qt_archive.name}",
        ]
        if jobs:
            cmd.extend(["--build-arg", f"PARALLEL_JOBS={jobs}"])
        cmd.extend(
            [
                "-f",
                str(kit_dir / "docker" / "qt6" / "host" / "Dockerfile"),
                "-t",
                "qt6-host",
                str(kit_dir),
            ]
        )
        result = subprocess.run(cmd)
        if result.returncode != 0:
            print_error("Failed to build host Qt image")

    # Build target platform image
    dockerfile = kit_dir / config["dockerfile"]
    cmd = [
        "docker",
        "build",
        "--build-arg",
        f"QT_VERSION={QT_VERSION}",
        "--build-arg",
        f"QT_ARCHIVE={qt_archive.name}",
    ]
    if jobs:
        cmd.extend(["--build-arg", f"PARALLEL_JOBS={jobs}"])
    cmd.extend(
        [
            "-f",
            str(dockerfile),
            "-t",
            image_name,
            str(kit_dir),
        ]
    )

    result = subprocess.run(cmd)
    if result.returncode != 0:
        print_error(f"Failed to build Qt image for {platform_name}")


def build_project(
    project_dir: Path, output_dir: Path, platform_name: str, config: dict
):
    """Build the user's project using the Qt Docker image."""
    print_step(f"Building project for {platform_name}...")

    image_name = config["image"]
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
  python scripts/build/qt6-build-project.py linux64 --project ../app --download
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
        "--download",
        action="store_true",
        help="Download Qt sources if not found locally (~1.3GB)",
    )
    parser.add_argument(
        "--jobs",
        "-j",
        type=int,
        default=0,
        help="Number of parallel build jobs (default: auto)",
    )
    parser.add_argument(
        "--rebuild-qt",
        action="store_true",
        help="Force rebuild of Qt Docker image",
    )

    args = parser.parse_args()

    # The repository root, two levels up from scripts/build/. It is both the
    # Docker build context and where downloads/ lives, so every path below is
    # relative to it rather than to the caller's working directory.
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

    # Check Docker
    print_step("Checking Docker...")
    check_docker()
    print("Docker is running.")

    if platform_name in ("win-amd64", "win-arm64"):
        # Both Windows variants use the Makefile's single canonical recipe per
        # architecture. In particular, amd64 must never fall back to the old
        # direct UCRT build, which did not include the Windows 7 backport.
        command = ["make", f"build-qt6-{platform_name}"]
        if args.jobs:
            command.append(f"PARALLEL_JOBS={args.jobs}")
        if args.rebuild_qt:
            command.append("NO_CACHE=1")
        if subprocess.run(command, cwd=kit_dir).returncode:
            print_error(f"Failed to prepare Qt image for {platform_name}")
    else:
        # Remove existing image if rebuild requested.
        if args.rebuild_qt and docker_image_exists(config["image"]):
            print(f"Removing existing image: {config['image']}")
            subprocess.run(["docker", "rmi", config["image"]], capture_output=True)
        if not docker_image_exists(config["image"]):
            qt_archive = find_qt_archive(kit_dir, args.download)
            build_qt_image(kit_dir, platform_name, config, qt_archive, args.jobs)
        else:
            print(f"\nUsing existing Qt image: {config['image']}")

    # Build the project
    build_project(project_dir, output_dir, platform_name, config)

    print_step("Build successful!")
    print(f"Artifacts are in: {output_dir}")


if __name__ == "__main__":
    main()
