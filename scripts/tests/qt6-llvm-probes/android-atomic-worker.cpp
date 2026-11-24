// SPDX-License-Identifier: GPL-3.0-or-later
// Compile this source separately into two DSOs; do not embed atomic.c in either.
#include "android-atomic.h"
#include <thread>
#ifndef LONGREACH_ATOMIC_WORKER
#error LONGREACH_ATOMIC_WORKER must name this DSO's worker export
#endif
#ifndef LONGREACH_ATOMIC_PROVIDER
#error LONGREACH_ATOMIC_PROVIDER must name this DSO's provider export
#endif

extern "C" __attribute__((visibility("default")))
void LONGREACH_ATOMIC_PROVIDER(AtomicEntry *entries)
{
    atomicProviderEntries(entries);
}

extern "C" __attribute__((visibility("default")))
int LONGREACH_ATOMIC_WORKER(AtomicCounter *value, std::atomic<unsigned> *arrived,
                          std::atomic<bool> *go, unsigned iterations)
{
    arrived->fetch_add(1, std::memory_order_release);
    while (!go->load(std::memory_order_acquire))
        std::this_thread::yield();
    for (unsigned i = 0; i < iterations; ++i) {
        if ((i & 31) == 0)
            std::this_thread::yield();
        AtomicValue before = value->load();
        for (;;) {
            if (!validAtomicValue(before))
                return 1;
            const AtomicValue after = atomicValue(before.sequence + 1);
            if (value->compare_exchange_weak(before, after))
                break;
        }
    }
    return 0;
}
