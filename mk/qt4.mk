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
QT4_MACOS_I386_IMAGE := qt4-macos-i386
QT4_MACOS_PPC_IMAGE := qt4-macos-ppc

.PHONY: download-qt4 download-qt4-openssl \
        qt4-linux-i386 qt4-linux-amd64 qt4-win-i386 qt4-win-amd64 \
        qt4-extract-tests qt4-package-tests

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
	$(ONE_BUILD_CHECK)
	$(PYTHON) scripts/fetch/qt4-sarge-fetch.py --arch i386
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(SOURCE_ARGS) --platform linux/386 --build-arg PARALLEL_JOBS=$(PARALLEL_JOBS) -f docker/qt4/linux/i386/Dockerfile -t $(QT4_LINUX_I386_IMAGE) .

qt4-linux-amd64: $(QT4_ARCHIVE_PATH) $(QT4_OPENSSL_PATH)
	$(ONE_BUILD_CHECK)
	$(PYTHON) scripts/fetch/qt4-sarge-fetch.py --arch amd64
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(SOURCE_ARGS) --platform linux/amd64 --build-arg PARALLEL_JOBS=$(PARALLEL_JOBS) -f docker/qt4/linux/amd64/Dockerfile -t $(QT4_LINUX_AMD64_IMAGE) .

# Opt-in Clang/libc++ SDKs. The existing SDKs supply the pinned Sarge
# sysroot, CRT startup objects and OpenSSL.
QT4_SARGE_LLVM_ARCH = $(if $(filter qt4-linux-amd64-llvm%,$@),amd64,i386)
QT4_SARGE_LLVM_PLATFORM = linux/$(if $(filter amd64,$(QT4_SARGE_LLVM_ARCH)),amd64,386)
QT4_SARGE_LLVM_TRIPLE = $(if $(filter amd64,$(QT4_SARGE_LLVM_ARCH)),x86_64,i686)-linux-gnu
QT4_SARGE_LLVM_IMAGE = qt4-linux-$(QT4_SARGE_LLVM_ARCH):llvm21
QT4_SARGE_LLVM_BASE ?= qt4-linux-$(QT4_SARGE_LLVM_ARCH):latest
QT4_SARGE_LLVM_COMPILER ?= longreach-llvm:21.1.8-compiler
QT4_SARGE_LLVM_HOST ?= host-packages
QT4_SARGE_LLVM_QEMU ?= longreach-run-qemu:lucid-$(QT4_SARGE_LLVM_ARCH)-bookworm
QT4_SARGE_LLVM_OUT = $(ARTIFACTS_DIR)/tests-qt4-linux-$(QT4_SARGE_LLVM_ARCH)-llvm21

QT4_SARGE_LLVM_TARGETS := qt4-linux-i386-llvm qt4-linux-amd64-llvm
.PHONY: $(QT4_SARGE_LLVM_TARGETS) $(addsuffix -examples,$(QT4_SARGE_LLVM_TARGETS)) $(addsuffix -qemu,$(QT4_SARGE_LLVM_TARGETS)) $(addsuffix -probe,$(QT4_SARGE_LLVM_TARGETS))
BUILD_TARGETS += $(QT4_SARGE_LLVM_TARGETS)
$(QT4_SARGE_LLVM_TARGETS) $(addsuffix -examples,$(QT4_SARGE_LLVM_TARGETS)): $(QT4_ARCHIVE_PATH)

