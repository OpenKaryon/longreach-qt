# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 4.8.7, the last Qt 4: Windows from 95 OSR2, Linux from Debian 3.1 Sarge,
# Mac OS X from 10.2 Jaguar (PowerPC) and 10.4 Tiger (Intel). Its own
# configure and qmake; nothing here is shared with the Qt 5 and 6 paths.
QT4_VERSION ?= 4.8.7
QT4_SERIES := $(basename $(QT4_VERSION))

# Qt's own archive: the Qt 5 mirror carries no Qt 4.
QT4_ARCHIVE := qt-everywhere-opensource-src-$(QT4_VERSION).tar.gz
QT4_ARCHIVE_PATH := $(DOWNLOAD_DIR)/$(QT4_ARCHIVE)
QT4_ARCHIVE_URL ?= https://download.qt.io/archive/qt/$(QT4_SERIES)/$(QT4_VERSION)/$(QT4_ARCHIVE)
QT4_ARCHIVE_SHA256 ?= e2882295097e47fe089f8ac741a95fef47e0a73a3f3cdf21b56990638f626ea0

QT4_WIN_AMD64_IMAGE := qt4-win-amd64

# Qt Mobility, Qt 4's add-on outside the source archive, pinned by commit.
QT_MOBILITY_COMMIT := fb3e9bc2d941462f1244aaf0ea79425a307f883d
QT_MOBILITY_ARCHIVE := qt-mobility-$(QT_MOBILITY_COMMIT).tar.xz
QT_MOBILITY_PATH := $(DOWNLOAD_DIR)/$(QT_MOBILITY_ARCHIVE)
QT_MOBILITY_URL := https://code.qt.io/qt-mobility/qt-mobility.git

.PHONY: download-qt4 download-qt4-openssl download-qt-mobility \
        qt4-linux-i386 qt4-linux-amd64 qt4-win-i386 qt4-win-amd64 \
        qt4-extract-tests qt4-package-tests

download-qt-mobility: $(QT_MOBILITY_PATH)

$(QT_MOBILITY_PATH):
	$(PYTHON) scripts/fetch/fetch-git-archive.py "$(QT_MOBILITY_URL)" "$(QT_MOBILITY_COMMIT)" "$@" qt-mobility

download-qt4: $(QT4_ARCHIVE_PATH)

$(QT4_ARCHIVE_PATH):
	$(PYTHON) scripts/fetch/fetch.py "$(QT4_ARCHIVE_URL)" "$@" "$(QT4_ARCHIVE_SHA256)"

QT4_BUILD_ARGS = --build-arg QT4_VERSION=$(QT4_VERSION) --build-arg OPENSSL_VERSION=$(OPENSSL_VERSION) --build-arg DOWNLOAD_DIR=$(DOWNLOAD_DIR) --build-arg PARALLEL_JOBS=$(PARALLEL_JOBS)

# 64-bit Windows starts at XP x64 and needs no backport.
qt4-win-amd64: $(QT4_ARCHIVE_PATH) $(OPENSSL_PATH)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(QT4_BUILD_ARGS) -f docker/qt4/windows/amd64/Dockerfile -t $(QT4_WIN_AMD64_IMAGE) .

# The test suite into artifacts/tests-<image>/: Windows i386 and Sarge build it
# against the installed SDK now, Windows amd64 copies /opt/qt4-smoke-bin out
# of the image.
#   make qt4-extract-tests QT4_IMAGE=qt4-win-amd64
QT4_IMAGE ?= $(QT4_WIN_AMD64_IMAGE)
QT4_TESTS_OUT = $(ARTIFACTS_DIR)/tests-$(QT4_IMAGE)

qt4-extract-tests:
	$(PYTHON) -c "import os, sys; os.makedirs(sys.argv[1], exist_ok=True)" "$(QT4_TESTS_OUT)"
	docker run --rm -v "$(CURDIR)/$(QT4_TESTS_OUT):/out" -v "$(CURDIR)/scripts:/scripts:ro" \
		$(QT4_IMAGE) "bash /scripts/tests/extract.sh /opt/qt4-smoke-bin"
	$(PYTHON) scripts/tests/write_manifest.py --out "$(QT4_TESTS_OUT)" --image "$(QT4_IMAGE)" \
		--qt-version "$(QT4_VERSION)" --openssl-version "$(OPENSSL_VERSION)" \
		--kind "qt4-build-kit-tests" --license-profile "lgpl-friendly"
	@echo "-> $(QT4_TESTS_OUT)"

# The suite as one tar.gz with its SHA256, to carry to another machine.
QT4_TESTS_PACKAGE := $(ARTIFACTS_DIR)/tests-$(QT4_IMAGE).tar.gz

qt4-package-tests: qt4-extract-tests
	docker run --rm -v "$(CURDIR)/$(ARTIFACTS_DIR):/artifacts" \
		--entrypoint bash $(QT4_IMAGE) -ec "tar -czf /artifacts/tests-$(QT4_IMAGE).tar.gz -C /artifacts/tests-$(QT4_IMAGE) . && sha256sum /artifacts/tests-$(QT4_IMAGE).tar.gz > /artifacts/tests-$(QT4_IMAGE).tar.gz.sha256"
	@echo "-> $(QT4_TESTS_PACKAGE)"

QT4_IMAGE_CONFIG = qt4=$(QT4_VERSION),$(QT4_ARCHIVE_URL);openssl=$(OPENSSL_VERSION),$(OPENSSL_URL);download=$(DOWNLOAD_DIR)

$(eval $(call simple-build-targets,qt4-win-amd64,qt4-win-amd64,QT4_WIN_AMD64_IMAGE,qt4-extract-tests,QT4_IMAGE=$(QT4_WIN_AMD64_IMAGE),QT4_IMAGE_CONFIG))
