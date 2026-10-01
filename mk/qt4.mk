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

QT4_WIN_I386_IMAGE := qt4-win-i386
QT4_WIN_AMD64_IMAGE := qt4-win-amd64
QT4_LINUX_I386_IMAGE := qt4-linux-i386
QT4_LINUX_AMD64_IMAGE := qt4-linux-amd64

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

# OpenSSL 1.0.2u, the last series that runs on Windows 95, Sarge and Tiger;
# Windows amd64 uses OPENSSL_VERSION (patches/qt4/all ports Qt to the 1.1 API).
QT4_OPENSSL_ARCHIVE := openssl-1.0.2u.tar.gz
QT4_OPENSSL_PATH := $(DOWNLOAD_DIR)/$(QT4_OPENSSL_ARCHIVE)
QT4_OPENSSL_URL ?= https://www.openssl.org/source/old/1.0.2/$(QT4_OPENSSL_ARCHIVE)
QT4_OPENSSL_SHA256 := ecd0c6ffb493dd06707d38b14bb4d8c2288bb7033735606569d8f90f89669d16

download-qt4-openssl: $(QT4_OPENSSL_PATH)

$(QT4_OPENSSL_PATH):
	$(PYTHON) scripts/fetch/fetch.py "$(QT4_OPENSSL_URL)" "$@" "$(QT4_OPENSSL_SHA256)"

$(QT4_ARCHIVE_PATH):
	$(PYTHON) scripts/fetch/fetch.py "$(QT4_ARCHIVE_URL)" "$@" "$(QT4_ARCHIVE_SHA256)"

QT4_BUILD_ARGS = --build-arg QT4_VERSION=$(QT4_VERSION) --build-arg OPENSSL_VERSION=$(OPENSSL_VERSION) --build-arg DOWNLOAD_DIR=$(DOWNLOAD_DIR) --build-arg PARALLEL_JOBS=$(PARALLEL_JOBS)

# Linux i386 and amd64 from the pinned Debian 3.1 Sarge packages.
qt4-linux-i386: $(QT4_ARCHIVE_PATH) $(QT4_OPENSSL_PATH)
	$(PYTHON) scripts/fetch/qt4-sarge-fetch.py --arch i386
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) --platform linux/386 --build-arg PARALLEL_JOBS=$(PARALLEL_JOBS) -f docker/qt4/linux/i386/Dockerfile -t $(QT4_LINUX_I386_IMAGE) .

qt4-linux-amd64: $(QT4_ARCHIVE_PATH) $(QT4_OPENSSL_PATH)
	$(PYTHON) scripts/fetch/qt4-sarge-fetch.py --arch amd64
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) --platform linux/amd64 --build-arg PARALLEL_JOBS=$(PARALLEL_JOBS) -f docker/qt4/linux/amd64/Dockerfile -t $(QT4_LINUX_AMD64_IMAGE) .

# Windows 95 OSR2 and later: the Win9x backport, one configure.
qt4-win-i386: $(QT4_ARCHIVE_PATH) $(QT4_OPENSSL_PATH)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) --build-arg PARALLEL_JOBS=$(PARALLEL_JOBS) -f docker/qt4/windows/i386/Dockerfile -t $(QT4_WIN_I386_IMAGE) .

# 64-bit Windows starts at XP x64 and needs no backport.
qt4-win-amd64: $(QT4_ARCHIVE_PATH) $(OPENSSL_PATH)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(QT4_BUILD_ARGS) -f docker/qt4/windows/amd64/Dockerfile -t $(QT4_WIN_AMD64_IMAGE) .

# The test suite into artifacts/tests-<image>/: Windows i386 and Sarge build it
# against the installed SDK now, Windows amd64 copies /opt/qt4-smoke-bin out
# of the image.
#   make qt4-extract-tests QT4_IMAGE=qt4-win-i386
QT4_IMAGE ?= $(QT4_WIN_I386_IMAGE)
QT4_TESTS_OUT = $(ARTIFACTS_DIR)/tests-$(QT4_IMAGE)

qt4-extract-tests:
ifeq ($(QT4_IMAGE),$(QT4_WIN_I386_IMAGE))
	$(PYTHON) scripts/build/qt4-win95-examples.py --image "$(QT4_IMAGE)" --out "$(QT4_TESTS_OUT)" --jobs "$(PARALLEL_JOBS)" $(if $(filter 1,$(QT4_BUILD_LOCK_HELD)),--lock-held,)
