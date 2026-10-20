# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon

# Longreach Qt: Qt 4.8.7, 5.15.19 and 6.8.4, one build per Qt version, OS
# and architecture (`make qt<N>-<os>-<arch>`). Shared settings are here; each
# generation's inputs, images and targets are in mk/qt4.mk, mk/qt5.mk and
# mk/qt6.mk.

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
# The default profile keeps the plain names (qt5-win-amd64); another one is
# added to the image and artifact names so that the two never overwrite.
LICENSE_SUFFIX := $(if $(filter gpl-enabled,$(LICENSE_PROFILE)),,-$(LICENSE_PROFILE))
# lgpl-friendly leaves the GPL-only modules out of the Linux Qt 5/6 images
# only (docs/licensing.md); elsewhere the image would carry the name and
# still contain them, so those recipes refuse it.
LICENSE_ENFORCED_ONLY_ON_LINUX = $(if $(filter lgpl-friendly,$(LICENSE_PROFILE)),$(error $(1): LICENSE_PROFILE=lgpl-friendly is enforced for the Linux Qt 5/6 targets only (docs/licensing.md)))
# Named on the command line, they stop before any download or prerequisite.
LICENSE_REFUSED_GOALS := $(if $(filter lgpl-friendly,$(LICENSE_PROFILE)),$(filter $(foreach t,qt5-win qt5-macos qt6-win qt6-macos,$(t)-% build-$(t)-%),$(MAKECMDGOALS)))
ifneq ($(LICENSE_REFUSED_GOALS),)
$(call LICENSE_ENFORCED_ONLY_ON_LINUX,$(LICENSE_REFUSED_GOALS))
endif

# Compiler jobs inside one image build; Qt links can take several GB each.
PARALLEL_JOBS ?= 6

BUILD_DIR := build
ARTIFACTS_DIR := artifacts

# Every downloaded input, git-ignored. Fixed: the Dockerfiles and the Sarge and
# Lucid fetchers name downloads/ themselves.
DOWNLOAD_DIR := downloads
ifneq ($(origin DOWNLOAD_DIR),file)
$(error DOWNLOAD_DIR is fixed to downloads/ (the Dockerfiles copy from there); link that folder elsewhere instead)
endif

# OpenSSL for the Qt 5 and Qt 6 targets and qt4-win-amd64 (the other Qt 4
# targets take 1.0.2u: QT4_OPENSSL in mk/qt4.mk).
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

# osxcross has no tags, so a verified commit; the build log records what the
# ref resolved to.
#   make qt5-macos-amd64 OSXCROSS_REF=master
# osxcross and the projects it builds come from the OpenKaryonLab copies
# (docs/sources.md): LAB_GIT/<project>.git.
LAB_GIT ?= https://github.com/OpenKaryonLab
OSXCROSS_REF ?= 27d21e4977c9751d01199c7a226a6faf494c3dd9

ifeq ($(NO_CACHE),1)
DOCKER_CACHE_FLAG := --no-cache
else
DOCKER_CACHE_FLAG :=
endif

# Extra Docker build options, for example --resource=memory=8g.
DOCKER_BUILD_FLAGS ?=

# Where the base images (pinned by digest) are pulled from: the OpenKaryonLab
# copy, or Docker Hub, which has the same digests:
#   make qt5-linux-amd64 BASE_REGISTRY=docker.io/library
BASE_REGISTRY ?= ghcr.io/openkaryonlab
# The release of source archives the builds take their inputs from, inside
# Docker too (CMake); another copy of it: LONGREACH_MIRROR=<url>.
LONGREACH_MIRROR ?= https://github.com/OpenKaryonLab/longreach-qt-sources/releases/download/sources/
export LONGREACH_MIRROR
# Debian 12 and Ubuntu 22.04 install their packages from the archive as it was
# at the date in scripts/build/apt-snapshot.sh; APT_SNAPSHOT=<YYYYMMDDTHHMMSSZ>
# takes another date, APT_SNAPSHOT=none the live archive.
APT_SNAPSHOT ?=
SOURCE_ARGS = --build-arg BASE_REGISTRY=$(BASE_REGISTRY) --build-arg LONGREACH_MIRROR=$(LONGREACH_MIRROR) \
              $(if $(APT_SNAPSHOT),--build-arg APT_SNAPSHOT=$(APT_SNAPSHOT))

