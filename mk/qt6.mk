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
QT6_WIN_AMD64_IMAGE := qt6-win-amd64$(LICENSE_SUFFIX)
QT6_WIN_ARM64_IMAGE := qt6-win-arm64$(LICENSE_SUFFIX)
QT6_LINUX_AMD64_IMAGE := qt6-linux-amd64$(LICENSE_SUFFIX)
QT6_LINUX_ARM64_IMAGE := qt6-linux-arm64$(LICENSE_SUFFIX)
QT6_MACOS_AMD64_IMAGE := qt6-macos-amd64$(LICENSE_SUFFIX)
QT6_MACOS_ARM64_IMAGE := qt6-macos-arm64$(LICENSE_SUFFIX)

# Releases are published as qt-everywhere-src or -opensource-src;
# scripts/fetch/qt6-fetch-source.py finds the archive and stores it under this
# one name. The SHA256 is pinned for the default version; another one needs
# QT6_ARCHIVE_SHA256, or QT6_SOURCE, to be downloaded at all.
QT6_ARCHIVE := qt-everywhere-src-$(QT6_VERSION).tar.xz
QT6_ARCHIVE_SHA256 ?= $(if $(filter 6.8.4,$(QT6_VERSION)),1da37a32a583e7856d6fc13357c8ff6ad3ef7b877b8d276713b85026426d5246,)
QT6_ARCHIVE_PATH := $(DOWNLOAD_DIR)/$(QT6_ARCHIVE)

# The MSVCRT build of LLVM-MinGW for Windows 7 (the UCRT one needs Windows 10).
QT6_WIN7_LLVM_MINGW_ARCHIVE := llvm-mingw-$(LLVM_MINGW_VERSION)-msvcrt-ubuntu-20.04-x86_64.tar.xz
QT6_WIN7_LLVM_MINGW_PATH := $(DOWNLOAD_DIR)/$(QT6_WIN7_LLVM_MINGW_ARCHIVE)
QT6_WIN7_LLVM_MINGW_SHA256 := eb878636e95c358452e4f4c95f032d81360096d0f1cd8ab6d24d5d09ca481372
QT6_WIN7_LLVM_MINGW_URL := https://github.com/mstorsjo/llvm-mingw/releases/download/$(LLVM_MINGW_VERSION)/$(QT6_WIN7_LLVM_MINGW_ARCHIVE)

# Sources the Linux Dockerfiles copy from downloads/: ninja (CentOS 7 has none
# new enough; amd64 only) and xcb-util-cursor, linked statically.
QT6_NINJA_PATH := $(DOWNLOAD_DIR)/ninja-1.12.1.tar.gz
QT6_NINJA_URL := https://github.com/ninja-build/ninja/archive/refs/tags/v1.12.1.tar.gz
QT6_NINJA_SHA256 := 821bdff48a3f683bc4bb3b6f0b5fe7b2d647cf65d52aeb63328c91a6c6df285a
QT6_XCB_CURSOR_PATH := $(DOWNLOAD_DIR)/xcb-util-cursor-0.1.5.tar.xz
QT6_XCB_CURSOR_URL := https://xcb.freedesktop.org/dist/xcb-util-cursor-0.1.5.tar.xz
QT6_XCB_CURSOR_SHA256 := 0caf99b0d60970f81ce41c7ba694e5eaaf833227bb2cbcdb2f6dc9666a663c57
# compiler-rt's os_version_check.c, which the macOS images build into
# libclang_rt.osx.a (osxcross does not install it).
QT6_OS_VERSION_CHECK_PATH := $(DOWNLOAD_DIR)/os_version_check-f28c006.c
QT6_OS_VERSION_CHECK_URL := https://raw.githubusercontent.com/llvm/llvm-project/f28c006a5895fc0e329fe15fead81e37457cb1d1/compiler-rt/lib/builtins/os_version_check.c
QT6_OS_VERSION_CHECK_SHA256 := 846d994b7dc1f229a3086b113ad946befaf963c5d6e8838323b17447bb5749fb

