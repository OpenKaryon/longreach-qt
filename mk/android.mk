# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
# One registry owns public names, image tags and output locations.
# Enumerating names is read-only and needs neither PowerShell nor Android SDK.
ANDROID_TARGETS := $(shell $(PYTHON) scripts/build/android.py --targets)
BUILD_TARGETS += $(ANDROID_TARGETS)

# Refuse unsupported profiles before any SDK prerequisite can start.
ifneq ($(LICENSE_PROFILE),gpl-enabled)
ANDROID_GOALS := $(foreach t,$(ANDROID_TARGETS),$(t) $(t)-examples) qt4-android-arm-legacy
ifneq ($(filter $(ANDROID_GOALS),$(MAKECMDGOALS)),)
$(error Android recipes currently support LICENSE_PROFILE=gpl-enabled only)
endif
endif

POWERSHELL ?= pwsh
ANDROID_SDK ?= $(ANDROID_HOME)
ANDROID_OUTPUT ?=
ANDROID_SDK_IMAGE ?=
ANDROID_HOST_IMAGE ?=
ANDROID_INPUT ?=
# Existing Android containers have two CPUs and 3 GiB, independently of desktops.
ANDROID_PARALLEL_JOBS ?= 2

ANDROID_OPTIONS = --powershell "$(POWERSHELL)" --license-profile "$(LICENSE_PROFILE)" \
 --android-sdk "$(ANDROID_SDK)" --output-directory "$(ANDROID_OUTPUT)" \
 --sdk-image "$(ANDROID_SDK_IMAGE)" \
 --input-directory "$(ANDROID_INPUT)" --parallel-jobs "$(ANDROID_PARALLEL_JOBS)"
ANDROID_SDK_OPTIONS = --host-image "$(ANDROID_HOST_IMAGE)" $(if $(filter 1,$(NO_CACHE)),--no-cache,) --docker-build-flags="$(DOCKER_BUILD_FLAGS)"

# Direct -examples consumes a ready SDK, then packages the applications as APKs.
# Only explicit SDK mode builds Qt; build-all schedules SDK then examples.
define android-target
.PHONY: $(1) $(1)-examples
$(1):
	$$(PYTHON) scripts/build/android.py --target "$(1)" --mode sdk --qt-version "$$(QT$(2)_VERSION)" $$(ANDROID_OPTIONS) $$(ANDROID_SDK_OPTIONS)
$(1)-examples:
	$$(PYTHON) scripts/build/android.py --target "$(1)" --mode examples --qt-version "$$(QT$(2)_VERSION)" $$(ANDROID_OPTIONS)
endef
$(foreach t,$(ANDROID_TARGETS),$(eval $(call android-target,$(t),$(patsubst qt%,%,$(firstword $(subst -, ,$(t)))))))

# Prepare Qt6's native Linux host SDK through the existing incremental route.
# A caller selecting a custom ready host image takes responsibility for it.
# This dependency belongs to SDK mode only, never to -examples.
ifeq ($(OS),Windows_NT)
ifeq ($(strip $(ANDROID_HOST_IMAGE)),)
$(filter qt6-%,$(ANDROID_TARGETS)): build-qt6-linux-amd64
endif
endif

# Preserve the original combined API4 recipe separately from its installed
# SDK target. The legacy recipe stays outside the SDK-only build-all matrix.
.PHONY: qt4-android-arm-legacy
qt4-android-arm-legacy:
	$(PYTHON) scripts/build/android.py --target "$@" --mode legacy --qt-version "$(QT4_VERSION)" $(ANDROID_OPTIONS) $(ANDROID_SDK_OPTIONS)
