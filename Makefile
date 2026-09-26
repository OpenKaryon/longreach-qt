# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon

# Longreach: Qt 4.8.7, 5.15.19 and 6.8.4, one build per Qt version, OS and
# architecture (`make qt<N>-<os>-<arch>`). Shared settings are here; each
# generation's inputs, images and targets are in mk/qt4.mk, mk/qt5.mk, mk/qt6.mk.

PROJECT_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

PYTHON ?= python
MODULES ?=
THRESHOLD ?=
PLATFORM ?=
LICENSE_PROFILE ?= gpl-enabled
VALID_LICENSE_PROFILES := lgpl-friendly gpl-enabled commercial-qt
ifeq ($(filter $(LICENSE_PROFILE),$(VALID_LICENSE_PROFILES)),)
$(error LICENSE_PROFILE must be one of: $(VALID_LICENSE_PROFILES))
endif
LICENSE_SUFFIX := -$(LICENSE_PROFILE)

# Compiler jobs inside one image build; Qt links can take several GB each.
PARALLEL_JOBS ?= 6

BUILD_DIR := build
ARTIFACTS_DIR := artifacts

# Every downloaded input, git-ignored. The Dockerfiles take it as a build arg.
DOWNLOAD_DIR ?= downloads

# OpenSSL for the Qt 5 and Qt 6 targets and the 64-bit Qt 4 ones.
OPENSSL_VERSION ?= 3.5.7
OPENSSL_ARCHIVE := openssl-$(OPENSSL_VERSION).tar.gz
OPENSSL_PATH := $(DOWNLOAD_DIR)/$(OPENSSL_ARCHIVE)
OPENSSL_URL ?= https://www.openssl.org/source/$(OPENSSL_ARCHIVE)
OPENSSL_SHA256 ?= a8c0d28a529ca480f9f36cf5792e2cd21984552a3c8e4aa11a24aa31aeac98e8

# LLVM-MinGW for the Windows arm64 targets and Qt 6 Windows. Another release
# needs LLVM_MINGW_VERSION, LLVM_MINGW_ARCHIVE and LLVM_MINGW_SHA256 together.
LLVM_MINGW_VERSION ?= 20241217
LLVM_MINGW_ARCHIVE ?= llvm-mingw-$(LLVM_MINGW_VERSION)-ucrt-ubuntu-20.04-x86_64.tar.xz
LLVM_MINGW_SHA256 ?= cfe4aac3d245a77d8cd0c41bdcd7971b1002c771d3bba2ac39702733b0fb0c12
LLVM_MINGW_PATH := $(DOWNLOAD_DIR)/$(LLVM_MINGW_ARCHIVE)
LLVM_MINGW_URL ?= https://github.com/mstorsjo/llvm-mingw/releases/download/$(LLVM_MINGW_VERSION)/$(LLVM_MINGW_ARCHIVE)

# osxcross has no tags, so a verified commit of our fork; the build log
# records what the ref resolved to.
#   make qt5-macos-amd64 OSXCROSS_REF=master
OSXCROSS_REPO ?= https://github.com/OpenKaryon/osxcross.git
OSXCROSS_REF ?= 27d21e4977c9751d01199c7a226a6faf494c3dd9

ifeq ($(NO_CACHE),1)
DOCKER_CACHE_FLAG := --no-cache
else
DOCKER_CACHE_FLAG :=
endif

# Extra Docker build options, for example --resource=memory=8g.
DOCKER_BUILD_FLAGS ?=

# Recipes run under whatever SHELL is: sh in Git Bash (where OS is still
# Windows_NT), cmd.exe on some Windows installs.
ifeq ($(OS),Windows_NT)
ifeq ($(filter sh sh.exe bash bash.exe,$(notdir $(SHELL))),)
MKDIR_P = cmake -E make_directory "$(1)"
RM_RF   = if exist "$(subst /,\,$(1))" rmdir /s /q "$(subst /,\,$(1))"
else
MKDIR_P = cmake -E make_directory "$(1)"
RM_RF   = rm -rf "$(1)"
endif
else
MKDIR_P = cmake -E make_directory "$(1)"
RM_RF   = rm -rf "$(1)"
endif

# An interrupted download leaves no truncated archive behind.
.DELETE_ON_ERROR:

download-openssl: $(OPENSSL_PATH)

$(OPENSSL_PATH):
	$(PYTHON) scripts/fetch/fetch.py "$(OPENSSL_URL)" "$@" "$(OPENSSL_SHA256)"

download-llvm-mingw: $(LLVM_MINGW_PATH)

