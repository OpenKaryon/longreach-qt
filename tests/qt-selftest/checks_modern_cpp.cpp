// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
#include "../common/smokecheck.h"
#include "../common/moderncpp_checks.h"
#include "checks.h"

void checkModernCpp(SmokeReporter &reporter)
{
    SmokeModernCpp::printConfiguration();
    SmokeModernCpp::run([&](const char *name, auto function) {
        reporter.check(QString::fromLatin1(name), [&](QString &detail) {
            const SmokeModernCpp::Result result = SmokeModernCpp::evaluate(function);
            detail = QString::fromUtf8(result.detail.c_str());
            if (result.status == SmokeModernCpp::Result::Unavailable) {
#ifndef SMOKE_REQUIRE_CXX23
                reporter.skip(detail, detail);
#endif
                return false;
            }
            return result.status == SmokeModernCpp::Result::Passed;
        });
    });
}
