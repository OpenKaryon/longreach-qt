// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
// Exercise one generic provider through two independent shared-library clients.
#include "android-atomic.h"
#include <chrono>
#include <cstdio>
#include <cstring>
#include <dlfcn.h>
#include <thread>

static bool imageFor(AtomicEntry entry, const char *name, void **base)
{
    Dl_info info = {};
    if (!dladdr(reinterpret_cast<void *>(entry), &info) || !info.dli_fname || !info.dli_fbase)
        return false;
    const char *slash = std::strrchr(info.dli_fname, '/');
    if (std::strcmp(slash ? slash + 1 : info.dli_fname, name) != 0)
        return false;
    *base = info.dli_fbase;
    return true;
}

int main()
{
    AtomicEntry local[atomicEntryCount], firstProvider[atomicEntryCount], secondProvider[atomicEntryCount];
    atomicProviderEntries(local);
    longreach_atomic_provider_a(firstProvider);
    longreach_atomic_provider_b(secondProvider);
    void *runtimeBase = nullptr;
    for (unsigned i = 0; i < atomicEntryCount; ++i) {
        void *base = nullptr;
        if (local[i] != firstProvider[i] || local[i] != secondProvider[i]
                || !imageFor(local[i], "libc++_shared.so", &base)
                || (runtimeBase && runtimeBase != base)) {
            std::puts("FAIL: generic atomic provider differs between consumers");
            return 1;
        }
        runtimeBase = base;
    }
    void *workerA = nullptr, *workerB = nullptr;
    if (!imageFor(reinterpret_cast<AtomicEntry>(&longreach_atomic_worker_a), "liblongreach-atomic-a.so", &workerA)
            || !imageFor(reinterpret_cast<AtomicEntry>(&longreach_atomic_worker_b), "liblongreach-atomic-b.so", &workerB)
            || workerA == workerB || workerA == runtimeBase || workerB == runtimeBase) {
        std::puts("FAIL: atomic workers are not separate shared-library clients");
        return 1;
    }
    AtomicCounter value(atomicValue(0));
    if (value.is_lock_free()) {
        std::puts("FAIL: expected generic non-lock-free 24-byte atomics");
        return 1;
    }
    value.store(atomicValue(7));
    const AtomicValue loaded = value.load();
    const AtomicValue exchanged = value.exchange(atomicValue(0));
    if (!validAtomicValue(loaded) || !validAtomicValue(exchanged)
            || loaded.sequence != 7 || exchanged.sequence != 7) {
        std::puts("FAIL: generic atomic store/load/exchange");
        return 1;
    }
    std::atomic<unsigned> arrived(0);
    std::atomic<bool> go(false);
    int firstResult = 1, secondResult = 1;
    constexpr unsigned iterations = 2000;
    std::thread first, second;
    try {
        first = std::thread([&] { firstResult = longreach_atomic_worker_a(&value, &arrived, &go, iterations); });
        second = std::thread([&] { secondResult = longreach_atomic_worker_b(&value, &arrived, &go, iterations); });
    } catch (...) {
        go.store(true, std::memory_order_release);
        if (first.joinable()) first.join();
        if (second.joinable()) second.join();
        std::puts("FAIL: cannot start both atomic worker threads");
        return 1;
    }
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
    while (arrived.load(std::memory_order_acquire) != 2 && std::chrono::steady_clock::now() < deadline)
        std::this_thread::yield();
    const bool bothReady = arrived.load(std::memory_order_acquire) == 2;
    go.store(true, std::memory_order_release);
    first.join();
    second.join();
    const AtomicValue result = value.load();
    if (!bothReady || firstResult || secondResult || !validAtomicValue(result) || result.sequence != 2 * iterations) {
        std::puts("FAIL: cross-DSO generic atomic compare/exchange handoff");
        return 1;
    }
    std::puts("ATOMIC_PROVIDER: libc++_shared.so");
    std::puts("ATOMIC_WORKERS: 2");
    std::puts("PASS: generic 24-byte cross-DSO atomic store/load/exchange/CAS/thread handoff");
    return 0;
}
