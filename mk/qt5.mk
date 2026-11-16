# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 5.15.19: Windows from XP SP3, Linux from Ubuntu 10.04, macOS from 10.6.
# Images are qt5-<os>-<arch>-<licence profile>.

QT5_VERSION ?= 5.15.19
QT5_SERIES := $(basename $(QT5_VERSION))

QT5_WIN_I386_IMAGE := qt5-win-i386-llvm21$(LICENSE_SUFFIX)
QT5_WIN_AMD64_IMAGE := qt5-win-amd64-llvm21$(LICENSE_SUFFIX)
QT5_WIN_ARM64_IMAGE := qt5-win-arm64$(LICENSE_SUFFIX)
QT5_LINUX_I386_IMAGE := qt5-linux-i386-llvm21$(LICENSE_SUFFIX)
QT5_LINUX_AMD64_IMAGE := qt5-linux-amd64-llvm21$(LICENSE_SUFFIX)
QT5_LINUX_ARM64_IMAGE := qt5-linux-arm64-llvm21$(LICENSE_SUFFIX)
QT5_MACOS_AMD64_IMAGE := qt5-macos-amd64-llvm21$(LICENSE_SUFFIX)
QT5_MACOS_ARM64_IMAGE := qt5-macos-arm64$(LICENSE_SUFFIX)
QT5_MACOS_I386_IMAGE := qt5-macos-i386-llvm21$(LICENSE_SUFFIX)

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

# Oldest macOS the binaries load on: Qt 4.8's 10.6 on Intel, 11.0 on Apple
# silicon.
QT5_MACOS_TARGET_AMD64 ?= 10.6
QT5_MACOS_TARGET_ARM64 ?= 11.0

# libc++ and libc++abi for 10.6, which has none: built from this LLVM release
# and linked statically (scripts/build/qt5-macos/build-libcxx.sh).
QT5_LLVM_SRC_VERSION ?= 14.0.6
QT5_LLVM_SRC_ARCHIVE := llvm-project-$(QT5_LLVM_SRC_VERSION).src.tar.xz
QT5_LLVM_SRC_PATH := $(DOWNLOAD_DIR)/$(QT5_LLVM_SRC_ARCHIVE)
QT5_LLVM_SRC_URL ?= https://github.com/llvm/llvm-project/releases/download/llvmorg-$(QT5_LLVM_SRC_VERSION)/$(QT5_LLVM_SRC_ARCHIVE)
QT5_LLVM_SRC_SHA256 ?= 8b3cfd7bc695bd6cea0f37f53f0981f34f87496e79e2529874fd03a2f9dd3a8a

# The i386 target links against the i386 libraries of the 10.7 SDK, which
# Apple ships only inside Xcode 4.3 to 4.6; this is the copy osxcross users
# take, pinned by SHA256.
QT5_MACOS_I386_LINK_SDK ?= MacOSX10.7.sdk.tar.xz
QT5_MACOS_I386_LINK_SDK_PATH := $(DOWNLOAD_DIR)/$(QT5_MACOS_I386_LINK_SDK)
QT5_MACOS_I386_LINK_SDK_URL ?= https://github.com/phracker/MacOSX-SDKs/releases/download/11.3/MacOSX10.7.sdk.tar.xz
QT5_MACOS_I386_LINK_SDK_SHA256 ?= e5cf1c4026fa2b538201268d1b057854eb6e47676ff31a336d19b981c6fd4d2a
QT5_MACOS_BUILD_ARGS = $(QT5_BUILD_ARGS) --build-arg LAB_GIT="$(LAB_GIT)" --build-arg OSXCROSS_REF="$(OSXCROSS_REF)"

QT5_BUILD_ARGS = --build-arg QT_FULL_VERSION=$(QT5_VERSION) --build-arg OPENSSL_VERSION=$(OPENSSL_VERSION) --build-arg PARALLEL_JOBS=$(PARALLEL_JOBS) --build-arg DOWNLOAD_DIR=$(DOWNLOAD_DIR) --build-arg LICENSE_PROFILE=$(LICENSE_PROFILE)
QT5_WINDOWS_BUILD_ARGS = $(QT5_BUILD_ARGS) --build-arg QT_OPENGL_CONFIG="$(QT5_OPENGL_CONFIG)"

QT5_INPUTS := $(QT5_ARCHIVE_PATH)