# macOS floors: 10.13 on Intel, 11.0 on Apple silicon (Qt 6.8 asks for 12;
# patches/qt6/macos takes it down).
QT6_MACOS_SDK_VERSION ?= 14.0
QT6_MACOS_DEPLOYMENT_TARGET ?= 10.13
QT6_MACOS_SDK := MacOSX$(QT6_MACOS_SDK_VERSION).sdk.tar.xz
QT6_MACOS_SDK_URL ?= https://github.com/joseluisq/macosx-sdks/releases/download/$(QT6_MACOS_SDK_VERSION)/$(QT6_MACOS_SDK)
QT6_MACOS_SDK_SHA256 ?= 5e4d3be6b445f0eacc0333ff2117e93e4433d8c4fe44053a14f735033a98aaa9
QT6_MACOS_SDK_PATH := $(DOWNLOAD_DIR)/$(QT6_MACOS_SDK)
QT6_MACOS_OSXCROSS_REF ?= $(OSXCROSS_REF)
QT6_MACOS_ARM64_SDK_VERSION ?= 14.0
QT6_MACOS_ARM64_DEPLOYMENT_TARGET ?= 11.0
QT6_MACOS_ARM64_SDK := MacOSX$(QT6_MACOS_ARM64_SDK_VERSION).sdk.tar.xz
QT6_MACOS_ARM64_SDK_URL ?= https://github.com/joseluisq/macosx-sdks/releases/download/$(QT6_MACOS_ARM64_SDK_VERSION)/$(QT6_MACOS_ARM64_SDK)
QT6_MACOS_ARM64_SDK_SHA256 ?= 5e4d3be6b445f0eacc0333ff2117e93e4433d8c4fe44053a14f735033a98aaa9
QT6_MACOS_ARM64_SDK_PATH := $(DOWNLOAD_DIR)/$(QT6_MACOS_ARM64_SDK)

.PHONY: download-qt6 qt6-host build-qt6-host \
        qt6-win-amd64 qt6-win-arm64 qt6-linux-amd64 qt6-linux-arm64 \
        qt6-macos-amd64 qt6-macos-arm64 \
        qt6-win-amd64-smoke qt6-win-amd64-audit qt6-win-arm64-smoke \
        qt6-linux-amd64-smoke qt6-linux-arm64-smoke \
        qt6-macos-amd64-smoke qt6-macos-amd64-audit qt6-macos-arm64-smoke qt6-macos-arm64-audit \
        qt6-host-smoke

$(QT6_WIN7_LLVM_MINGW_PATH):
	$(PYTHON) scripts/fetch/fetch.py "$(QT6_WIN7_LLVM_MINGW_URL)" "$@" "$(QT6_WIN7_LLVM_MINGW_SHA256)"

$(QT6_NINJA_PATH):
	$(PYTHON) scripts/fetch/fetch.py "$(QT6_NINJA_URL)" "$@" "$(QT6_NINJA_SHA256)"

$(QT6_XCB_CURSOR_PATH):
	$(PYTHON) scripts/fetch/fetch.py "$(QT6_XCB_CURSOR_URL)" "$@" "$(QT6_XCB_CURSOR_SHA256)"

$(QT6_OS_VERSION_CHECK_PATH):
	$(PYTHON) scripts/fetch/fetch.py "$(QT6_OS_VERSION_CHECK_URL)" "$@" "$(QT6_OS_VERSION_CHECK_SHA256)"

download-qt6: $(QT6_ARCHIVE_PATH)

# QT6_SOURCE replaces the archive even when one is already in downloads/.
ifneq ($(QT6_SOURCE),)
.PHONY: $(QT6_ARCHIVE_PATH)
endif

$(QT6_ARCHIVE_PATH):
	$(if $(or $(QT6_ARCHIVE_SHA256),$(QT6_SOURCE)),,$(error Qt $(QT6_VERSION) has no pinned SHA256: give QT6_ARCHIVE_SHA256=<sha256> (from the Qt release), or QT6_SOURCE=<archive> you trust))
	$(PYTHON) scripts/fetch/qt6-fetch-source.py "$(QT6_VERSION)" "$(DOWNLOAD_DIR)" $(if $(QT6_SOURCE),--source "$(QT6_SOURCE)",)
	$(if $(and $(QT6_ARCHIVE_SHA256),$(if $(QT6_SOURCE),,1)),$(PYTHON) scripts/fetch/fetch.py --check "$@" "$(QT6_ARCHIVE_SHA256)")

