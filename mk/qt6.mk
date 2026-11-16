# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 6.8.5 LTS: Windows from 7 SP1, Linux from RHEL/CentOS 7, macOS from 10.13
# (11.0 on Apple silicon). CMake-based, with its own Dockerfiles and patches.
#
# QT6_VERSION picks the patch release; QT6_SOURCE uses an archive of your own,
# such as a commercial LTS release that is not public yet:
#   make qt6-linux-amd64 QT6_VERSION=6.8.8 QT6_SOURCE=/path/to/qt-everywhere-src-6.8.8.tar.xz
QT6_VERSION ?= 6.8.5
QT6_SOURCE ?=
QT6_SERIES := $(basename $(QT6_VERSION))

QT6_HOST_IMAGE := qt6-host$(LICENSE_SUFFIX)
QT6_LLVM_COMPILER_INPUTS_IMAGE ?= qt6-centos7-amd64-inputs
QT6_LLVM_COMPILER_IMAGE ?= longreach-llvm:21.1.8-compiler
QT6_WIN_AMD64_IMAGE := qt6-win-amd64-llvm21$(LICENSE_SUFFIX)
QT6_WIN_ARM64_IMAGE := qt6-win-arm64$(LICENSE_SUFFIX)
QT6_LINUX_AMD64_IMAGE := qt6-linux-amd64-llvm21$(LICENSE_SUFFIX)
QT6_LINUX_ARM64_IMAGE := qt6-linux-arm64-llvm21$(LICENSE_SUFFIX)
QT6_MACOS_AMD64_IMAGE := qt6-macos-amd64-llvm21$(LICENSE_SUFFIX)
QT6_MACOS_ARM64_IMAGE := qt6-macos-arm64$(LICENSE_SUFFIX)

# Releases are published as qt-everywhere-src or -opensource-src;
# scripts/fetch/qt6-fetch-source.py finds the archive and stores it under this
# one name. The SHA256 is pinned for the default version; another one needs
# QT6_ARCHIVE_SHA256, or QT6_SOURCE, to be downloaded at all.
QT6_ARCHIVE := qt-everywhere-src-$(QT6_VERSION).tar.xz
QT6_ARCHIVE_SHA256 ?= $(if $(filter 6.8.5,$(QT6_VERSION)),c0537548bb3871cbb3cac85fb55813430d45ac4d5d4daa64bdf41f3c2ae65ff9,)
QT6_ARCHIVE_PATH := $(DOWNLOAD_DIR)/$(QT6_ARCHIVE)

# Windows 7's CRT and headers are built from the pinned MinGW-w64 sources.
QT6_MINGW_CRT_ARCHIVE := mingw-w64-v13.0.0.tar.bz2
QT6_MINGW_CRT_PATH := $(DOWNLOAD_DIR)/$(QT6_MINGW_CRT_ARCHIVE)
QT6_MINGW_CRT_SHA256 := 5afe822af5c4edbf67daaf45eec61d538f49eef6b19524de64897c6b95828caf
QT6_MINGW_CRT_URL := https://downloads.sourceforge.net/project/mingw-w64/mingw-w64/mingw-w64-release/$(QT6_MINGW_CRT_ARCHIVE)

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

$(QT6_MINGW_CRT_PATH):
	$(PYTHON) scripts/fetch/fetch.py "$(QT6_MINGW_CRT_URL)" "$@" "$(QT6_MINGW_CRT_SHA256)"

# CMake for the CentOS 7 build, downloaded from the Lab release via fetch.py.
QT6_CENTOS_CMAKE_VERSION := 3.27.9
QT6_CENTOS_CMAKE_ARCHIVE := cmake-$(QT6_CENTOS_CMAKE_VERSION)-linux-x86_64.tar.gz
QT6_CENTOS_CMAKE_PATH := $(DOWNLOAD_DIR)/$(QT6_CENTOS_CMAKE_ARCHIVE)
QT6_CENTOS_CMAKE_SHA256 := 72b01478eeb312bf1a0136208957784fe55a7b587f8d9f9142a7fc9b0b9e9a28