$(LLVM_MINGW_PATH):
	$(PYTHON) scripts/fetch/fetch.py "$(LLVM_MINGW_URL)" "$@" "$(LLVM_MINGW_SHA256)"

# build-<target> builds only when an input changed (the image carries a
# fingerprint label); build-<target>-examples also builds its test suite.
# $(1) public name, $(2) SDK target, $(3) image variable, $(4) examples
# target, $(5) examples arguments, $(6) fingerprint settings.
define simple-build-targets
.PHONY: build-$(1) build-$(1)-examples
build-$(1):
	$(PYTHON) scripts/build/ensure-image.py --image "$($(3))" --target "$(2)" --config "$($(6))" --docker-build-flags "$(DOCKER_BUILD_FLAGS)" $(if $(and $(filter qt6-%,$(1)),$(QT6_SOURCE)),--source-file "$(QT6_SOURCE)",) $(if $(filter 1,$(NO_CACHE)),--force,)
build-$(1)-examples:
	$(PYTHON) scripts/build/ensure-image.py --image "$($(3))" --target "$(2)" --config "$($(6))" --docker-build-flags "$(DOCKER_BUILD_FLAGS)" --examples-target "$(4)" --examples-args "$(5)" $(if $(and $(filter qt6-%,$(1)),$(QT6_SOURCE)),--source-file "$(QT6_SOURCE)",) $(if $(filter 1,$(NO_CACHE)),--force,)
endef

# A bare `make` fetches the Qt 5 source archive.
.DEFAULT_GOAL := download-qt5

include $(PROJECT_DIR)mk/qt4.mk
include $(PROJECT_DIR)mk/qt5.mk
include $(PROJECT_DIR)mk/qt6.mk

.PHONY: download-openssl download-llvm-mingw verify-downloads check-coverage regen-db image-sizes clean prune-cache

# Re-check the pinned inputs already in downloads/.
verify-downloads:
	$(foreach f,QT5_ARCHIVE QT4_ARCHIVE OPENSSL QT4_OPENSSL LLVM_MINGW QT6_WIN7_LLVM_MINGW QT5_LLVM_SRC QT5_MACOS_I386_LINK_SDK TIGER_SDK GCC55 JAGUAR_SDK,$(if $(wildcard $($(f)_PATH)),$(PYTHON) scripts/fetch/fetch.py --check "$($(f)_PATH)" "$($(f)_SHA256)" &&) ) echo all present inputs verified

# Public API coverage of tests/ against scripts/tests/qt-api-classes*.txt;
# writes scripts/tests/coverage-gap.txt. No Docker needed.
#   make check-coverage                       every generation, side by side
#   make check-coverage QT=5 MODULES=qtbase   one generation, some modules
#   make check-coverage GATE=1                the repository gate
#   make check-coverage THRESHOLD=90          fail below 90%
#   make check-coverage PLATFORM=all          what each target's SDK exercises
#   make check-coverage COMPARE=1             what changed between Qt 5 and 6
CHECK_ONLY_ARG := $(if $(MODULES),--only=$(MODULES),)
CHECK_THR_ARG  := $(if $(THRESHOLD),--threshold=$(THRESHOLD),$(if $(GATE),--gate,))
CHECK_PLAT_ARG := $(if $(PLATFORM),--platform=$(PLATFORM),)
CHECK_QT_ARG   := $(if $(QT),--qt=$(QT),)
CHECK_CMP_ARG  := $(if $(COMPARE),--compare,)

check-coverage:
	$(PYTHON) scripts/tests/check_coverage.py $(CHECK_ONLY_ARG) $(CHECK_THR_ARG) $(CHECK_PLAT_ARG) $(CHECK_QT_ARG) $(CHECK_CMP_ARG)

# Regenerate the class database from an unpacked Qt source tree (when the Qt
# version changes); the version is read from the directory name, or QT=.
#   make regen-db QT_SRC=path/to/qt-everywhere-src-5.15.19
regen-db:
	$(PYTHON) scripts/audit/qt_api_audit.py "$(QT_SRC)" $(if $(QT),--qt $(QT),)

image-sizes:
	docker images --filter "reference=qt4-*" --format "{{.Repository}}:{{.Tag}}\t{{.Size}}"
	docker images --filter "reference=qt5-*" --format "{{.Repository}}:{{.Tag}}\t{{.Size}}"
	docker images --filter "reference=qt6-*" --format "{{.Repository}}:{{.Tag}}\t{{.Size}}"

clean:
	$(call RM_RF,$(BUILD_DIR))
	$(call RM_RF,$(ARTIFACTS_DIR))

prune-cache:
	docker builder prune -f
	docker image prune -f