QT6_BUILD_ARGS = --build-arg QT_VERSION=$(QT6_VERSION) --build-arg QT_ARCHIVE=$(QT6_ARCHIVE) --build-arg DOWNLOAD_DIR=$(DOWNLOAD_DIR) --build-arg PARALLEL_JOBS=$(PARALLEL_JOBS) --build-arg LICENSE_PROFILE=$(LICENSE_PROFILE)

# Host Qt tools (moc, rcc, ...), which every cross target copies from this image.
qt6-host: $(QT6_ARCHIVE_PATH)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(SOURCE_ARGS) $(QT6_BUILD_ARGS) -f docker/qt6/host/Dockerfile -t $(QT6_HOST_IMAGE) .

# What the cross targets depend on: qt6-host only when its inputs changed. A
# plain docker build of it starts over once Docker has dropped its cache.
build-qt6-host:
	$(PYTHON) scripts/build/ensure-image.py --image "$(QT6_HOST_IMAGE)" --target qt6-host --docker-build-flags="$(DOCKER_BUILD_FLAGS)" $(if $(filter 1,$(NO_CACHE) $(FORCE)),--force,)

# Windows x86_64 is the Windows 7 backport, built against MSVCRT.
qt6-win-amd64: $(QT6_ARCHIVE_PATH) $(QT6_WIN7_LLVM_MINGW_PATH) build-qt6-host
	$(call LICENSE_ENFORCED_ONLY_ON_LINUX,$@)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(SOURCE_ARGS) $(QT6_BUILD_ARGS) --build-arg QT6_HOST_IMAGE=$(QT6_HOST_IMAGE) --build-arg LLVM_MINGW_VERSION=$(LLVM_MINGW_VERSION) --build-arg LLVM_MINGW_ARCHIVE=$(QT6_WIN7_LLVM_MINGW_ARCHIVE) --build-arg LLVM_MINGW_SHA256=$(QT6_WIN7_LLVM_MINGW_SHA256) -f docker/qt6/windows/amd64/Dockerfile -t $(QT6_WIN_AMD64_IMAGE) .

qt6-win-arm64: $(QT6_ARCHIVE_PATH) $(LLVM_MINGW_PATH) build-qt6-host
	$(call LICENSE_ENFORCED_ONLY_ON_LINUX,$@)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(SOURCE_ARGS) $(QT6_BUILD_ARGS) --build-arg QT6_HOST_IMAGE=$(QT6_HOST_IMAGE) --build-arg LLVM_MINGW_VERSION=$(LLVM_MINGW_VERSION) --build-arg LLVM_MINGW_ARCHIVE=$(LLVM_MINGW_ARCHIVE) --build-arg LLVM_MINGW_SHA256=$(LLVM_MINGW_SHA256) -f docker/qt6/windows/arm64/Dockerfile -t $(QT6_WIN_ARM64_IMAGE) .

# glibc 2.17 (RHEL/CentOS 7.6), built natively on CentOS 7, without the host
# image.
qt6-linux-amd64: $(QT6_ARCHIVE_PATH) $(OPENSSL_PATH) $(QT6_NINJA_PATH) $(QT6_XCB_CURSOR_PATH)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(SOURCE_ARGS) $(QT6_BUILD_ARGS) --build-arg OPENSSL_VERSION=$(OPENSSL_VERSION) -f docker/qt6/linux/amd64/Dockerfile -t $(QT6_LINUX_AMD64_IMAGE) .

qt6-linux-arm64: $(QT6_ARCHIVE_PATH) $(OPENSSL_PATH) $(QT6_XCB_CURSOR_PATH) build-qt6-host
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(SOURCE_ARGS) $(QT6_BUILD_ARGS) --build-arg QT6_HOST_IMAGE=$(QT6_HOST_IMAGE) --build-arg OPENSSL_VERSION=$(OPENSSL_VERSION) -f docker/qt6/linux/arm64/Dockerfile -t $(QT6_LINUX_ARM64_IMAGE) .

# A quick headless run of tests/ against the host image's Qt (no Qt 3D, so
# gl-heavy-gallery skips); qt6-linux-amd64-smoke is the full one.
qt6-host-smoke:
	docker run --rm --entrypoint sh 	    -v "$(CURDIR)/tests:/src:ro" 	    -v "$(CURDIR)/scripts/build/qt6-host-smoke.sh:/qt6-host-smoke.sh:ro" 	    $(QT6_HOST_IMAGE) -c "PARALLEL_JOBS=$(PARALLEL_JOBS) sh /qt6-host-smoke.sh"

