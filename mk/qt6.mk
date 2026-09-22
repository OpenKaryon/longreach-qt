# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 6.8.4 LTS: Windows from 7 SP1, Linux from RHEL/CentOS 7, macOS from 10.13
# (11.0 on Apple silicon). CMake-based, with its own Dockerfiles and patches.
#
# QT6_VERSION picks the patch release; QT6_SOURCE uses an archive of your own,
# such as a commercial LTS release that is not public yet:
#   make qt6-linux-amd64 QT6_VERSION=6.8.8 QT6_SOURCE=/path/to/qt-everywhere-src-6.8.8.tar.xz
QT6_VERSION ?= 6.8.4
QT6_SOURCE ?=
QT6_SERIES := $(basename $(QT6_VERSION))

QT6_HOST_IMAGE := qt6-host$(LICENSE_SUFFIX)

# Releases are published as qt-everywhere-src or -opensource-src;
# scripts/fetch/qt6-fetch-source.py finds the archive and stores it under this
# one name. The SHA256 is checked for the default version's public archive.
QT6_ARCHIVE := qt-everywhere-src-$(QT6_VERSION).tar.xz
QT6_ARCHIVE_SHA256 ?= $(if $(filter 6.8.4,$(QT6_VERSION)),1da37a32a583e7856d6fc13357c8ff6ad3ef7b877b8d276713b85026426d5246,)
QT6_ARCHIVE_PATH := $(DOWNLOAD_DIR)/$(QT6_ARCHIVE)

.PHONY: download-qt6 qt6-host \
        qt6-win-amd64 qt6-win-arm64 qt6-linux-amd64 qt6-linux-arm64 \
        qt6-macos-amd64 qt6-macos-arm64 \
        qt6-win-amd64-smoke qt6-win-amd64-audit qt6-win-arm64-smoke \
        qt6-linux-amd64-smoke qt6-linux-arm64-smoke \
        qt6-macos-amd64-smoke qt6-macos-amd64-audit qt6-macos-arm64-smoke qt6-macos-arm64-audit \
        qt6-host-smoke

download-qt6: $(QT6_ARCHIVE_PATH)

$(QT6_ARCHIVE_PATH):
	$(PYTHON) scripts/fetch/qt6-fetch-source.py "$(QT6_VERSION)" "$(DOWNLOAD_DIR)" $(if $(QT6_SOURCE),--source "$(QT6_SOURCE)",)
	$(if $(and $(QT6_ARCHIVE_SHA256),$(if $(QT6_SOURCE),,1)),$(PYTHON) scripts/fetch/fetch.py --check "$@" "$(QT6_ARCHIVE_SHA256)")

QT6_BUILD_ARGS = --build-arg QT_VERSION=$(QT6_VERSION) --build-arg QT_ARCHIVE=$(QT6_ARCHIVE) --build-arg DOWNLOAD_DIR=$(DOWNLOAD_DIR) --build-arg PARALLEL_JOBS=$(PARALLEL_JOBS) --build-arg LICENSE_PROFILE=$(LICENSE_PROFILE)

# Host Qt tools (moc, rcc, ...), which every cross target copies from this image.
qt6-host: $(QT6_ARCHIVE_PATH)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(QT6_BUILD_ARGS) -f docker/qt6/host/Dockerfile -t $(QT6_HOST_IMAGE) .

# A quick headless run of tests/ against the host image's Qt (no Qt 3D, so
# gl-heavy-gallery skips); qt6-linux-amd64-smoke is the full one.
qt6-host-smoke:
	docker run --rm --entrypoint sh 	    -v "$(CURDIR)/tests:/src:ro" 	    -v "$(CURDIR)/scripts/build/qt6-host-smoke.sh:/qt6-host-smoke.sh:ro" 	    $(QT6_HOST_IMAGE) -c "PARALLEL_JOBS=$(PARALLEL_JOBS) sh /qt6-host-smoke.sh"

QT6_IMAGE_CONFIG = qt6=$(QT6_VERSION);source=$(QT6_SOURCE);profile=$(LICENSE_PROFILE);llvm=$(LLVM_MINGW_VERSION),$(LLVM_MINGW_SHA256),$(QT6_WIN7_LLVM_MINGW_SHA256),$(LLVM_MINGW_URL),$(QT6_WIN7_LLVM_MINGW_URL);osx=$(QT6_MACOS_SDK_VERSION),$(QT6_MACOS_DEPLOYMENT_TARGET),$(QT6_MACOS_ARM64_SDK_VERSION),$(QT6_MACOS_ARM64_DEPLOYMENT_TARGET),$(QT6_MACOS_OSXCROSS_REF),$(QT6_MACOS_SDK_SHA256),$(QT6_MACOS_ARM64_SDK_SHA256),$(QT6_MACOS_SDK_URL),$(QT6_MACOS_ARM64_SDK_URL);download=$(DOWNLOAD_DIR)