.PHONY: download-qt5 download-qt5-macos-sdk download-qt5-llvm-src download-qt5-macos-i386-link-sdk \
        qt5-win-i386 qt5-win-amd64 qt5-win-arm64 qt5-linux-i386 qt5-linux-amd64 qt5-linux-arm64 \
        qt5-macos-amd64 qt5-macos-arm64 qt5-macos-i386 qt5-extract-tests qt5-package-tests

download-qt5: $(QT5_ARCHIVE_PATH)

$(QT5_ARCHIVE_PATH):
	$(PYTHON) scripts/fetch/fetch.py "$(QT5_ARCHIVE_URL)" "$@" "$(QT5_ARCHIVE_SHA256)"

# Windows on ARM starts at Windows 10; the same patches apply.
qt5-win-arm64: $(QT5_INPUTS) $(LLVM_MINGW_PATH)
	$(ONE_BUILD_CHECK)
	$(call LICENSE_ENFORCED_ONLY_ON_LINUX,$@)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(SOURCE_ARGS) $(QT5_BUILD_ARGS) --build-arg QT_OPENGL_CONFIG="$(QT5_OPENGL_CONFIG)" --build-arg LLVM_MINGW_ARCHIVE="$(LLVM_MINGW_ARCHIVE)" --build-arg LLVM_MINGW_SHA256="$(LLVM_MINGW_SHA256)" -f docker/qt5/windows/arm64/Dockerfile -t $(QT5_WIN_ARM64_IMAGE) .

$(QT5_LLVM_SRC_PATH):
	$(PYTHON) scripts/fetch/fetch.py "$(QT5_LLVM_SRC_URL)" "$@" "$(QT5_LLVM_SRC_SHA256)"

download-qt5-llvm-src: $(QT5_LLVM_SRC_PATH)

$(QT5_MACOS_I386_LINK_SDK_PATH):
	$(PYTHON) scripts/fetch/fetch.py "$(QT5_MACOS_I386_LINK_SDK_URL)" "$@" "$(QT5_MACOS_I386_LINK_SDK_SHA256)"

download-qt5-macos-i386-link-sdk: $(QT5_MACOS_I386_LINK_SDK_PATH)

# The common ARM64 LLVM runtime is built against CentOS 7's glibc 2.17.
QT5_ARM64_LLVM_ARGS = $(SOURCE_ARGS) $(QT5_BUILD_ARGS) --build-arg LLVM_TOOLCHAIN_IMAGE=$(QT6_ARM64_LLVM_RUNTIME_IMAGE) --build-arg QT_DISTRO=$(QT5_ARCHIVE) --build-arg QT_SHA256=$(QT5_ARCHIVE_SHA256) --build-arg OPENSSL_DISTRO=$(OPENSSL_ARCHIVE)

.PHONY: qt5-linux-arm64-examples build-qt5-linux-arm64 build-qt5-linux-arm64-examples
.PHONY: qt5-linux-arm64-llvm qt5-linux-arm64-llvm-examples

qt5-linux-arm64: $(QT5_INPUTS) $(OPENSSL_PATH) build-qt6-linux-arm64-llvm-runtime
qt5-linux-arm64 qt5-linux-arm64-smoke:
	$(ONE_BUILD_CHECK)
	$(if $(filter-out %-smoke,$@),$(PYTHON) scripts/fetch/qt5-lucid-fetch.py --sources-only)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(QT5_ARM64_LLVM_ARGS) --target $(if $(filter %-smoke,$@),examples,sdk) $(if $(filter %-smoke,$@),--build-arg SDK_IMAGE=$(QT5_LINUX_ARM64_IMAGE)) -f docker/qt5/linux/arm64/Dockerfile -t $(QT5_LINUX_ARM64_IMAGE)$(if $(filter %-smoke,$@),-examples) .
	$(if $(filter %-smoke,$@),$(MAKE) qt5-extract-tests QT5_IMAGE=$(QT5_LINUX_ARM64_IMAGE))

qt5-linux-arm64-llvm: build-qt5-linux-arm64
qt5-linux-arm64-llvm-examples: qt5-linux-arm64-examples