# A repacked macOS SDK from a GitHub release, pinned by SHA256 and fetched
# into downloads/ like every other input (one rule when both use the same).
$(QT6_MACOS_SDK_PATH):
	$(PYTHON) scripts/fetch/fetch.py "$(QT6_MACOS_SDK_URL)" "$@" "$(QT6_MACOS_SDK_SHA256)"

ifneq ($(QT6_MACOS_ARM64_SDK_PATH),$(QT6_MACOS_SDK_PATH))
$(QT6_MACOS_ARM64_SDK_PATH):
	$(PYTHON) scripts/fetch/fetch.py "$(QT6_MACOS_ARM64_SDK_URL)" "$@" "$(QT6_MACOS_ARM64_SDK_SHA256)"
endif

qt6-macos-amd64: $(QT6_ARCHIVE_PATH) $(QT6_OS_VERSION_CHECK_PATH) $(QT6_MACOS_SDK_PATH) build-qt6-host
	$(call LICENSE_ENFORCED_ONLY_ON_LINUX,$@)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(SOURCE_ARGS) $(QT6_BUILD_ARGS) --build-arg QT6_HOST_IMAGE=$(QT6_HOST_IMAGE) --build-arg OSX_SDK_VERSION=$(QT6_MACOS_SDK_VERSION) --build-arg OSX_DEPLOYMENT_TARGET=$(QT6_MACOS_DEPLOYMENT_TARGET) --build-arg OSX_SDK=$(QT6_MACOS_SDK) --build-arg OSX_SDK_SHA256=$(QT6_MACOS_SDK_SHA256) --build-arg LAB_GIT=$(LAB_GIT) --build-arg OSXCROSS_REF=$(QT6_MACOS_OSXCROSS_REF) -f docker/qt6/macos/amd64/Dockerfile -t $(QT6_MACOS_AMD64_IMAGE) .

qt6-macos-arm64: $(QT6_ARCHIVE_PATH) $(QT6_OS_VERSION_CHECK_PATH) $(QT6_MACOS_ARM64_SDK_PATH) build-qt6-host
	$(call LICENSE_ENFORCED_ONLY_ON_LINUX,$@)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(SOURCE_ARGS) $(QT6_BUILD_ARGS) --build-arg QT6_HOST_IMAGE=$(QT6_HOST_IMAGE) --build-arg OSX_SDK_VERSION=$(QT6_MACOS_ARM64_SDK_VERSION) --build-arg OSX_DEPLOYMENT_TARGET=$(QT6_MACOS_ARM64_DEPLOYMENT_TARGET) --build-arg OSX_SDK=$(QT6_MACOS_ARM64_SDK) --build-arg OSX_SDK_SHA256=$(QT6_MACOS_ARM64_SDK_SHA256) --build-arg LAB_GIT=$(LAB_GIT) --build-arg OSXCROSS_REF=$(QT6_MACOS_OSXCROSS_REF) -f docker/qt6/macos/arm64/Dockerfile -t $(QT6_MACOS_ARM64_IMAGE) .

# qt6-<target>-smoke builds tests/ against the image into
# artifacts/tests-<image>/ and, for Linux amd64, runs it there; the
# cross-built suites are run with scripts/run/run.py.
QT6_SMOKE_OUT = $(ARTIFACTS_DIR)/tests-$(QT6_SMOKE_IMAGE)

define qt6-build-smoke
	$(call MKDIR_P,$(QT6_SMOKE_OUT))
	docker run --rm -v "$(CURDIR)/tests:/src:ro" -v "$(CURDIR)/$(QT6_SMOKE_OUT):/out" \
		$(QT6_SMOKE_IMAGE) \
		bash -c 'set -e; cp -r /src /tmp/qt-smoke-tests; mkdir -p /tmp/qt-smoke-build; cd /tmp/qt-smoke-build; $(QT6_SMOKE_QT_DIR)/bin/qt-cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DSMOKE_LICENSE_PROFILE=$(LICENSE_PROFILE) $(QT6_SMOKE_CMAKE_ARGS) /tmp/qt-smoke-tests; cmake --build . -j $(if $(PARALLEL_JOBS),$(PARALLEL_JOBS),$$(nproc)); $(QT6_SMOKE_COLLECT); ls -la /out/; $(QT6_SMOKE_RUN)'
	$(PYTHON) scripts/tests/write_manifest.py --out "$(QT6_SMOKE_OUT)" --image "$(QT6_SMOKE_IMAGE)" --qt-version "$(QT6_VERSION)" --openssl-version "$(if $(findstring linux,$(QT6_SMOKE_IMAGE)),$(OPENSSL_VERSION),none)" --kind qt6-build-kit-tests --license-profile "$(LICENSE_PROFILE)"
	@echo "-> $(QT6_SMOKE_OUT)"
