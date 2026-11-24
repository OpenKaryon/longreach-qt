// SPDX-License-Identifier: GPL-3.0-or-later
// Shared ABI for two independent consumer DSOs and their executable.
#ifndef LONGREACH_ANDROID_ATOMIC_PROBE_H
#define LONGREACH_ANDROID_ATOMIC_PROBE_H
#include <atomic>
#include <cstddef>
#include <cstdint>

struct alignas(8) AtomicValue {
    std::uint64_t sequence;
    std::uint64_t mirror;
    std::uint64_t checksum;
};
static_assert(sizeof(AtomicValue) == 24 && offsetof(AtomicValue, mirror) == 8
              && offsetof(AtomicValue, checksum) == 16, "Payload must have no padding");
inline AtomicValue atomicValue(std::uint64_t sequence)
{
    return {sequence, sequence, sequence ^ UINT64_C(0x5a61746f6d696373)};
}
inline bool validAtomicValue(const AtomicValue &value)
{
    return value.sequence == value.mirror
            && value.checksum == (value.sequence ^ UINT64_C(0x5a61746f6d696373));
}

using AtomicEntry = void (*)();
constexpr unsigned atomicEntryCount = 5;
// LLVM 21.1.8 generic ABI aliases, used only to compare imported addresses.
// The alias names avoid redeclaring Clang's reserved builtin identifiers.
extern "C" {
void longreach_atomic_load_entry(int, void *, void *, int) __asm__("__atomic_load") __attribute__((visibility("default")));
void longreach_atomic_store_entry(int, void *, void *, int) __asm__("__atomic_store") __attribute__((visibility("default")));
void longreach_atomic_exchange_entry(int, void *, void *, void *, int) __asm__("__atomic_exchange") __attribute__((visibility("default")));
int longreach_atomic_compare_entry(int, void *, void *, void *, int, int) __asm__("__atomic_compare_exchange") __attribute__((visibility("default")));
bool longreach_atomic_lock_free_entry(std::size_t, void *) __asm__("__atomic_is_lock_free") __attribute__((visibility("default")));
}
static inline void atomicProviderEntries(AtomicEntry *entries)
{
    entries[0] = reinterpret_cast<AtomicEntry>(&longreach_atomic_load_entry);
    entries[1] = reinterpret_cast<AtomicEntry>(&longreach_atomic_store_entry);
    entries[2] = reinterpret_cast<AtomicEntry>(&longreach_atomic_exchange_entry);
    entries[3] = reinterpret_cast<AtomicEntry>(&longreach_atomic_compare_entry);
    entries[4] = reinterpret_cast<AtomicEntry>(&longreach_atomic_lock_free_entry);
}

using AtomicCounter = std::atomic<AtomicValue>;
extern "C" {
__attribute__((visibility("default"))) int longreach_atomic_worker_a(AtomicCounter *, std::atomic<unsigned> *, std::atomic<bool> *, unsigned);
__attribute__((visibility("default"))) int longreach_atomic_worker_b(AtomicCounter *, std::atomic<unsigned> *, std::atomic<bool> *, unsigned);
__attribute__((visibility("default"))) void longreach_atomic_provider_a(AtomicEntry *);
__attribute__((visibility("default"))) void longreach_atomic_provider_b(AtomicEntry *);
}
#endif