$(QT4_SARGE_LLVM_TARGETS) $(addsuffix -examples,$(QT4_SARGE_LLVM_TARGETS)) $(addsuffix -probe,$(QT4_SARGE_LLVM_TARGETS)): $(DOWNLOAD_DIR)/llvm-project-21.1.8.src.tar.xz
	$(ONE_BUILD_CHECK)
	docker image inspect --format "{{.Id}}" $(QT4_SARGE_LLVM_BASE) $(QT4_SARGE_LLVM_COMPILER)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) --build-arg BASE_REGISTRY=$(BASE_REGISTRY) $(if $(APT_SNAPSHOT),--build-arg APT_SNAPSHOT=$(APT_SNAPSHOT)) --build-arg SARGE_IMAGE=$(QT4_SARGE_LLVM_BASE) --build-arg SARGE_ARCH=$(QT4_SARGE_LLVM_ARCH) --build-arg SARGE_PLATFORM=$(QT4_SARGE_LLVM_PLATFORM) --build-arg SARGE_GCC_TRIPLE=$(QT4_SARGE_LLVM_TRIPLE) --build-arg LLVM_COMPILER_IMAGE=$(QT4_SARGE_LLVM_COMPILER) --build-arg HOST_IMAGE=$(QT4_SARGE_LLVM_HOST) --build-arg PARALLEL_JOBS=$(PARALLEL_JOBS) --target $(if $(filter %-probe,$@),sdk-toolchain,$(if $(filter %-examples,$@),examples,sdk)) -f docker/qt4/linux/i386/Dockerfile-llvm -t $(QT4_SARGE_LLVM_IMAGE)$(if $(filter %-probe,$@),-probe) .
	$(if $(filter %-probe,$@),$(call MKDIR_P,$(QT4_SARGE_LLVM_OUT)/probe/bin))
	$(if $(filter %-probe,$@),docker run --rm --network none -v "$(CURDIR)/$(QT4_SARGE_LLVM_OUT)/probe/bin:/export" --entrypoint cp $(QT4_SARGE_LLVM_IMAGE)-probe /opt/qt4-sarge/cxx23-probe /export/)
	$(if $(filter %-probe,$@),$(PYTHON) scripts/build/qt4-sarge/run-llvm-qemu.py --probe-only --arch $(QT4_SARGE_LLVM_ARCH) --out "$(QT4_SARGE_LLVM_OUT)/probe" --sarge-image "$(QT4_SARGE_LLVM_BASE)" --qemu-image "$(QT4_SARGE_LLVM_QEMU)")
	$(if $(filter %-examples,$@),$(call MKDIR_P,$(QT4_SARGE_LLVM_OUT)))
	$(if $(filter %-examples,$@),$(PYTHON) -c "from pathlib import Path; Path('$(QT4_SARGE_LLVM_OUT)/elf-audit.json').unlink(missing_ok=True)")
	$(if $(filter %-examples,$@),docker run --rm --network none -v "$(CURDIR)/$(QT4_SARGE_LLVM_OUT):/export" $(QT4_SARGE_LLVM_IMAGE) -ec "mkdir -p /export/bin && cp /out/bin/* /export/bin/")
	$(if $(filter %-examples,$@),docker run --rm --network none -v "$(CURDIR)/$(QT4_SARGE_LLVM_OUT):/out" -v "$(CURDIR)/scripts/build/qt4-sarge:/scripts:ro" -v "$(CURDIR)/tests/expected-apps.txt:/expected-apps.txt:ro" -e SARGE_ARCH=$(QT4_SARGE_LLVM_ARCH) $(QT4_SARGE_LLVM_BASE) -ec "mkdir -p /work/suite && cp /expected-apps.txt /work/suite/expected-apps.txt && echo qt-selftest-cxx23 >> /work/suite/expected-apps.txt && python /scripts/audit-elf.py")

$(addsuffix -qemu,$(QT4_SARGE_LLVM_TARGETS)):
	$(ONE_BUILD_CHECK)
	$(PYTHON) scripts/build/qt4-sarge/run-llvm-qemu.py --arch $(QT4_SARGE_LLVM_ARCH) --out "$(QT4_SARGE_LLVM_OUT)" --sarge-image "$(QT4_SARGE_LLVM_BASE)" --qemu-image "$(QT4_SARGE_LLVM_QEMU)"

.PHONY: qt4-macos-i386
# Tiger: the Mac OS X 10.4u SDK, and GCC 5.5 for the C++ runtime.
TIGER_SDK_PATH := $(DOWNLOAD_DIR)/MacOSX10.4u.sdk.tar.xz
TIGER_SDK_URL ?= https://github.com/phracker/MacOSX-SDKs/releases/download/11.3/MacOSX10.4u.sdk.tar.xz
TIGER_SDK_SHA256 := d28276ce6b0f14af30f3bfdc171f8ef4033652da593578568f8be189506c1021
GCC55_PATH := $(DOWNLOAD_DIR)/gcc-5.5.0.tar.xz
GCC55_URL ?= https://ftp.gnu.org/gnu/gcc/gcc-5.5.0/gcc-5.5.0.tar.xz
GCC55_SHA256 := 530cea139d82fe542b358961130c69cfde8b3d14556370b65823d2f91f0ced87