# Build both Lucid SDKs with the same recipe and their pinned sysroot inputs.
QT5_LUCID_TARGETS := qt5-linux-amd64 qt5-linux-i386
QT5_LUCID_ARCH = $(if $(filter qt5-linux-i386%,$@),i386,amd64)
QT5_LUCID_PLATFORM = $(if $(filter i386,$(QT5_LUCID_ARCH)),386,amd64)
QT5_LUCID_IMAGE = $(if $(filter i386,$(QT5_LUCID_ARCH)),$(QT5_LINUX_I386_IMAGE),$(QT5_LINUX_AMD64_IMAGE))
QT5_LUCID_LLVM_COMPILER ?= $(QT6_LLVM_COMPILER_IMAGE)
QT5_LUCID_ARGS = $(SOURCE_ARGS) $(QT5_BUILD_ARGS) --build-arg QT_DISTRO=$(QT5_ARCHIVE) --build-arg QT_SHA256=$(QT5_ARCHIVE_SHA256) --build-arg OPENSSL_DISTRO=$(OPENSSL_ARCHIVE) --build-arg LUCID_ARCH=$(QT5_LUCID_ARCH) --build-arg LUCID_PLATFORM=$(QT5_LUCID_PLATFORM) --build-arg LLVM_COMPILER_IMAGE=$(QT5_LUCID_LLVM_COMPILER)

.PHONY: $(addsuffix -examples,$(QT5_LUCID_TARGETS)) $(addprefix build-,$(QT5_LUCID_TARGETS)) $(addprefix build-,$(addsuffix -examples,$(QT5_LUCID_TARGETS)))
.PHONY: $(addsuffix -llvm,$(QT5_LUCID_TARGETS)) $(addsuffix -llvm-examples,$(QT5_LUCID_TARGETS))


$(QT5_LUCID_TARGETS): $(QT5_INPUTS) $(OPENSSL_PATH) $(GCC55_PATH) $(DOWNLOAD_DIR)/llvm-project-21.1.8.src.tar.xz build-qt6-llvm-compiler
$(QT5_LUCID_TARGETS) $(addsuffix -smoke,$(QT5_LUCID_TARGETS)):
	$(ONE_BUILD_CHECK)
	$(if $(filter-out %-smoke,$@),$(PYTHON) scripts/fetch/qt5-lucid-fetch.py --arch $(QT5_LUCID_ARCH))
	docker image inspect --format "{{.Id}}" $(QT5_LUCID_LLVM_COMPILER)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) --platform linux/amd64 $(QT5_LUCID_ARGS) --target $(if $(filter %-smoke,$@),examples,sdk) $(if $(filter %-smoke,$@),--build-arg SDK_IMAGE=$(QT5_LUCID_IMAGE)) -f docker/qt5/linux/Dockerfile -t $(QT5_LUCID_IMAGE)$(if $(filter %-smoke,$@),-examples) .
	$(if $(filter %-smoke,$@),$(MAKE) qt5-extract-tests QT5_IMAGE=$(QT5_LUCID_IMAGE))

$(foreach target,$(QT5_LUCID_TARGETS),$(eval $(target)-llvm: build-$(target))$(eval $(target)-llvm-examples: $(target)-examples))

# XP uses the Bionic MinGW-w64 v5 CRT and static OpenSSL inputs.
QT5_XP_TARGETS := qt5-win-i386 qt5-win-amd64
QT5_XP_ARCH = $(if $(filter qt5-win-amd64%,$@),amd64,i386)
QT5_XP_CROSS = $(if $(filter amd64,$(QT5_XP_ARCH)),x86_64,i686)-w64-mingw32
QT5_XP_OPENSSL_LIBDIR = $(if $(filter amd64,$(QT5_XP_ARCH)),lib64,lib)
QT5_XP_IMAGE = $(if $(filter amd64,$(QT5_XP_ARCH)),$(QT5_WIN_AMD64_IMAGE),$(QT5_WIN_I386_IMAGE))
QT5_XP_LLVM_COMPILER ?= $(QT6_LLVM_COMPILER_IMAGE)
QT5_XP_ARGS = $(SOURCE_ARGS) $(QT5_WINDOWS_BUILD_ARGS) --build-arg XP_ARCH=$(QT5_XP_ARCH) --build-arg XP_CROSS=$(QT5_XP_CROSS) --build-arg XP_OPENSSL_LIBDIR=$(QT5_XP_OPENSSL_LIBDIR) --build-arg LLVM_COMPILER_IMAGE=$(QT5_XP_LLVM_COMPILER) --build-arg QT_DISTRO=$(QT5_ARCHIVE) --build-arg QT_SHA256=$(QT5_ARCHIVE_SHA256) --build-arg OPENSSL_DISTRO=$(OPENSSL_ARCHIVE)

