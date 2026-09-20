# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 5.15.19: Windows from XP SP3, macOS from 10.7.
# Images are qt5-<os>-<arch>-<licence profile>.

QT5_VERSION ?= 5.15.19
QT5_SERIES := $(basename $(QT5_VERSION))

QT5_WIN_I386_IMAGE := qt5-win-i386$(LICENSE_SUFFIX)
QT5_WIN_AMD64_IMAGE := qt5-win-amd64$(LICENSE_SUFFIX)
QT5_WIN_ARM64_IMAGE := qt5-win-arm64$(LICENSE_SUFFIX)
QT5_MACOS_AMD64_IMAGE := qt5-macos-amd64$(LICENSE_SUFFIX)
QT5_MACOS_ARM64_IMAGE := qt5-macos-arm64$(LICENSE_SUFFIX)

# One source archive for every image. Another version needs its SHA256 too.
QT5_ARCHIVE := qt-everywhere-opensource-src-$(QT5_VERSION).tar.xz
QT5_ARCHIVE_PATH := $(DOWNLOAD_DIR)/$(QT5_ARCHIVE)
QT5_ARCHIVE_URL ?= https://qt.mirror.constant.com/archive/qt/$(QT5_SERIES)/$(QT5_VERSION)/single/$(QT5_ARCHIVE)
QT5_ARCHIVE_SHA256 ?= 173c2326dae138bbb0d98921e9d911e55c00163d93a6db29f294b5e19ff306ae

# Desktop OpenGL, which works on XP; for example QT5_OPENGL_CONFIG=-no-opengl.
QT5_OPENGL_CONFIG ?= -opengl desktop

# The macOS SDK, from Apple's software-update CDN (the package MacPorts uses),
# unpacked by scripts/fetch/fetch-macos-sdk.sh and never redistributed. A
# tarball of your own (osxcross' gen_sdk_package.sh) in downloads/ is used as is:
#   make qt5-macos-amd64 QT5_MACOS_SDK=MacOSX12.3.sdk.tar.xz
# The SDK only decides what can be compiled against; how old a system the
# result runs on is the deployment target below. The package holds macOS
# 11.3.1 in a directory named MacOSX11.3.sdk, which osxcross keys off.
QT5_MACOS_SDK ?= MacOSX11.3.sdk.tar.xz
QT5_MACOS_SDK_PATH := $(DOWNLOAD_DIR)/$(QT5_MACOS_SDK)
QT5_MACOS_SDK_DIR := $(basename $(basename $(QT5_MACOS_SDK)))
QT5_MACOS_SDK_PKG_URL ?= https://swcdn.apple.com/content/downloads/52/17/002-41708-A_E8MFK7B2PK/6p55tbmh0qttgbt4cy94uuvnacy6tkw435/CLTools_macOSLMOS_SDK.pkg
QT5_MACOS_SDK_PKG_SHA256 ?= b075d3d2f3b066607209a5bbf7cf727a40b98fe65629c5b6abc17f156897af4a

# Oldest macOS the binaries load on.
QT5_MACOS_TARGET_AMD64 ?= 10.7
QT5_MACOS_TARGET_ARM64 ?= 11.0

QT5_MACOS_BUILD_ARGS = $(QT5_BUILD_ARGS) --build-arg OSXCROSS_REPO="$(OSXCROSS_REPO)" --build-arg OSXCROSS_REF="$(OSXCROSS_REF)"

QT5_BUILD_ARGS = --build-arg QT_FULL_VERSION=$(QT5_VERSION) --build-arg OPENSSL_VERSION=$(OPENSSL_VERSION) --build-arg PARALLEL_JOBS=$(PARALLEL_JOBS) --build-arg DOWNLOAD_DIR=$(DOWNLOAD_DIR) --build-arg LICENSE_PROFILE=$(LICENSE_PROFILE)
QT5_WINDOWS_BUILD_ARGS = $(QT5_BUILD_ARGS) --build-arg QT_OPENGL_CONFIG="$(QT5_OPENGL_CONFIG)"

QT5_INPUTS := $(QT5_ARCHIVE_PATH)