qt4-macos-i386: $(QT4_ARCHIVE_PATH) $(QT4_OPENSSL_PATH) $(TIGER_SDK_PATH) $(GCC55_PATH)
	$(ONE_BUILD_CHECK)
	docker build --progress=plain $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(SOURCE_ARGS) --platform linux/amd64 --build-arg PARALLEL_JOBS=$(PARALLEL_JOBS) --build-arg LAB_GIT=$(LAB_GIT) -f docker/qt4/macos/i386/Dockerfile -t $(QT4_MACOS_I386_IMAGE) .

# The Tiger LLVM profile shares the patched Darwin compiler from Qt 5.
QT4_TIGER_LLVM_BASE ?= qt4-macos-i386:latest
QT4_TIGER_LLVM_COMPILER ?= longreach-llvm:21.1.8-snow-tls
QT4_TIGER_LLVM_IMAGE := qt4-macos-i386:llvm21
QT4_TIGER_LLVM_OUT := $(ARTIFACTS_DIR)/tests-qt4-macos-i386-llvm21

.PHONY: qt4-macos-i386-llvm qt4-macos-i386-llvm-probe qt4-macos-i386-llvm-examples
BUILD_TARGETS += qt4-macos-i386-llvm
qt4-macos-i386-llvm qt4-macos-i386-llvm-probe qt4-macos-i386-llvm-examples: $(DOWNLOAD_DIR)/llvm-project-21.1.8.src.tar.xz
	$(ONE_BUILD_CHECK)
	docker image inspect --format "{{.Id}}" $(QT4_TIGER_LLVM_BASE) $(QT4_TIGER_LLVM_COMPILER)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) --platform linux/amd64 --build-arg TIGER_IMAGE=$(QT4_TIGER_LLVM_BASE) --build-arg LLVM_COMPILER_IMAGE=$(QT4_TIGER_LLVM_COMPILER) --build-arg PARALLEL_JOBS=$(PARALLEL_JOBS) --target $(if $(filter %-probe,$@),probe,$(if $(filter %-examples,$@),examples,sdk)) -f docker/qt4/macos/i386/Dockerfile-llvm -t $(QT4_TIGER_LLVM_IMAGE)$(if $(filter %-probe,$@),-probe) .
	$(if $(filter %-probe %-examples,$@),$(call MKDIR_P,$(QT4_TIGER_LLVM_OUT)))
	$(if $(filter %-probe,$@),docker run --rm --network none -v "$(CURDIR)/$(QT4_TIGER_LLVM_OUT):/export" $(QT4_TIGER_LLVM_IMAGE)-probe "cp /out/cxx23-probe /export/")
	$(if $(filter %-examples,$@),docker run --rm --network none -v "$(CURDIR)/$(QT4_TIGER_LLVM_OUT):/export" $(QT4_TIGER_LLVM_IMAGE) "cp /out/*.tar.gz /out/macho-audit*.json /out/README.txt /out/*LICENSE* /out/*COPYING* /out/*EXCEPTION* /export/")

qt4-macos-i386-llvm qt4-macos-i386-llvm-examples: $(QT4_ARCHIVE_PATH)

$(TIGER_SDK_PATH):
	$(PYTHON) scripts/fetch/fetch.py "$(TIGER_SDK_URL)" "$@" "$(TIGER_SDK_SHA256)"

$(GCC55_PATH):
	$(PYTHON) scripts/fetch/fetch.py "$(GCC55_URL)" "$@" "$(GCC55_SHA256)"

.PHONY: qt4-macos-i386-extract-tests qt4-macos-ppc qt4-macos-ppc-extract-tests
qt4-macos-i386-extract-tests:
	$(PYTHON) scripts/build/qt4-macos-examples.py --image "$(QT4_MACOS_I386_IMAGE)" --jobs "$(PARALLEL_JOBS)" $(if $(filter 1,$(QT4_BUILD_LOCK_HELD)),--lock-held,)