$(QT6_CENTOS_CMAKE_PATH):
	$(PYTHON) scripts/fetch/fetch.py "https://github.com/Kitware/CMake/releases/download/v$(QT6_CENTOS_CMAKE_VERSION)/$(QT6_CENTOS_CMAKE_ARCHIVE)" "$@" "$(QT6_CENTOS_CMAKE_SHA256)"

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
	$(PYTHON) scripts/fetch/qt6-fetch-source.py "$(QT6_VERSION)" "$(DOWNLOAD_DIR)" $(if $(QT6_SOURCE),--source "$(QT6_SOURCE)",$(if $(QT6_ARCHIVE_SHA256),--sha256 "$(QT6_ARCHIVE_SHA256)"))
	$(if $(and $(QT6_ARCHIVE_SHA256),$(if $(QT6_SOURCE),,1)),$(PYTHON) scripts/fetch/fetch.py --check "$@" "$(QT6_ARCHIVE_SHA256)")

QT6_SOURCE_SHA256 = $(if $(QT6_SOURCE),,$(QT6_ARCHIVE_SHA256))
QT6_BUILD_ARGS = --build-arg QT_VERSION=$(QT6_VERSION) --build-arg QT_ARCHIVE=$(QT6_ARCHIVE) --build-arg DOWNLOAD_DIR=$(DOWNLOAD_DIR) --build-arg PARALLEL_JOBS=$(PARALLEL_JOBS) --build-arg LICENSE_PROFILE=$(LICENSE_PROFILE)

# Host Qt tools (moc, rcc, ...), which every cross target copies from this image.
qt6-host: $(QT6_ARCHIVE_PATH)
	$(ONE_BUILD_CHECK)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(SOURCE_ARGS) $(QT6_BUILD_ARGS) -f docker/qt6/host/Dockerfile -t $(QT6_HOST_IMAGE) .

# What the cross targets depend on: qt6-host only when its inputs changed. A
# plain docker build of it starts over once Docker has dropped its cache.
build-qt6-host:
	$(PYTHON) scripts/build/ensure-image.py --image "$(QT6_HOST_IMAGE)" --target qt6-host --docker-build-flags="$(DOCKER_BUILD_FLAGS)" $(if $(filter 1,$(NO_CACHE) $(FORCE)),--force,)

.PHONY: qt6-llvm-cross-host
qt6-llvm-cross-host:
	$(ONE_BUILD_CHECK)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(SOURCE_ARGS) --target cross-host -f docker/qt6/linux/arm64/Dockerfile -t qt6-llvm-cross-host .

# The Windows 7 CRT is built from MinGW-w64 sources by upstream Clang.
qt6-win-amd64: $(QT6_ARCHIVE_PATH) $(DOWNLOAD_DIR)/llvm-project-21.1.8.src.tar.xz $(QT6_MINGW_CRT_PATH) build-qt6-linux-amd64 qt6-llvm-cross-host
	$(ONE_BUILD_CHECK)
	$(call LICENSE_ENFORCED_ONLY_ON_LINUX,$@)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(QT6_BUILD_ARGS) --build-arg LLVM_COMPILER_IMAGE=$(QT6_LLVM_COMPILER_IMAGE) --build-arg QT_HOST_IMAGE=$(QT6_LINUX_AMD64_IMAGE) --build-arg QT_SHA256=$(QT6_SOURCE_SHA256) -f docker/qt6/windows/amd64/Dockerfile -t $(QT6_WIN_AMD64_IMAGE) -t qt6-win-amd64:llvm21 .

qt6-win-arm64: $(QT6_ARCHIVE_PATH) $(LLVM_MINGW_PATH) build-qt6-host
	$(ONE_BUILD_CHECK)
	$(call LICENSE_ENFORCED_ONLY_ON_LINUX,$@)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(SOURCE_ARGS) $(QT6_BUILD_ARGS) --build-arg QT6_HOST_IMAGE=$(QT6_HOST_IMAGE) --build-arg LLVM_MINGW_VERSION=$(LLVM_MINGW_VERSION) --build-arg LLVM_MINGW_ARCHIVE=$(LLVM_MINGW_ARCHIVE) --build-arg LLVM_MINGW_SHA256=$(LLVM_MINGW_SHA256) -f docker/qt6/windows/arm64/Dockerfile -t $(QT6_WIN_ARM64_IMAGE) .

