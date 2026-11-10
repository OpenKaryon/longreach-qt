// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
#include "smokecheck.h"

void checkModernCpp(SmokeReporter &reporter);

int main()
{
    SmokeReporter reporter("modern-cpp");
    checkModernCpp(reporter);
    return reporter.summary();
}