.PHONY: $(addsuffix -examples,$(QT5_XP_TARGETS)) $(addprefix build-,$(QT5_XP_TARGETS)) $(addprefix build-,$(addsuffix -examples,$(QT5_XP_TARGETS)))
.PHONY: $(addsuffix -llvm,$(QT5_XP_TARGETS)) $(addsuffix -llvm-examples,$(QT5_XP_TARGETS)) $(addsuffix -llvm-toolchain,$(QT5_XP_TARGETS))
QT5_XP_I386_TOOLCHAIN_IMAGE ?= qt5-win-i386:llvm21-toolchain
QT5_XP_AMD64_TOOLCHAIN_IMAGE ?= qt5-win-amd64:llvm21-toolchain
QT5_XP_TOOLCHAIN_IMAGE = $(if $(filter amd64,$(QT5_XP_ARCH)),$(QT5_XP_AMD64_TOOLCHAIN_IMAGE),$(QT5_XP_I386_TOOLCHAIN_IMAGE))

$(QT5_XP_TARGETS): $(QT5_INPUTS) $(OPENSSL_PATH) $(DOWNLOAD_DIR)/llvm-project-21.1.8.src.tar.xz build-qt6-llvm-compiler
$(QT5_XP_TARGETS) $(addsuffix -smoke,$(QT5_XP_TARGETS)):
	$(ONE_BUILD_CHECK)
	$(call LICENSE_ENFORCED_ONLY_ON_LINUX,$@)
	docker image inspect --format "{{.Id}}" $(QT5_XP_LLVM_COMPILER)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(QT5_XP_ARGS) --target $(if $(filter %-smoke,$@),examples,sdk) $(if $(filter %-smoke,$@),--build-arg SDK_IMAGE=$(QT5_XP_IMAGE)) -f docker/qt5/windows/Dockerfile -t $(QT5_XP_IMAGE)$(if $(filter %-smoke,$@),-examples) .
	$(if $(filter %-smoke,$@),$(MAKE) qt5-extract-tests QT5_IMAGE=$(QT5_XP_IMAGE))

$(foreach target,$(QT5_XP_TARGETS),$(eval $(target)-llvm: build-$(target))$(eval $(target)-llvm-examples: $(target)-examples))

# The Qt 4 Windows SDKs use the same XP inputs.
$(addsuffix -llvm-toolchain,$(QT5_XP_TARGETS)): $(OPENSSL_PATH) $(DOWNLOAD_DIR)/llvm-project-21.1.8.src.tar.xz build-qt6-llvm-compiler
	$(ONE_BUILD_CHECK)
	docker image inspect --format "{{.Id}}" $(QT5_XP_LLVM_COMPILER)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(QT5_XP_ARGS) --target toolchain -f docker/qt5/windows/Dockerfile -t $(QT5_XP_TOOLCHAIN_IMAGE) .

# ARM64 uses the Windows 10 UCRT toolchain already built from upstream LLVM.
QT5_WINDOWS_ARM64_LLVM_IMAGE := qt5-win-arm64:llvm21
QT5_WINDOWS_ARM64_LLVM_TOOLCHAIN ?= qt6-win-arm64:llvm21-toolchain
QT5_WINDOWS_ARM64_LLVM_ARGS = --build-arg BASE_REGISTRY=$(BASE_REGISTRY) \
    $(if $(APT_SNAPSHOT),--build-arg APT_SNAPSHOT=$(APT_SNAPSHOT)) \
    --build-arg LLVM_TOOLCHAIN_IMAGE=$(QT5_WINDOWS_ARM64_LLVM_TOOLCHAIN) \
    --build-arg PARALLEL_JOBS=$(PARALLEL_JOBS)

.PHONY: qt5-win-arm64-llvm qt5-win-arm64-llvm-examples
BUILD_TARGETS += qt5-win-arm64-llvm
qt5-win-arm64-llvm qt5-win-arm64-llvm-examples: $(DOWNLOAD_DIR)/qt-everywhere-opensource-src-5.15.19.tar.xz
	$(ONE_BUILD_CHECK)
	$(if $(filter-out gpl-enabled,$(LICENSE_PROFILE)),$(error $@: only LICENSE_PROFILE=gpl-enabled is supported))
	docker image inspect --format "{{.Id}}" $(QT5_WINDOWS_ARM64_LLVM_TOOLCHAIN)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(QT5_WINDOWS_ARM64_LLVM_ARGS) --target $(if $(filter %-examples,$@),examples,sdk) -f docker/qt5/windows/arm64/Dockerfile-llvm -t $(QT5_WINDOWS_ARM64_LLVM_IMAGE) .
	$(if $(filter %-examples,$@),$(MAKE) qt5-extract-tests QT5_IMAGE=$(QT5_WINDOWS_ARM64_LLVM_IMAGE) QT5_VERSION=5.15.19 OPENSSL_VERSION=)

