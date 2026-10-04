// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

#import <Foundation/Foundation.h>
#include <cstdio>
#include <stdexcept>
#include <vector>
int main() {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    std::vector<int> values{42};
    int checks = 0;
    try { throw std::runtime_error("C++ exception"); }
    catch (const std::exception &error) { std::puts(error.what()); ++checks; }
    @try { [[NSArray array] objectAtIndex:1]; }
    @catch (NSException *error) { std::puts([[error name] UTF8String]); ++checks; }
    [pool release];
    return checks == 2 && values.front() == 42 ? 0 : 1;
}