# Build the shared LLVM compiler from the locked CentOS userland and source
# inputs. The inputs stage assembles dependencies without building Qt.
.PHONY: qt6-llvm-compiler-inputs qt6-llvm-compiler
qt6-llvm-compiler-inputs: $(QT6_ARCHIVE_PATH) $(OPENSSL_PATH) $(QT6_NINJA_PATH) $(QT6_XCB_CURSOR_PATH) $(QT6_CENTOS_CMAKE_PATH)
	$(ONE_BUILD_CHECK)
	$(PYTHON) scripts/fetch/qt6-centos7-fetch.py
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(SOURCE_ARGS) $(QT6_BUILD_ARGS) --build-arg OPENSSL_VERSION=$(OPENSSL_VERSION) --target inputs -f docker/qt6/linux/amd64/Dockerfile -t $(QT6_LLVM_COMPILER_INPUTS_IMAGE) .

qt6-llvm-compiler: $(DOWNLOAD_DIR)/llvm-project-21.1.8.src.tar.xz qt6-llvm-compiler-inputs
	$(ONE_BUILD_CHECK)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) --build-arg LLVM_COMPILER_BASE=$(QT6_LLVM_COMPILER_INPUTS_IMAGE) --build-arg PARALLEL_JOBS=$(PARALLEL_JOBS) --target compiler -f docker/qt6/host/Dockerfile -t $(QT6_LLVM_COMPILER_IMAGE) .

# The CentOS 7 ARM64 runtime is also used by the Qt 5 Trusty SDK.
QT6_ARM64_LLVM_RUNTIME_IMAGE ?= longreach-llvm:21.1.8-linux-arm64-runtime
.PHONY: qt6-linux-arm64-llvm-runtime
qt6-linux-arm64-llvm-runtime: $(DOWNLOAD_DIR)/llvm-project-21.1.8.src.tar.xz build-qt6-llvm-compiler
	$(ONE_BUILD_CHECK)
	docker image inspect --format "{{.Id}}" $(QT6_LLVM_COMPILER_IMAGE)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(SOURCE_ARGS) --build-arg LLVM_COMPILER_IMAGE=$(QT6_LLVM_COMPILER_IMAGE) --build-arg PARALLEL_JOBS=$(PARALLEL_JOBS) --target llvm-runtime -f docker/qt6/linux/arm64/Dockerfile -t $(QT6_ARM64_LLVM_RUNTIME_IMAGE) .

$(DOWNLOAD_DIR)/llvm-project-21.1.8.src.tar.xz:
	$(PYTHON) scripts/fetch/fetch.py "https://github.com/llvm/llvm-project/releases/download/llvmorg-21.1.8/llvm-project-21.1.8.src.tar.xz" "$@" "4633a23617fa31a3ea51242586ea7fb1da7140e426bd62fc164261fe036aa142"

# The native SDK also supplies the LLVM host Qt tools for cross-builds.
qt6-linux-amd64: build-qt6-llvm-compiler
	$(ONE_BUILD_CHECK)
	docker image inspect --format "{{.Id}}" $(QT6_LLVM_COMPILER_IMAGE)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(QT6_BUILD_ARGS) --build-arg LLVM_COMPILER_IMAGE=$(QT6_LLVM_COMPILER_IMAGE) --target qt -f docker/qt6/linux/amd64/Dockerfile -t $(QT6_LINUX_AMD64_IMAGE) $(if $(filter gpl-enabled,$(LICENSE_PROFILE)),-t qt6-linux-amd64:llvm21) .

.PHONY: qt6-linux-arm64-cross-deps
qt6-linux-arm64-cross-deps: $(OPENSSL_PATH) $(QT6_XCB_CURSOR_PATH)
	$(ONE_BUILD_CHECK)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(SOURCE_ARGS) --build-arg OPENSSL_VERSION=$(OPENSSL_VERSION) --build-arg PARALLEL_JOBS=$(PARALLEL_JOBS) --target deps -f docker/qt6/linux/arm64/Dockerfile -t qt6-linux-arm64-cross-deps .