# The two Snow Leopard SDKs share the patched emulated TLS compiler.
QT5_SNOW_TARGETS := qt5-macos-amd64 qt5-macos-i386
QT5_SNOW_ARCH = $(if $(filter qt5-macos-i386%,$@),i386,amd64)
QT5_SNOW_IMAGE = $(if $(filter i386,$(QT5_SNOW_ARCH)),$(QT5_MACOS_I386_IMAGE),$(QT5_MACOS_AMD64_IMAGE))
QT5_MACOS_SNOW_LLVM_COMPILER_IMAGE ?= longreach-llvm:21.1.8-snow-tls
QT5_MACOS_SNOW_OSXCROSS_IMAGE ?= qt5-macos-snow-osxcross
QT5_SNOW_OSXCROSS_ARGS = --build-arg OSX_SDK="$(QT5_MACOS_SDK)" --build-arg LLVM_SRC="$(QT5_LLVM_SRC_ARCHIVE)"
QT5_SNOW_ARGS = $(SOURCE_ARGS) $(QT5_MACOS_BUILD_ARGS) $(QT5_SNOW_OSXCROSS_ARGS) --build-arg QT_DISTRO=$(QT5_ARCHIVE) --build-arg QT_SHA256=$(QT5_ARCHIVE_SHA256) --build-arg OPENSSL_DISTRO=$(OPENSSL_ARCHIVE)
QT5_SNOW_I386_ARGS = --build-arg SNOW_COMPILER_IMAGE=$(QT5_MACOS_SNOW_LLVM_COMPILER_IMAGE) --build-arg OSXCROSS_IMAGE=$(QT5_MACOS_SNOW_OSXCROSS_IMAGE) --build-arg I386_LINK_SDK="$(QT5_MACOS_I386_LINK_SDK)"
QT5_SNOW_AMD64_ARGS = --build-arg LLVM_COMPILER_IMAGE=$(QT5_MACOS_SNOW_LLVM_COMPILER_IMAGE) --build-arg LEGACY_MACOS_SDK="$(QT5_MACOS_I386_LINK_SDK)" --build-arg MACOS_DEPLOYMENT_TARGET="$(QT5_MACOS_TARGET_AMD64)"

.PHONY: qt5-macos-snow-llvm-compiler qt5-macos-snow-osxcross
qt5-macos-snow-llvm-compiler: $(DOWNLOAD_DIR)/llvm-project-21.1.8.src.tar.xz build-qt6-llvm-compiler
	$(ONE_BUILD_CHECK)
	docker image inspect --format "{{.Id}}" $(QT6_LLVM_COMPILER_IMAGE)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) --platform linux/amd64 --build-arg LLVM_COMPILER_IMAGE=$(QT6_LLVM_COMPILER_IMAGE) --build-arg PARALLEL_JOBS=$(PARALLEL_JOBS) --target snow-compiler -f docker/qt5/macos/i386/Dockerfile -t $(QT5_MACOS_SNOW_LLVM_COMPILER_IMAGE) .

qt5-macos-snow-osxcross: $(QT5_MACOS_SDK_PATH) $(QT5_LLVM_SRC_PATH)
	$(ONE_BUILD_CHECK)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(SOURCE_ARGS) $(QT5_MACOS_BUILD_ARGS) $(QT5_SNOW_OSXCROSS_ARGS) --platform linux/amd64 --target osxcross -f docker/qt5/macos/amd64/Dockerfile -t $(QT5_MACOS_SNOW_OSXCROSS_IMAGE) .

.PHONY: $(addsuffix -examples,$(QT5_SNOW_TARGETS)) $(addprefix build-,$(QT5_SNOW_TARGETS)) $(addprefix build-,$(addsuffix -examples,$(QT5_SNOW_TARGETS)))
.PHONY: $(addsuffix -llvm,$(QT5_SNOW_TARGETS)) $(addsuffix -llvm-examples,$(QT5_SNOW_TARGETS))


QT5_MACOS_I386_CMAKE := cmake-3.28.6-linux-x86_64.tar.gz
QT5_MACOS_I386_CMAKE_PATH := $(DOWNLOAD_DIR)/$(QT5_MACOS_I386_CMAKE)
QT5_MACOS_I386_CMAKE_SHA256 := 931e3c0d546ee03ca72bb147ccd9b49e3b6252f765f66bf21b9d165519940458
QT5_MACOS_I386_CMAKE_URL := https://github.com/Kitware/CMake/releases/download/v3.28.6/$(QT5_MACOS_I386_CMAKE)

