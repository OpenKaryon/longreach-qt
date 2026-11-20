// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
// Generic compiler-rt atomics must share their lock table through the runtime.
#include <atomic>
#include <cstdint>
#include <cstdio>
#include <thread>

struct alignas(16) Value {
    std::uint64_t sequence;
    std::uint64_t mirror;
};

int main()
{
    std::atomic<Value> value(Value{0, 0});
    if (sizeof(void *) != 4 || value.is_lock_free()) {
        std::puts("FAIL: expected 32-bit generic non-lock-free atomics");
        return 1;
    }
    value.store(Value{7, 7});
    const Value loaded = value.load();
    const Value exchanged = value.exchange(Value{0, 0});
    if (loaded.sequence != 7 || loaded.mirror != 7
            || exchanged.sequence != 7 || exchanged.mirror != 7) {
        std::puts("FAIL: generic atomic store/load/exchange");
        return 1;
    }
    std::atomic<bool> failed(false);
    const auto increment = [&] {
        for (int i = 0; i < 200; ++i) {
            Value before = value.load();
            for (;;) {
                if (before.sequence != before.mirror)
                    failed.store(true);
                const Value after{before.sequence + 1, before.mirror + 1};
                if (value.compare_exchange_weak(before, after))
                    break;
            }
        }
    };
    std::thread first(increment), second(increment);
    first.join();
    second.join();
    const Value result = value.load();
    if (failed.load() || result.sequence != 400 || result.mirror != 400) {
        std::puts("FAIL: generic atomic compare/exchange thread handoff");
        return 1;
    }
    std::puts("PASS: generic 16-byte atomic store/load/exchange/CAS/thread handoff");
    return 0;
}