# PowerPC from Jaguar: one Dockerfile builds both compilers, OpenSSL and Qt.
JAGUAR_SDK_PATH := $(DOWNLOAD_DIR)/MacOSX10.2.8.sdk.tar.xz
JAGUAR_SDK_URL ?= https://github.com/phracker/MacOSX-SDKs/releases/download/11.3/MacOSX10.2.8.sdk.tar.xz
JAGUAR_SDK_SHA256 := 8f30a969f8ae2be2ce9c2fae3a649f342a6b4aeceda9021f978af502fadeb13c

$(JAGUAR_SDK_PATH):
	$(PYTHON) scripts/fetch/fetch.py "$(JAGUAR_SDK_URL)" "$@" "$(JAGUAR_SDK_SHA256)"

qt4-macos-ppc: $(QT4_ARCHIVE_PATH) $(QT4_OPENSSL_PATH) $(TIGER_SDK_PATH) $(JAGUAR_SDK_PATH) $(GCC55_PATH)
	$(ONE_BUILD_CHECK)
	docker build --progress=plain $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(SOURCE_ARGS) --platform linux/amd64 --build-arg JOBS=$(PARALLEL_JOBS) --build-arg LAB_GIT=$(LAB_GIT) -f docker/qt4/macos/ppc/Dockerfile -t $(QT4_MACOS_PPC_IMAGE) .

qt4-macos-ppc-extract-tests:
	$(PYTHON) scripts/build/qt4-macos-examples.py --platform macos-jaguar-ppc --image "$(QT4_MACOS_PPC_IMAGE)" --jobs "$(PARALLEL_JOBS)" $(if $(filter 1,$(QT4_BUILD_LOCK_HELD)),--lock-held,)

# Windows 95 OSR2 and later: the Win9x backport, one configure.
qt4-win-i386: $(QT4_ARCHIVE_PATH) $(QT4_OPENSSL_PATH)
	$(ONE_BUILD_CHECK)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(SOURCE_ARGS) --build-arg PARALLEL_JOBS=$(PARALLEL_JOBS) -f docker/qt4/windows/i386/Dockerfile -t $(QT4_WIN_I386_IMAGE) .

# 64-bit Windows starts at XP x64 and needs no backport.
qt4-win-amd64: $(QT4_ARCHIVE_PATH) $(OPENSSL_PATH)
	$(ONE_BUILD_CHECK)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(SOURCE_ARGS) $(QT4_BUILD_ARGS) -f docker/qt4/windows/amd64/Dockerfile -t $(QT4_WIN_AMD64_IMAGE) .

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


$(eval $(call simple-build-targets,qt4-win-i386,qt4-win-i386,QT4_WIN_I386_IMAGE,qt4-extract-tests,QT4_IMAGE=$(QT4_WIN_I386_IMAGE) QT4_BUILD_LOCK_HELD=1,))
$(eval $(call simple-build-targets,qt4-win-amd64,qt4-win-amd64,QT4_WIN_AMD64_IMAGE,qt4-extract-tests,QT4_IMAGE=$(QT4_WIN_AMD64_IMAGE),))
$(eval $(call simple-build-targets,qt4-linux-i386,qt4-linux-i386,QT4_LINUX_I386_IMAGE,qt4-extract-tests,QT4_IMAGE=$(QT4_LINUX_I386_IMAGE) QT4_BUILD_LOCK_HELD=1,))
$(eval $(call simple-build-targets,qt4-linux-amd64,qt4-linux-amd64,QT4_LINUX_AMD64_IMAGE,qt4-extract-tests,QT4_IMAGE=$(QT4_LINUX_AMD64_IMAGE) QT4_BUILD_LOCK_HELD=1,))
$(eval $(call simple-build-targets,qt4-macos-i386,qt4-macos-i386,QT4_MACOS_I386_IMAGE,qt4-macos-i386-extract-tests,QT4_BUILD_LOCK_HELD=1,))
$(eval $(call simple-build-targets,qt4-macos-ppc,qt4-macos-ppc,QT4_MACOS_PPC_IMAGE,qt4-macos-ppc-extract-tests,QT4_BUILD_LOCK_HELD=1,))