.PHONY: download-qt5 download-qt5-macos-sdk download-qt5-llvm-src download-qt5-macos-i386-link-sdk \
        qt5-win-i386 qt5-win-amd64 qt5-win-arm64 qt5-linux-i386 qt5-linux-amd64 qt5-linux-arm64 \
        qt5-macos-amd64 qt5-macos-arm64 qt5-macos-i386 qt5-extract-tests qt5-package-tests

download-qt5: $(QT5_ARCHIVE_PATH)

$(QT5_ARCHIVE_PATH):
	$(PYTHON) scripts/fetch/fetch.py "$(QT5_ARCHIVE_URL)" "$@" "$(QT5_ARCHIVE_SHA256)"

# Windows: the XP backport; one binary takes the newer paths at run time up to
# Windows 11.
qt5-win-i386: $(QT5_INPUTS) $(OPENSSL_PATH)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(QT5_WINDOWS_BUILD_ARGS) -f docker/qt5/windows/i386/Dockerfile -t $(QT5_WIN_I386_IMAGE) .

qt5-win-amd64: $(QT5_INPUTS) $(OPENSSL_PATH)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(QT5_WINDOWS_BUILD_ARGS) -f docker/qt5/windows/amd64/Dockerfile -t $(QT5_WIN_AMD64_IMAGE) .

# Windows on ARM starts at Windows 10; the same patches apply.
qt5-win-arm64: $(QT5_INPUTS) $(LLVM_MINGW_PATH)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(QT5_BUILD_ARGS) --build-arg QT_OPENGL_CONFIG="$(QT5_OPENGL_CONFIG)" --build-arg LLVM_MINGW_ARCHIVE="$(LLVM_MINGW_ARCHIVE)" --build-arg LLVM_MINGW_SHA256="$(LLVM_MINGW_SHA256)" -f docker/qt5/windows/arm64/Dockerfile -t $(QT5_WIN_ARM64_IMAGE) .

qt5-macos-amd64: $(QT5_INPUTS) $(QT5_MACOS_SDK_PATH) $(OPENSSL_PATH)
	@echo "Using SDK $(QT5_MACOS_SDK), deployment target $(QT5_MACOS_TARGET_AMD64)"
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(QT5_MACOS_BUILD_ARGS) --build-arg OSX_SDK="$(QT5_MACOS_SDK)" --build-arg MACOS_DEPLOYMENT_TARGET="$(QT5_MACOS_TARGET_AMD64)" -f docker/qt5/macos/amd64/Dockerfile -t $(QT5_MACOS_AMD64_IMAGE) .

qt5-macos-arm64: $(QT5_INPUTS) $(QT5_MACOS_SDK_PATH)
	@echo "Using SDK $(QT5_MACOS_SDK), deployment target $(QT5_MACOS_TARGET_ARM64)"
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(QT5_MACOS_BUILD_ARGS) --build-arg OSX_SDK="$(QT5_MACOS_SDK)" --build-arg MACOS_DEPLOYMENT_TARGET="$(QT5_MACOS_TARGET_ARM64)" -f docker/qt5/macos/arm64/Dockerfile -t $(QT5_MACOS_ARM64_IMAGE) .

# Unpacked in a container: the SDK is thousands of symlinks a Windows
# filesystem cannot hold. The command is one `bash -c` string so that Git Bash
# does not rewrite /scripts/... into a Windows path.
download-qt5-macos-sdk: $(QT5_MACOS_SDK_PATH)

$(QT5_MACOS_SDK_PATH):
	$(PYTHON) -c "import os, sys; os.makedirs(sys.argv[1], exist_ok=True)" "$(DOWNLOAD_DIR)"
	docker run --rm -v "$(CURDIR):/work" -v "$(CURDIR)/scripts:/scripts:ro" \
		-e SDK_TARBALL="$(QT5_MACOS_SDK_PATH)" -e SDK_DIR="$(QT5_MACOS_SDK_DIR)" \
		-e SDK_PKG_URL="$(QT5_MACOS_SDK_PKG_URL)" -e SDK_PKG_SHA256="$(QT5_MACOS_SDK_PKG_SHA256)" \
		ubuntu:22.04 bash -c "bash /scripts/fetch/fetch-macos-sdk.sh"