endef

QT6_COLLECT_EXE := find . -name "*.exe" ! -name "a.exe" -exec cp {} /out/ \;
QT6_COLLECT_ELF := find . -maxdepth 2 -type f -executable ! -name "*.so" -exec cp {} /out/ \;
QT6_COLLECT_APP := find . -maxdepth 2 -type d -name "*.app" -exec cp -r {} /out/ \; ; find . -maxdepth 2 -type f -executable ! -name "*.dylib" ! -name "*.qml" -exec cp {} /out/ \;

# Xvfb gives Qt Quick 3D a real GLX context; 24-bit because CentOS 7's Mesa has
# no GLX configuration for xvfb-run's default 8 bits.
QT6_RUN_OFFSCREEN := cd /out && xvfb-run -a -s "-screen 0 1280x1024x24" env QT_QPA_PLATFORM=offscreen ./smoke-runner
QT6_RUN_NONE := true

qt6-win-amd64-smoke: QT6_SMOKE_IMAGE := $(QT6_WIN_AMD64_IMAGE)
qt6-win-amd64-smoke: QT6_SMOKE_QT_DIR := /opt/qt6-amd64
qt6-win-amd64-smoke: QT6_SMOKE_COLLECT := $(QT6_COLLECT_EXE)
qt6-win-amd64-smoke: QT6_SMOKE_RUN := $(QT6_RUN_NONE)
qt6-win-amd64-smoke:
	$(qt6-build-smoke)

qt6-win-amd64-audit: QT6_SMOKE_IMAGE := $(QT6_WIN_AMD64_IMAGE)
qt6-win-amd64-audit:
	docker run --rm --entrypoint sh -v "$(CURDIR)/$(QT6_SMOKE_OUT):/in:ro" -v "$(CURDIR)/scripts/audit/qt6-win7-audit.sh:/audit.sh:ro" $(QT6_WIN_AMD64_IMAGE) -c 'sh /audit.sh /in/*.exe'

qt6-win-arm64-smoke: QT6_SMOKE_IMAGE := $(QT6_WIN_ARM64_IMAGE)
qt6-win-arm64-smoke: QT6_SMOKE_QT_DIR := /opt/qt6-arm64
qt6-win-arm64-smoke: QT6_SMOKE_COLLECT := $(QT6_COLLECT_EXE)
qt6-win-arm64-smoke: QT6_SMOKE_RUN := $(QT6_RUN_NONE)
qt6-win-arm64-smoke:
	$(qt6-build-smoke)

qt6-linux-amd64-smoke: QT6_SMOKE_IMAGE := $(QT6_LINUX_AMD64_IMAGE)
qt6-linux-amd64-smoke: QT6_SMOKE_QT_DIR := /opt/qt6-linux-amd64
qt6-linux-amd64-smoke: QT6_SMOKE_CMAKE_ARGS := -DOPENSSL_ROOT_DIR=/opt/openssl-3 -DOPENSSL_USE_STATIC_LIBS=ON
qt6-linux-amd64-smoke: QT6_SMOKE_COLLECT := $(QT6_COLLECT_ELF)
qt6-linux-amd64-smoke: QT6_SMOKE_RUN := $(QT6_RUN_OFFSCREEN)
qt6-linux-amd64-smoke:
	$(qt6-build-smoke)

qt6-linux-arm64-smoke: QT6_SMOKE_IMAGE := $(QT6_LINUX_ARM64_IMAGE)
qt6-linux-arm64-smoke: QT6_SMOKE_QT_DIR := /opt/qt6-linux-arm64
qt6-linux-arm64-smoke: QT6_SMOKE_COLLECT := $(QT6_COLLECT_ELF)
qt6-linux-arm64-smoke: QT6_SMOKE_RUN := $(QT6_RUN_NONE)
qt6-linux-arm64-smoke:
	$(qt6-build-smoke)