$(QT5_MACOS_I386_CMAKE_PATH):
	$(PYTHON) scripts/fetch/fetch.py "$(QT5_MACOS_I386_CMAKE_URL)" "$@" "$(QT5_MACOS_I386_CMAKE_SHA256)"

qt5-macos-i386: $(QT5_MACOS_I386_CMAKE_PATH) build-qt5-macos-snow-osxcross
$(QT5_SNOW_TARGETS): $(QT5_INPUTS) $(OPENSSL_PATH) $(QT5_MACOS_SDK_PATH) $(QT5_LLVM_SRC_PATH) $(QT5_MACOS_I386_LINK_SDK_PATH) build-qt5-macos-snow-llvm-compiler
$(QT5_SNOW_TARGETS) $(addsuffix -smoke,$(QT5_SNOW_TARGETS)):
	$(ONE_BUILD_CHECK)
	$(call LICENSE_ENFORCED_ONLY_ON_LINUX,$@)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(QT5_SNOW_ARGS) $(if $(filter i386,$(QT5_SNOW_ARCH)),$(QT5_SNOW_I386_ARGS),$(QT5_SNOW_AMD64_ARGS)) --platform linux/amd64 --target $(if $(filter %-smoke,$@),examples,sdk) $(if $(filter %-smoke,$@),--build-arg SDK_IMAGE=$(QT5_SNOW_IMAGE)) -f docker/qt5/macos/$(QT5_SNOW_ARCH)/Dockerfile -t $(QT5_SNOW_IMAGE)$(if $(filter %-smoke,$@),-examples) .
	$(if $(filter %-smoke,$@),$(MAKE) qt5-extract-tests QT5_IMAGE=$(QT5_SNOW_IMAGE))

$(foreach target,$(QT5_SNOW_TARGETS),$(eval $(target)-llvm: build-$(target))$(eval $(target)-llvm-examples: $(target)-examples))

QT5_MACOS_ARM64_LLVM_IMAGE := qt5-macos-arm64:llvm21
QT5_MACOS_ARM64_LLVM_PLATFORM ?= qt5-macos-arm64:latest
QT5_MACOS_ARM64_LLVM_TOOLCHAIN ?= qt6-macos-arm64:llvm21-toolchain
QT5_MACOS_ARM64_LLVM_ARGS = --build-arg MACOS_PLATFORM_IMAGE=$(QT5_MACOS_ARM64_LLVM_PLATFORM) \
    --build-arg LLVM_TOOLCHAIN_IMAGE=$(QT5_MACOS_ARM64_LLVM_TOOLCHAIN) \
    --build-arg PARALLEL_JOBS=$(PARALLEL_JOBS)

.PHONY: qt5-macos-arm64-llvm qt5-macos-arm64-llvm-examples
BUILD_TARGETS += qt5-macos-arm64-llvm
qt5-macos-arm64-llvm qt5-macos-arm64-llvm-examples: $(DOWNLOAD_DIR)/qt-everywhere-opensource-src-5.15.19.tar.xz
	$(ONE_BUILD_CHECK)
	$(if $(filter-out gpl-enabled,$(LICENSE_PROFILE)),$(error $@: only LICENSE_PROFILE=gpl-enabled is supported))
	docker image inspect --format "{{.Id}}" $(QT5_MACOS_ARM64_LLVM_PLATFORM) $(QT5_MACOS_ARM64_LLVM_TOOLCHAIN)
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(QT5_MACOS_ARM64_LLVM_ARGS) --target $(if $(filter %-examples,$@),examples,sdk) -f docker/qt5/macos/arm64/Dockerfile-llvm -t $(QT5_MACOS_ARM64_LLVM_IMAGE) .
	$(if $(filter %-examples,$@),$(MAKE) qt5-extract-tests QT5_IMAGE=$(QT5_MACOS_ARM64_LLVM_IMAGE) QT5_VERSION=5.15.19 OPENSSL_VERSION=)