qt6-linux-arm64: $(QT6_ARCHIVE_PATH) $(OPENSSL_PATH) $(QT6_XCB_CURSOR_PATH) $(DOWNLOAD_DIR)/llvm-project-21.1.8.src.tar.xz build-qt6-linux-amd64
	$(ONE_BUILD_CHECK)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(SOURCE_ARGS) $(QT6_BUILD_ARGS) --build-arg LLVM_COMPILER_IMAGE=$(QT6_LLVM_COMPILER_IMAGE) --build-arg QT_HOST_IMAGE=$(QT6_LINUX_AMD64_IMAGE) --build-arg OPENSSL_VERSION=$(OPENSSL_VERSION) --build-arg QT_SHA256=$(QT6_SOURCE_SHA256) -f docker/qt6/linux/arm64/Dockerfile -t $(QT6_LINUX_ARM64_IMAGE) $(if $(filter gpl-enabled,$(LICENSE_PROFILE)),-t qt6-linux-arm64:llvm21) .

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

QT6_MACOS_AMD64_OSXCROSS_ARGS = --build-arg OSX_SDK_VERSION=$(QT6_MACOS_SDK_VERSION) --build-arg OSX_DEPLOYMENT_TARGET=$(QT6_MACOS_DEPLOYMENT_TARGET) --build-arg OSX_SDK=$(QT6_MACOS_SDK) --build-arg OSX_SDK_SHA256=$(QT6_MACOS_SDK_SHA256) --build-arg LAB_GIT=$(LAB_GIT) --build-arg OSXCROSS_REF=$(QT6_MACOS_OSXCROSS_REF)

.PHONY: qt6-macos-amd64-osxcross
qt6-macos-amd64-osxcross: $(QT6_OS_VERSION_CHECK_PATH) $(QT6_MACOS_SDK_PATH)
	$(ONE_BUILD_CHECK)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(SOURCE_ARGS) $(QT6_BUILD_ARGS) $(QT6_MACOS_AMD64_OSXCROSS_ARGS) --target osxcross-builder -f docker/qt6/macos/amd64/Dockerfile -t qt6-macos-amd64-osxcross .

qt6-macos-amd64: $(QT6_ARCHIVE_PATH) $(DOWNLOAD_DIR)/llvm-project-21.1.8.src.tar.xz build-qt6-linux-amd64 qt6-llvm-cross-host qt6-macos-amd64-osxcross
	$(ONE_BUILD_CHECK)
	$(call LICENSE_ENFORCED_ONLY_ON_LINUX,$@)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(QT6_BUILD_ARGS) $(QT6_MACOS_AMD64_OSXCROSS_ARGS) --build-arg OSX_SDK_IMAGE=qt6-macos-amd64-osxcross --build-arg LLVM_COMPILER_IMAGE=$(QT6_LLVM_COMPILER_IMAGE) --build-arg QT_HOST_IMAGE=$(QT6_LINUX_AMD64_IMAGE) --build-arg QT_SHA256=$(QT6_SOURCE_SHA256) -f docker/qt6/macos/amd64/Dockerfile -t $(QT6_MACOS_AMD64_IMAGE) -t qt6-macos-amd64:llvm21 .

qt6-macos-arm64: $(QT6_ARCHIVE_PATH) $(QT6_OS_VERSION_CHECK_PATH) $(QT6_MACOS_ARM64_SDK_PATH) build-qt6-host
	$(ONE_BUILD_CHECK)
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
qt6-win-amd64-smoke: QT6_SMOKE_QT_DIR := /opt/qt6-windows-amd64-llvm
qt6-win-amd64-smoke: QT6_SMOKE_CMAKE_ARGS := -DCMAKE_TOOLCHAIN_FILE=/opt/longreach-llvm/cmake/toolchain.cmake -DCMAKE_CXX_STANDARD=23 -DCMAKE_CXX_STANDARD_REQUIRED=ON -DSMOKE_REQUIRE_CXX23=ON
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
qt6-linux-amd64-smoke: QT6_SMOKE_QT_DIR := /opt/qt6-linux-amd64-llvm
qt6-linux-amd64-smoke: QT6_SMOKE_CMAKE_ARGS := -DOPENSSL_ROOT_DIR=/opt/openssl-3 -DOPENSSL_USE_STATIC_LIBS=ON -DCMAKE_CXX_STANDARD=23 -DCMAKE_CXX_STANDARD_REQUIRED=ON -DSMOKE_REQUIRE_CXX23=ON -DCMAKE_EXE_LINKER_FLAGS=-no-pie
qt6-linux-amd64-smoke: QT6_SMOKE_COLLECT := $(QT6_COLLECT_ELF)
qt6-linux-amd64-smoke: QT6_SMOKE_RUN := $(QT6_RUN_OFFSCREEN)
qt6-linux-amd64-smoke:
	$(qt6-build-smoke)