# Recipes run under whatever SHELL is: sh in Git Bash (where OS is still
# Windows_NT), cmd.exe on some Windows installs.
ifeq ($(OS),Windows_NT)
ifeq ($(filter sh sh.exe bash bash.exe,$(notdir $(SHELL))),)
MKDIR_P = $(PYTHON) -c "import os, sys; os.makedirs(sys.argv[1], exist_ok=True)" "$(1)"
RM_RF   = if exist "$(subst /,\,$(1))" rmdir /s /q "$(subst /,\,$(1))"
else
MKDIR_P = $(PYTHON) -c "import os, sys; os.makedirs(sys.argv[1], exist_ok=True)" "$(1)"
RM_RF   = rm -rf "$(1)"
endif
else
MKDIR_P = $(PYTHON) -c "import os, sys; os.makedirs(sys.argv[1], exist_ok=True)" "$(1)"
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
# fingerprint label); <target>-examples (also build-<target>-examples) does
# that and then builds the test applications into artifacts/tests-<image>/.
# $(1) public name, $(2) SDK target, $(3) image variable, $(4) examples
# target, $(5) examples arguments, $(6) the targets of images it is built
# FROM (scripts/build/ensure-image.py --needs).
define simple-build-targets
BUILD_TARGETS += $(1)
.PHONY: build-$(1) build-$(1)-examples $(1)-examples
$(1)-examples: build-$(1)-examples
build-$(1):
	$(PYTHON) scripts/build/ensure-image.py --image "$($(3))" --target "$(2)" $(foreach n,$(6),--needs $(n)) --docker-build-flags="$(DOCKER_BUILD_FLAGS)" $(if $(filter 1,$(NO_CACHE) $(FORCE)),--force,)
build-$(1)-examples:
	$(PYTHON) scripts/build/ensure-image.py --image "$($(3))" --target "$(2)" $(foreach n,$(6),--needs $(n)) --docker-build-flags="$(DOCKER_BUILD_FLAGS)" --examples-target "$(4)" --examples-args "$(5)" $(if $(filter 1,$(NO_CACHE) $(FORCE)),--force,)
endef

# A bare `make` lists the targets.
.DEFAULT_GOAL := help

include $(PROJECT_DIR)mk/qt4.mk
include $(PROJECT_DIR)mk/qt5.mk
include $(PROJECT_DIR)mk/qt6.mk

.PHONY: help build-all build-all-examples download-openssl download-llvm-mingw verify-downloads check-coverage regen-db image-sizes clean prune-cache

# Every target in one run (hours to a day or more); asks before it starts,
# YES=1 does not. BUILD_ALL_JOBS targets build at once, each with
# PARALLEL_JOBS compiler jobs; BUILD_ALL_ARGS passes more options to
# scripts/build/build-all.py (--only, --skip, --retries, see its --help).
#   make build-all-examples BUILD_ALL_JOBS=2
BUILD_ALL_JOBS ?= 1
BUILD_ALL_ARGS ?=
BUILD_ALL_FLAGS = --jobs $(BUILD_ALL_JOBS) --make-jobs $(PARALLEL_JOBS) --license-profile $(LICENSE_PROFILE) $(if $(filter 1,$(YES)),--yes,) $(if $(filter 1,$(NO_CACHE)),--no-cache,$(if $(filter 1,$(FORCE)),--force,)) $(BUILD_ALL_ARGS)

build-all:
	$(PYTHON) scripts/build/build-all.py --sdk-only $(BUILD_ALL_FLAGS)

build-all-examples:
	$(PYTHON) scripts/build/build-all.py $(BUILD_ALL_FLAGS)

# Every target, each SDK next to its -examples form.
help:
	@$(PYTHON) scripts/build/make-help.py qt4=$(QT4_VERSION) qt5=$(QT5_VERSION) qt6=$(QT6_VERSION) $(BUILD_TARGETS)

# Re-check the pinned inputs already in downloads/, and the Sarge and Lucid
# packages against their locks; what is not downloaded yet is counted, not
# failed.
VERIFY_DOWNLOADS = QT4_ARCHIVE QT5_ARCHIVE QT6_ARCHIVE OPENSSL QT4_OPENSSL GCC55 LLVM_MINGW QT6_WIN7_LLVM_MINGW \
                   QT5_LLVM_SRC QT6_NINJA QT6_XCB_CURSOR QT6_OS_VERSION_CHECK \
                   TIGER_SDK JAGUAR_SDK QT5_MACOS_I386_LINK_SDK QT6_MACOS_SDK QT6_MACOS_ARM64_SDK
VERIFY_PINS = $(sort $(foreach f,$(VERIFY_DOWNLOADS),$(if $($(f)_SHA256),$($(f)_PATH)=$($(f)_SHA256))))
VERIFY_PRESENT = $(foreach p,$(VERIFY_PINS),$(if $(wildcard $(firstword $(subst =, ,$(p)))),$(p)))
verify-downloads:
	$(foreach p,$(VERIFY_PRESENT),$(PYTHON) scripts/fetch/fetch.py --check $(subst =, ,$(p)) &&) echo "verify-downloads: $(words $(VERIFY_PRESENT)) of $(words $(VERIFY_PINS)) pinned files verified, the rest not downloaded"
	$(PYTHON) scripts/fetch/qt4-sarge-fetch.py --verify-only
	$(PYTHON) scripts/fetch/qt5-lucid-fetch.py --verify-only

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
