// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
#ifndef LONGREACH_API4_ARMV5_ATOMIC_H
#define LONGREACH_API4_ARMV5_ATOMIC_H

#if !defined(__arm__) || __ARM_ARCH != 5 || __ANDROID_API__ != 4
#error This probe requires the API4 ARMv5 target
#endif
#if __BYTE_ORDER__ != __ORDER_LITTLE_ENDIAN__
#error This probe covers the configured little-endian armeabi profile
#endif
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>

namespace LongreachArmv5Atomic {
// Distinct C++ identifiers force calls to the actual compatibility symbols,
// rather than allowing Clang to replace a builtin spelling with instructions.
extern "C" {
void barrier() __asm__("__sync_synchronize");
uint32_t cas32(volatile uint32_t *, uint32_t, uint32_t) __asm__("__sync_val_compare_and_swap_4");
uint32_t add32(volatile uint32_t *, uint32_t) __asm__("__sync_fetch_and_add_4");
uint32_t sub32(volatile uint32_t *, uint32_t) __asm__("__sync_fetch_and_sub_4");
uint32_t and32(volatile uint32_t *, uint32_t) __asm__("__sync_fetch_and_and_4");
uint32_t exchange32(volatile uint32_t *, uint32_t) __asm__("__sync_lock_test_and_set_4");
uint8_t cas8(volatile uint8_t *, uint8_t, uint8_t) __asm__("__sync_val_compare_and_swap_1");
uint8_t exchange8(volatile uint8_t *, uint8_t) __asm__("__sync_lock_test_and_set_1");
}
inline uint32_t read(volatile uint32_t *word) { return cas32(word, 0, 0); }
inline bool record(const char *name, bool passed)
{
    printf("ARMV5_ATOMIC: %s=%s\n", name, passed ? "PASS" : "FAIL");
    fflush(stdout);
    return passed;
}
constexpr int Workers = 4;
constexpr int Iterations = 1024;
struct Work { volatile uint32_t *word; int lane; };
inline void *increment(void *opaque)
{
    Work *work = static_cast<Work *>(opaque);
    for (int i = 0; i < Iterations; ++i) add32(work->word, 1);
    return nullptr;
}
inline void *exchangeLane(void *opaque)
{
    Work *work = static_cast<Work *>(opaque);
    volatile uint8_t *byte = reinterpret_cast<volatile uint8_t *>(work->word) + work->lane;
    for (int i = 0; i < Iterations; ++i) exchange8(byte, static_cast<uint8_t>(i));
    exchange8(byte, static_cast<uint8_t>(0xa0 + work->lane));
    return nullptr;
}
inline bool threads(volatile uint32_t *word, void *(*function)(void *))
{
    pthread_attr_t attributes;
    if (pthread_attr_init(&attributes)) return false;
    if (pthread_attr_setstacksize(&attributes, 128 * 1024)) {
        pthread_attr_destroy(&attributes);
        return false;
    }
    pthread_t workers[Workers];
    Work work[Workers];
    int created = 0;
    for (int i = 0; i < Workers; ++i) {
        work[i] = {word, i};
        if (pthread_create(&workers[i], &attributes, function, &work[i])) break;
        ++created;
    }
    const bool attributesClosed = pthread_attr_destroy(&attributes) == 0;
    for (int i = 0; i < created; ++i) {
        if (pthread_join(workers[i], nullptr)) {
            // Never return with a worker still holding this invocation's data.
            printf("ARMV5_ATOMIC: pthread_join=FAIL\n");
            fflush(stdout);
            abort();
        }
    }
    return created == Workers && attributesClosed;
}
inline bool run()
{
    const uint32_t version = *reinterpret_cast<const volatile uint32_t *>(uintptr_t(0xffff0ffc));
    printf("ARMV5_ATOMIC: helper_version=%u\n", unsigned(version));
    fflush(stdout);
    if (version < 3) return false;
    barrier();
    if (!record("barrier-call", true)) return false;
    alignas(4) volatile uint32_t word = 0x10203040;
    bool ok = cas32(&word, 0x10203040, 0xaabbccdd) == 0x10203040 && read(&word) == 0xaabbccdd;
    ok = ok && cas32(&word, 1, 2) == 0xaabbccdd && read(&word) == 0xaabbccdd;
    if (!record("word-cas", ok)) return false;
    word = 0xffffffffu;
    if (!record("word-fetch-add", add32(&word, 2) == 0xffffffffu && read(&word) == 1)) return false;
    word = 0;
    if (!record("word-fetch-sub", sub32(&word, 1) == 0 && read(&word) == 0xffffffffu)) return false;
    word = 0xa5a5ff00u;
    if (!record("word-fetch-and", and32(&word, 0x0ff00ff0u) == 0xa5a5ff00u && read(&word) == (0xa5a5ff00u & 0x0ff00ff0u))) return false;
    word = 0x01020304;
    if (!record("word-exchange", exchange32(&word, 0x55667788) == 0x01020304 && read(&word) == 0x55667788)) return false;
    word = 0x44332211;
    ok = true;
    for (unsigned lane = 0; lane < 4; ++lane) {
        volatile uint8_t *byte = reinterpret_cast<volatile uint8_t *>(&word) + lane;
        const uint32_t before = read(&word);
        const uint8_t original = static_cast<uint8_t>(before >> (lane * 8));
        const uint8_t desired = static_cast<uint8_t>(0x80 + lane);
        const uint32_t expected = (before & ~(0xffu << (lane * 8))) | (uint32_t(desired) << (lane * 8));
        ok = ok && cas8(byte, original, desired) == original && read(&word) == expected;
        ok = ok && cas8(byte, static_cast<uint8_t>(desired + 1), 0) == desired && read(&word) == expected;
    }
    if (!record("byte-cas-lanes", ok)) return false;
    word = 0x44332211;
    ok = true;
    for (unsigned lane = 0; lane < 4; ++lane) {
        volatile uint8_t *byte = reinterpret_cast<volatile uint8_t *>(&word) + lane;
        const uint32_t before = read(&word);
        const uint8_t original = static_cast<uint8_t>(before >> (lane * 8));
        const uint8_t desired = static_cast<uint8_t>(0xd0 + lane);
        const uint32_t expected = (before & ~(0xffu << (lane * 8))) | (uint32_t(desired) << (lane * 8));
        ok = ok && exchange8(byte, desired) == original && read(&word) == expected;
    }
    if (!record("byte-exchange-lanes", ok)) return false;
    word = 0;
    if (!threads(&word, increment)) return record("word-contention", false);
    const uint32_t count = read(&word);
    printf("ARMV5_ATOMIC: word-contention=%s workers=4 iterations=1024 final=%u\n",
           count == Workers * Iterations ? "PASS" : "FAIL", unsigned(count));
    fflush(stdout);
    if (count != Workers * Iterations) return false;
    word = 0;
    if (!threads(&word, exchangeLane)) return record("byte-contention", false);
    const uint32_t lanes = read(&word);
    printf("ARMV5_ATOMIC: byte-contention=%s workers=4 iterations=1024 final=%08x\n",
           lanes == 0xa3a2a1a0u ? "PASS" : "FAIL", unsigned(lanes));
    fflush(stdout);
    return lanes == 0xa3a2a1a0u;
}
} // namespace LongreachArmv5Atomic
#endif
