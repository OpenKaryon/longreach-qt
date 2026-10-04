// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

#include <cstdio>
#include <stdexcept>
#include <string>
#include <vector>
struct Global { Global() { std::printf("static init ok\n"); } ~Global() { std::printf("static fini ok\n"); } };
static Global g;
static int thrower(int v) { if (v > 1) throw std::runtime_error("expected"); return v; }
int main() {
    std::vector<std::string> v; v.push_back("jaguar");
    try { thrower(2); } catch (const std::exception &e) { std::printf("caught %s for %s\n", e.what(), v[0].c_str()); }
    std::printf("cxx-probe ok\n");
    return 0;
}