qt5-macos-arm64: $(QT5_INPUTS) $(QT5_MACOS_SDK_PATH) $(QT5_LLVM_SRC_PATH)
	$(ONE_BUILD_CHECK)
	$(call LICENSE_ENFORCED_ONLY_ON_LINUX,$@)
	@echo "Using SDK $(QT5_MACOS_SDK), deployment target $(QT5_MACOS_TARGET_ARM64)"
	docker build $(DOCKER_CACHE_FLAG) $(DOCKER_BUILD_FLAGS) $(SOURCE_ARGS) $(QT5_MACOS_BUILD_ARGS) --build-arg OSX_SDK="$(QT5_MACOS_SDK)" --build-arg MACOS_DEPLOYMENT_TARGET="$(QT5_MACOS_TARGET_ARM64)" --build-arg LLVM_SRC="$(QT5_LLVM_SRC_ARCHIVE)" -f docker/qt5/macos/arm64/Dockerfile -t $(QT5_MACOS_ARM64_IMAGE) .

# Unpacked in a container: the SDK is thousands of symlinks a Windows
# filesystem cannot hold. The command is one `bash -c` string so that Git Bash
# does not rewrite /scripts/... into a Windows path. amd64, since
# snapshot.ubuntu.com has no ubuntu-ports; under the download lock, since
# every Qt 5 macOS target needs the SDK.
download-qt5-macos-sdk: $(QT5_MACOS_SDK_PATH)

$(QT5_MACOS_SDK_PATH):
	$(PYTHON) -c "import os, sys; os.makedirs(sys.argv[1], exist_ok=True)" "$(DOWNLOAD_DIR)"
	$(PYTHON) scripts/fetch/fetch.py --locked "$@" docker run --rm --platform linux/amd64 -v "$(CURDIR):/work" -v "$(CURDIR)/scripts:/scripts:ro" \
		-e SDK_TARBALL="$(QT5_MACOS_SDK_PATH)" -e SDK_DIR="$(QT5_MACOS_SDK_DIR)" \
		-e SDK_PKG_URL="$(QT5_MACOS_SDK_PKG_URL)" -e SDK_PKG_SHA256="$(QT5_MACOS_SDK_PKG_SHA256)" \
		-e APT_SNAPSHOT="$(APT_SNAPSHOT)" \
		$(BASE_REGISTRY)/ubuntu:22.04@sha256:5ec03bb3441e8b0bf3b4f9cd4629a1ae763010dc3035bb8da3ae6cf026486401 \
		bash -c "bash /scripts/fetch/fetch-macos-sdk.sh"

# Copy an image's test suite to artifacts/tests-<image>/, with the same
# LICENSE_PROFILE as its build:
#   make qt5-extract-tests QT5_IMAGE=qt5-macos-amd64-llvm21
QT5_IMAGE ?= $(QT5_WIN_I386_IMAGE)
QT5_MIGRATED_IMAGES := $(QT5_WIN_I386_IMAGE) $(QT5_WIN_AMD64_IMAGE) $(QT5_LINUX_I386_IMAGE) $(QT5_LINUX_AMD64_IMAGE) $(QT5_LINUX_ARM64_IMAGE) $(QT5_MACOS_I386_IMAGE) $(QT5_MACOS_AMD64_IMAGE)
QT5_TESTS_IMAGE ?= $(if $(filter $(QT5_MIGRATED_IMAGES),$(QT5_IMAGE)),$(QT5_IMAGE)-examples,$(QT5_IMAGE))
QT5_TESTS_NAME := tests-$(subst :,-,$(QT5_IMAGE))
QT5_TESTS_OUT := $(ARTIFACTS_DIR)/$(QT5_TESTS_NAME)
QT5_TESTS_PACKAGE := $(QT5_TESTS_OUT).tar.gz
ifneq ($(filter qt5-linux-amd64-llvm21% qt5-linux-i386-llvm21% qt5-linux-amd64:llvm21 qt5-linux-i386:llvm21,$(QT5_IMAGE)),)
QT5_TESTS_OPENSSL_HEADER ?= /opt/openssl-lucid/include/openssl/opensslv.h
else ifneq ($(filter qt5-win-amd64-llvm21% qt5-win-i386-llvm21% qt5-win-amd64:llvm21 qt5-win-i386:llvm21 qt5-macos-amd64-llvm21% qt5-macos-i386-llvm21%,$(QT5_IMAGE)),)
QT5_TESTS_OPENSSL_HEADER ?= /opt/openssl-3/include/openssl/opensslv.h
endif
QT5_TESTS_OPENSSL_ARG = $(if $(QT5_TESTS_OPENSSL_HEADER),--openssl-header "$(QT5_TESTS_OPENSSL_HEADER)",--openssl-version "$(OPENSSL_VERSION)")

