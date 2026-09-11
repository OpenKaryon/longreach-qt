# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 5.15.19: Windows from XP SP3.
# Images are qt5-<os>-<arch>-<licence profile>.

QT5_VERSION ?= 5.15.19
QT5_SERIES := $(basename $(QT5_VERSION))

QT5_WIN_I386_IMAGE := qt5-win-i386$(LICENSE_SUFFIX)
QT5_WIN_AMD64_IMAGE := qt5-win-amd64$(LICENSE_SUFFIX)

# One source archive for every image. Another version needs its SHA256 too.
QT5_ARCHIVE := qt-everywhere-opensource-src-$(QT5_VERSION).tar.xz
QT5_ARCHIVE_PATH := $(DOWNLOAD_DIR)/$(QT5_ARCHIVE)
QT5_ARCHIVE_URL ?= https://qt.mirror.constant.com/archive/qt/$(QT5_SERIES)/$(QT5_VERSION)/single/$(QT5_ARCHIVE)
QT5_ARCHIVE_SHA256 ?= 173c2326dae138bbb0d98921e9d911e55c00163d93a6db29f294b5e19ff306ae

# Desktop OpenGL, which works on XP; for example QT5_OPENGL_CONFIG=-no-opengl.
QT5_OPENGL_CONFIG ?= -opengl desktop

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
