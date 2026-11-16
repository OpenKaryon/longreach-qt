// SPDX-License-Identifier: LGPL-2.1-only OR GPL-3.0-only
// Copyright (C) 2026 OpenKaryon

#include <stdint.h>
#include <stdlib.h>

typedef int (*KernelCompareExchange)(uint32_t, uint32_t, volatile uint32_t *);
typedef void (*KernelBarrier)(void);

static void barrier(void)
{
    ((KernelBarrier)0xffff0fa0u)();
}

static int replace32(volatile uint32_t *word, uint32_t original, uint32_t desired)
{
    return ((KernelCompareExchange)0xffff0fc0u)(original, desired, word) == 0;
}

__attribute__((constructor(101))) static void check_kernel_helpers(void)
{
    if (*(const volatile uint32_t *)0xffff0ffcu < 3)
        abort();
}

void donut_sync_barrier(void) __asm__("__sync_synchronize");
void donut_sync_barrier(void) { barrier(); }

uint32_t donut_cas4(volatile uint32_t *word, uint32_t expected, uint32_t desired)
    __asm__("__sync_val_compare_and_swap_4");
uint32_t donut_cas4(volatile uint32_t *word, uint32_t expected, uint32_t desired)
{
    barrier();
    for (;;) {
        uint32_t original = *word;
        if (original != expected || replace32(word, original, desired)) {
            barrier();
            return original;
        }
    }
}

#define DONUT_FETCH4(name, expression) \
    uint32_t donut_##name(volatile uint32_t *word, uint32_t value) __asm__("__sync_" #name "_4"); \
    uint32_t donut_##name(volatile uint32_t *word, uint32_t value) \
    { \
        barrier(); \
        uint32_t original; \
        do { original = *word; } while (!replace32(word, original, expression)); \
        return original; \
    }

DONUT_FETCH4(fetch_and_add, original + value)
DONUT_FETCH4(fetch_and_sub, original - value)
DONUT_FETCH4(fetch_and_and, original & value)
DONUT_FETCH4(lock_test_and_set, value)

static uint8_t exchange_byte(volatile uint8_t *byte, uint8_t expected, uint8_t value, int compare)
{
    uintptr_t address = (uintptr_t)byte;
    volatile uint32_t *word = (volatile uint32_t *)(address & ~(uintptr_t)3);
    unsigned shift = (address & 3u) * 8u;
    uint32_t mask = 0xffu << shift;
    barrier();
    for (;;) {
        uint32_t original = *word;
        uint8_t present = (uint8_t)(original >> shift);
        if (compare && present != expected) {
            barrier();
            return present;
        }
        uint32_t desired = (original & ~mask) | ((uint32_t)value << shift);
        if (replace32(word, original, desired))
            return present;
    }
}

uint8_t donut_cas1(volatile uint8_t *byte, uint8_t expected, uint8_t desired)
    __asm__("__sync_val_compare_and_swap_1");
uint8_t donut_cas1(volatile uint8_t *byte, uint8_t expected, uint8_t desired)
{ return exchange_byte(byte, expected, desired, 1); }

uint8_t donut_exchange1(volatile uint8_t *byte, uint8_t value) __asm__("__sync_lock_test_and_set_1");
uint8_t donut_exchange1(volatile uint8_t *byte, uint8_t value)
{ return exchange_byte(byte, 0, value, 0); }
