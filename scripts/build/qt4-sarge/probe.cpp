// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

#include <iostream>
#include <locale>
#include <thread>
#include <mutex>
#include <regex>

int main()
{
    std::mutex mutex;
    int value = 0;
    std::thread worker([&] {
        std::lock_guard<std::mutex> lock(mutex);
        value = 42;
    });
    worker.join();
    const bool match = std::regex_match("sarge2005", std::regex("sarge[0-9]+"));
    std::cout << "Sarge C++14 probe " << value << " regex=" << match << std::endl;
    return value == 42 && match ? 0 : 1;
}