else ifeq ($(QT4_IMAGE),$(QT4_LINUX_I386_IMAGE))
	$(PYTHON) scripts/build/qt4-sarge-examples.py --arch i386 --image "$(QT4_IMAGE)" --out "$(QT4_TESTS_OUT)" --jobs "$(PARALLEL_JOBS)" $(if $(filter 1,$(QT4_BUILD_LOCK_HELD)),--lock-held,)
else ifeq ($(QT4_IMAGE),$(QT4_LINUX_AMD64_IMAGE))
	$(PYTHON) scripts/build/qt4-sarge-examples.py --arch amd64 --image "$(QT4_IMAGE)" --out "$(QT4_TESTS_OUT)" --jobs "$(PARALLEL_JOBS)" $(if $(filter 1,$(QT4_BUILD_LOCK_HELD)),--lock-held,)
else
	$(PYTHON) -c "import os, sys; os.makedirs(sys.argv[1], exist_ok=True)" "$(QT4_TESTS_OUT)"
	docker run --rm -v "$(CURDIR)/$(QT4_TESTS_OUT):/out" -v "$(CURDIR)/scripts:/scripts:ro" \
		$(QT4_IMAGE) "bash /scripts/tests/extract.sh /opt/qt4-smoke-bin"
	$(PYTHON) scripts/tests/write_manifest.py --out "$(QT4_TESTS_OUT)" --image "$(QT4_IMAGE)" \
		--qt-version "$(QT4_VERSION)" --openssl-version "$(OPENSSL_VERSION)" \
		--kind "qt4-build-kit-tests" --license-profile "lgpl-friendly"
	@echo "-> $(QT4_TESTS_OUT)"
endif

# The suite as one tar.gz with its SHA256, to carry to another machine.
QT4_TESTS_PACKAGE := $(ARTIFACTS_DIR)/tests-$(QT4_IMAGE).tar.gz

qt4-package-tests: qt4-extract-tests
	docker run --rm -v "$(CURDIR)/$(ARTIFACTS_DIR):/artifacts" \
		--entrypoint bash $(QT4_IMAGE) -ec "tar -czf /artifacts/tests-$(QT4_IMAGE).tar.gz -C /artifacts/tests-$(QT4_IMAGE) . && sha256sum /artifacts/tests-$(QT4_IMAGE).tar.gz > /artifacts/tests-$(QT4_IMAGE).tar.gz.sha256"
	@echo "-> $(QT4_TESTS_PACKAGE)"

QT4_IMAGE_CONFIG = qt4=$(QT4_VERSION),$(QT4_ARCHIVE_URL);openssl=$(OPENSSL_VERSION),$(OPENSSL_URL);download=$(DOWNLOAD_DIR)
QT4_WIN95_IMAGE_CONFIG = qt4=4.8.7;platform=win95-i386;openssl=1.0.2u,ecd0c6ffb493dd06707d38b14bb4d8c2288bb7033735606569d8f90f89669d16;download=downloads
QT4_SARGE_IMAGE_CONFIG = qt4=4.8.7;platform=debian-sarge-i386;glibc=2.3.2;openssl=1.0.2u;gcc-runtime=5.5.0;download=downloads
QT4_SARGE_AMD64_IMAGE_CONFIG = qt4=4.8.7;platform=debian-sarge-amd64;glibc=2.3.2;openssl=1.0.2u;gcc-runtime=5.5.0;download=downloads

$(eval $(call simple-build-targets,qt4-win-i386,qt4-win-i386,QT4_WIN_I386_IMAGE,qt4-extract-tests,QT4_IMAGE=$(QT4_WIN_I386_IMAGE) QT4_BUILD_LOCK_HELD=1,QT4_WIN95_IMAGE_CONFIG))
$(eval $(call simple-build-targets,qt4-win-amd64,qt4-win-amd64,QT4_WIN_AMD64_IMAGE,qt4-extract-tests,QT4_IMAGE=$(QT4_WIN_AMD64_IMAGE),QT4_IMAGE_CONFIG))
$(eval $(call simple-build-targets,qt4-linux-i386,qt4-linux-i386,QT4_LINUX_I386_IMAGE,qt4-extract-tests,QT4_IMAGE=$(QT4_LINUX_I386_IMAGE) QT4_BUILD_LOCK_HELD=1,QT4_SARGE_IMAGE_CONFIG))
$(eval $(call simple-build-targets,qt4-linux-amd64,qt4-linux-amd64,QT4_LINUX_AMD64_IMAGE,qt4-extract-tests,QT4_IMAGE=$(QT4_LINUX_AMD64_IMAGE) QT4_BUILD_LOCK_HELD=1,QT4_SARGE_AMD64_IMAGE_CONFIG))