# Copy an image's test suite to artifacts/tests-<image>/, with the same
# LICENSE_PROFILE as its build:
#   make qt5-extract-tests QT5_IMAGE=qt5-macos-amd64-gpl-enabled
QT5_IMAGE ?= $(QT5_WIN_I386_IMAGE)
QT5_TESTS_OUT := $(ARTIFACTS_DIR)/tests-$(QT5_IMAGE)
QT5_TESTS_PACKAGE := $(ARTIFACTS_DIR)/tests-$(QT5_IMAGE).tar.gz

qt5-extract-tests:
	$(PYTHON) -c "import os, sys; os.makedirs(sys.argv[1], exist_ok=True)" "$(QT5_TESTS_OUT)"
	docker run --rm -v "$(CURDIR)/$(QT5_TESTS_OUT):/out" -v "$(CURDIR)/scripts:/scripts:ro" \
		$(QT5_IMAGE) "bash /scripts/tests/extract.sh"
	$(PYTHON) scripts/tests/write_manifest.py --out "$(QT5_TESTS_OUT)" --image "$(QT5_IMAGE)" --qt-version "$(QT5_VERSION)" --openssl-version "$(OPENSSL_VERSION)" --license-profile "$(LICENSE_PROFILE)"
	@echo "-> $(QT5_TESTS_OUT)"

qt5-package-tests: qt5-extract-tests
	docker run --rm -v "$(CURDIR)/$(ARTIFACTS_DIR):/artifacts" \
		$(QT5_IMAGE) "tar -czf /artifacts/tests-$(QT5_IMAGE).tar.gz -C /artifacts/tests-$(QT5_IMAGE) . && sha256sum /artifacts/tests-$(QT5_IMAGE).tar.gz > /artifacts/tests-$(QT5_IMAGE).tar.gz.sha256"
	@echo "-> $(QT5_TESTS_PACKAGE)"

QT5_IMAGE_CONFIG = qt5=$(QT5_VERSION),$(QT5_ARCHIVE_URL);openssl=$(OPENSSL_VERSION),$(OPENSSL_URL);profile=$(LICENSE_PROFILE);opengl=$(QT5_OPENGL_CONFIG);llvm=$(LLVM_MINGW_VERSION),$(LLVM_MINGW_ARCHIVE),$(LLVM_MINGW_SHA256),$(LLVM_MINGW_URL);osx=$(QT5_MACOS_SDK),$(QT5_MACOS_TARGET_AMD64),$(QT5_MACOS_TARGET_ARM64),$(OSXCROSS_REPO),$(OSXCROSS_REF),$(QT5_MACOS_SDK_PKG_URL),$(QT5_MACOS_SDK_PKG_SHA256),$(QT5_LLVM_SRC_VERSION),$(QT5_LLVM_SRC_SHA256),$(QT5_MACOS_I386_LINK_SDK_SHA256);download=$(DOWNLOAD_DIR)

$(eval $(call simple-build-targets,qt5-win-i386,qt5-win-i386,QT5_WIN_I386_IMAGE,qt5-extract-tests,QT5_IMAGE=$(QT5_WIN_I386_IMAGE),QT5_IMAGE_CONFIG))
$(eval $(call simple-build-targets,qt5-win-amd64,qt5-win-amd64,QT5_WIN_AMD64_IMAGE,qt5-extract-tests,QT5_IMAGE=$(QT5_WIN_AMD64_IMAGE),QT5_IMAGE_CONFIG))
$(eval $(call simple-build-targets,qt5-win-arm64,qt5-win-arm64,QT5_WIN_ARM64_IMAGE,qt5-extract-tests,QT5_IMAGE=$(QT5_WIN_ARM64_IMAGE),QT5_IMAGE_CONFIG))
$(eval $(call simple-build-targets,qt5-macos-amd64,qt5-macos-amd64,QT5_MACOS_AMD64_IMAGE,qt5-extract-tests,QT5_IMAGE=$(QT5_MACOS_AMD64_IMAGE),QT5_IMAGE_CONFIG))
$(eval $(call simple-build-targets,qt5-macos-arm64,qt5-macos-arm64,QT5_MACOS_ARM64_IMAGE,qt5-extract-tests,QT5_IMAGE=$(QT5_MACOS_ARM64_IMAGE),QT5_IMAGE_CONFIG))
