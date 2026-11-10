// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
#define SMOKE_REQUIRE_CXX23 1
#include "../../../tests/common/moderncpp_checks.h"

#if !defined(_LIBCPP_VERSION) || _LIBCPP_VERSION < 210000 || _LIBCPP_VERSION >= 220000
#error This probe requires upstream libc++ 21.
#endif

int main()
{
    SmokeModernCpp::printConfiguration();
    int passed = 0;
    int failed = 0;
    SmokeModernCpp::run([&](const char *name, auto function) {
        std::printf("RUN: %s\n", name);
        std::fflush(stdout);
        const SmokeModernCpp::Result result = SmokeModernCpp::evaluate(function);
        const bool success = result.status == SmokeModernCpp::Result::Passed;
        if (!success && !result.detail.empty())
            std::printf("DETAIL: %s: %s\n", name, result.detail.c_str());
        std::printf("%s: %s\n", success ? "PASS" : "FAIL", name);
        std::fflush(stdout);
        success ? ++passed : ++failed;
    });
    std::printf("SUMMARY: %d passed, %d failed, 0 skipped\n", passed, failed);
    return failed ? 1 : 0;
}
