// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

#include <cstdio>
#include <functional>
#include <memory>
#include <stdexcept>
#include <vector>
int main() {
    auto value = std::make_unique<int>(42);
    std::function<int()> read = [&]{ return *value; };
    std::vector<int> values{read(), 7};
    try { throw std::runtime_error("Tiger PPC C++14"); }
    catch (const std::exception &error) {
        std::printf("%s: %d\n", error.what(), values.front());
        return values.front() == 42 ? 0 : 1;
    }
    return 2;
}