qt6-macos-amd64-smoke: QT6_SMOKE_IMAGE := $(QT6_MACOS_AMD64_IMAGE)
qt6-macos-amd64-smoke: QT6_SMOKE_QT_DIR := /opt/qt6-macos-amd64
qt6-macos-amd64-smoke: QT6_SMOKE_CMAKE_ARGS := -DCMAKE_MACOSX_BUNDLE=TRUE -DOSXCROSS_SDK_VERSION=$(QT6_MACOS_SDK_VERSION) -DCMAKE_OSX_DEPLOYMENT_TARGET=$(QT6_MACOS_DEPLOYMENT_TARGET)
qt6-macos-amd64-smoke: QT6_SMOKE_COLLECT := $(QT6_COLLECT_APP)
qt6-macos-amd64-smoke: QT6_SMOKE_RUN := $(QT6_RUN_NONE)
qt6-macos-amd64-smoke:
	$(qt6-build-smoke)

qt6-macos-amd64-audit: QT6_SMOKE_IMAGE := $(QT6_MACOS_AMD64_IMAGE)
qt6-macos-amd64-audit:
	docker run --rm --entrypoint sh -v "$(CURDIR)/$(QT6_SMOKE_OUT):/in:ro" -v "$(CURDIR)/scripts/audit/qt6-macos-audit.sh:/audit.sh:ro" $(QT6_MACOS_AMD64_IMAGE) -c 'sh /audit.sh $(QT6_MACOS_DEPLOYMENT_TARGET) /in/*'

qt6-macos-arm64-smoke: QT6_SMOKE_IMAGE := $(QT6_MACOS_ARM64_IMAGE)
qt6-macos-arm64-smoke: QT6_SMOKE_QT_DIR := /opt/qt6-macos-arm64
qt6-macos-arm64-smoke: QT6_SMOKE_CMAKE_ARGS := -DCMAKE_MACOSX_BUNDLE=TRUE -DOSXCROSS_SDK_VERSION=$(QT6_MACOS_ARM64_SDK_VERSION) -DCMAKE_OSX_DEPLOYMENT_TARGET=$(QT6_MACOS_ARM64_DEPLOYMENT_TARGET)
qt6-macos-arm64-smoke: QT6_SMOKE_COLLECT := $(QT6_COLLECT_APP)
qt6-macos-arm64-smoke: QT6_SMOKE_RUN := $(QT6_RUN_NONE)
qt6-macos-arm64-smoke:
	$(qt6-build-smoke)

qt6-macos-arm64-audit: QT6_SMOKE_IMAGE := $(QT6_MACOS_ARM64_IMAGE)
qt6-macos-arm64-audit:
	docker run --rm --entrypoint sh -v "$(CURDIR)/$(QT6_SMOKE_OUT):/in:ro" -v "$(CURDIR)/scripts/audit/qt6-macos-audit.sh:/audit.sh:ro" $(QT6_MACOS_ARM64_IMAGE) -c 'MACHO_AUDIT_ARCH=arm64 sh /audit.sh $(QT6_MACOS_ARM64_DEPLOYMENT_TARGET) /in/*'


$(eval $(call simple-build-targets,qt6-win-amd64,qt6-win-amd64,QT6_WIN_AMD64_IMAGE,qt6-win-amd64-smoke,,qt6-host))
$(eval $(call simple-build-targets,qt6-win-arm64,qt6-win-arm64,QT6_WIN_ARM64_IMAGE,qt6-win-arm64-smoke,,qt6-host))
$(eval $(call simple-build-targets,qt6-linux-amd64,qt6-linux-amd64,QT6_LINUX_AMD64_IMAGE,qt6-linux-amd64-smoke,,))
$(eval $(call simple-build-targets,qt6-linux-arm64,qt6-linux-arm64,QT6_LINUX_ARM64_IMAGE,qt6-linux-arm64-smoke,,qt6-host))
$(eval $(call simple-build-targets,qt6-macos-amd64,qt6-macos-amd64,QT6_MACOS_AMD64_IMAGE,qt6-macos-amd64-smoke,,qt6-host))
$(eval $(call simple-build-targets,qt6-macos-arm64,qt6-macos-arm64,QT6_MACOS_ARM64_IMAGE,qt6-macos-arm64-smoke,,qt6-host))