qt6-linux-arm64-smoke: QT6_SMOKE_IMAGE := $(QT6_LINUX_ARM64_IMAGE)
qt6-linux-arm64-smoke: QT6_SMOKE_QT_DIR := /opt/qt6-linux-arm64-llvm
qt6-linux-arm64-smoke: QT6_SMOKE_CMAKE_ARGS := -DCMAKE_TOOLCHAIN_FILE=/opt/longreach-llvm/cmake/toolchain.cmake -DOPENSSL_ROOT_DIR=/opt/openssl-3 -DOPENSSL_USE_STATIC_LIBS=ON -DCMAKE_CXX_STANDARD=23 -DCMAKE_CXX_STANDARD_REQUIRED=ON -DSMOKE_REQUIRE_CXX23=ON -DCMAKE_EXE_LINKER_FLAGS=-no-pie
qt6-linux-arm64-smoke: QT6_SMOKE_COLLECT := $(QT6_COLLECT_ELF)
qt6-linux-arm64-smoke: QT6_SMOKE_RUN := $(QT6_RUN_NONE)
qt6-linux-arm64-smoke:
	$(qt6-build-smoke)

qt6-macos-amd64-smoke: QT6_SMOKE_IMAGE := $(QT6_MACOS_AMD64_IMAGE)
qt6-macos-amd64-smoke: QT6_SMOKE_QT_DIR := /opt/qt6-macos-amd64-llvm
qt6-macos-amd64-smoke: QT6_SMOKE_CMAKE_ARGS := -DCMAKE_TOOLCHAIN_FILE=/opt/longreach-llvm/cmake/toolchain.cmake -DCMAKE_CXX_STANDARD=23 -DCMAKE_CXX_STANDARD_REQUIRED=ON -DSMOKE_REQUIRE_CXX23=ON -DCMAKE_MACOSX_BUNDLE=TRUE -DOSXCROSS_SDK_VERSION=$(QT6_MACOS_SDK_VERSION) -DCMAKE_OSX_DEPLOYMENT_TARGET=$(QT6_MACOS_DEPLOYMENT_TARGET)
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


$(eval $(call ensure-build-image,qt6-llvm-compiler,$(QT6_LLVM_COMPILER_IMAGE)))
$(eval $(call ensure-build-image,qt6-linux-arm64-llvm-runtime,$(QT6_ARM64_LLVM_RUNTIME_IMAGE),qt6-llvm-compiler))

$(eval $(call simple-build-targets,qt6-win-amd64,qt6-win-amd64,QT6_WIN_AMD64_IMAGE,qt6-win-amd64-smoke,,qt6-linux-amd64 qt6-llvm-compiler))
$(eval $(call simple-build-targets,qt6-win-arm64,qt6-win-arm64,QT6_WIN_ARM64_IMAGE,qt6-win-arm64-smoke,,qt6-host))
$(eval $(call simple-build-targets,qt6-linux-amd64,qt6-linux-amd64,QT6_LINUX_AMD64_IMAGE,qt6-linux-amd64-smoke,,qt6-llvm-compiler))
$(eval $(call simple-build-targets,qt6-linux-arm64,qt6-linux-arm64,QT6_LINUX_ARM64_IMAGE,qt6-linux-arm64-smoke,,qt6-linux-amd64 qt6-llvm-compiler))
$(eval $(call simple-build-targets,qt6-macos-amd64,qt6-macos-amd64,QT6_MACOS_AMD64_IMAGE,qt6-macos-amd64-smoke,,qt6-linux-amd64 qt6-llvm-compiler))
$(eval $(call simple-build-targets,qt6-macos-arm64,qt6-macos-arm64,QT6_MACOS_ARM64_IMAGE,qt6-macos-arm64-smoke,,qt6-host))

# QT6_SOURCE goes into downloads/ before ensure-image.py fingerprints the
# archive there; otherwise an image built from the old one would look current.
ifneq ($(QT6_SOURCE),)
build-qt6-host $(foreach t,win-amd64 win-arm64 linux-amd64 linux-arm64 macos-amd64 macos-arm64,build-qt6-$(t) build-qt6-$(t)-examples): $(QT6_ARCHIVE_PATH)
endif
