// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Toolchain probe for the Ubuntu 10.04 Lucid amd64 target: C++14 threads,
// thread_local, exceptions, regex and iostreams through the static
// libstdc++ rebuilt against Lucid's glibc 2.11. Must run on stock Lucid.
#include <chrono>
#include <condition_variable>
#include <iostream>
#include <mutex>
#include <regex>
#include <stdexcept>
#include <string>
#include <thread>

thread_local int perThread = 7;

int main()
{
    std::mutex mutex;
    std::condition_variable ready;
    int value = 0;
    std::thread worker([&] {
        perThread = 1;
        std::lock_guard<std::mutex> lock(mutex);
        value = 42;
        ready.notify_one();
    });
    {
        std::unique_lock<std::mutex> lock(mutex);
        ready.wait_for(lock, std::chrono::seconds(5), [&] { return value == 42; });
    }
    worker.join();
    bool caught = false;
    try { throw std::runtime_error("lucid"); } catch (const std::exception &e) { caught = std::string(e.what()) == "lucid"; }
    const bool match = std::regex_match("lucid2010", std::regex("lucid[0-9]+"));
    std::cout << "Lucid C++14 probe value=" << value << " thread_local=" << perThread
              << " exception=" << caught << " regex=" << match << std::endl;
    return value == 42 && perThread == 7 && caught && match ? 0 : 1;
}