qt5-extract-tests:
	$(PYTHON) -c "import os, sys; os.makedirs(sys.argv[1], exist_ok=True)" "$(QT5_TESTS_OUT)"
	docker run --rm -v "$(CURDIR)/$(QT5_TESTS_OUT):/out" -v "$(CURDIR)/scripts:/scripts:ro" \
		$(QT5_TESTS_IMAGE) "bash /scripts/tests/extract.sh"
	$(PYTHON) scripts/tests/write_manifest.py --out "$(QT5_TESTS_OUT)" --image "$(QT5_IMAGE)" --qt-version "$(QT5_VERSION)" $(QT5_TESTS_OPENSSL_ARG) --license-profile "$(LICENSE_PROFILE)"
	@echo "-> $(QT5_TESTS_OUT)"

qt5-package-tests: qt5-extract-tests
	docker run --rm -v "$(CURDIR)/$(ARTIFACTS_DIR):/artifacts" \
		$(QT5_IMAGE) "tar -czf /artifacts/$(QT5_TESTS_NAME).tar.gz -C /artifacts/$(QT5_TESTS_NAME) . && sha256sum /artifacts/$(QT5_TESTS_NAME).tar.gz > /artifacts/$(QT5_TESTS_NAME).tar.gz.sha256"
	@echo "-> $(QT5_TESTS_PACKAGE)"


$(eval $(call simple-build-targets,qt5-win-arm64,qt5-win-arm64,QT5_WIN_ARM64_IMAGE,qt5-extract-tests,QT5_IMAGE=$(QT5_WIN_ARM64_IMAGE),))
$(eval $(call simple-build-targets,qt5-macos-arm64,qt5-macos-arm64,QT5_MACOS_ARM64_IMAGE,qt5-extract-tests,QT5_IMAGE=$(QT5_MACOS_ARM64_IMAGE),))
$(eval $(call simple-build-targets,qt5-linux-arm64,qt5-linux-arm64,QT5_LINUX_ARM64_IMAGE,qt5-linux-arm64-smoke,,qt6-linux-arm64-llvm-runtime qt6-llvm-compiler))
.PHONY: qt5-linux-arm64-smoke
$(eval $(call simple-build-targets,qt5-linux-i386,qt5-linux-i386,QT5_LINUX_I386_IMAGE,qt5-linux-i386-smoke,,qt6-llvm-compiler))
.PHONY: qt5-linux-i386-smoke
$(eval $(call simple-build-targets,qt5-linux-amd64,qt5-linux-amd64,QT5_LINUX_AMD64_IMAGE,qt5-linux-amd64-smoke,,qt6-llvm-compiler))
.PHONY: qt5-linux-amd64-smoke
$(eval $(call simple-build-targets,qt5-win-i386,qt5-win-i386,QT5_WIN_I386_IMAGE,qt5-win-i386-smoke,,qt6-llvm-compiler))
.PHONY: qt5-win-i386-smoke
$(eval $(call simple-build-targets,qt5-win-amd64,qt5-win-amd64,QT5_WIN_AMD64_IMAGE,qt5-win-amd64-smoke,,qt6-llvm-compiler))
.PHONY: qt5-win-amd64-smoke
$(eval $(call simple-build-targets,qt5-macos-i386,qt5-macos-i386,QT5_MACOS_I386_IMAGE,qt5-macos-i386-smoke,,qt6-llvm-compiler qt5-macos-snow-llvm-compiler qt5-macos-snow-osxcross))
.PHONY: qt5-macos-i386-smoke
$(eval $(call simple-build-targets,qt5-macos-amd64,qt5-macos-amd64,QT5_MACOS_AMD64_IMAGE,qt5-macos-amd64-smoke,,qt6-llvm-compiler qt5-macos-snow-llvm-compiler))
.PHONY: qt5-macos-amd64-smoke

$(eval $(call ensure-build-image,qt5-win-i386-llvm-toolchain,$(QT5_XP_I386_TOOLCHAIN_IMAGE),qt6-llvm-compiler))
$(eval $(call ensure-build-image,qt5-win-amd64-llvm-toolchain,$(QT5_XP_AMD64_TOOLCHAIN_IMAGE),qt6-llvm-compiler))
$(eval $(call ensure-build-image,qt5-macos-snow-llvm-compiler,$(QT5_MACOS_SNOW_LLVM_COMPILER_IMAGE),qt6-llvm-compiler))
$(eval $(call ensure-build-image,qt5-macos-snow-osxcross,$(QT5_MACOS_SNOW_OSXCROSS_IMAGE)))
