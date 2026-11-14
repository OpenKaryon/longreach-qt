// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

#ifndef JAGUAR_COMPAT_STDLIB_H
#define JAGUAR_COMPAT_STDLIB_H
#ifdef __cplusplus
#define _BSD_WCHAR_T_DEFINED_
#endif
#include_next <stdlib.h>

#ifdef __cplusplus
extern "C" {
#endif
long long strtoll(const char *, char **, int);
unsigned long long strtoull(const char *, char **, int);
float strtof(const char *, char **);
long double strtold(const char *, char **);
#ifdef __cplusplus
}
#endif

typedef struct {
    long long quot;
    long long rem;
} lldiv_t;

static __inline__ lldiv_t lldiv(long long numerator, long long denominator) {
    lldiv_t result;
    result.quot = numerator / denominator;
    result.rem = numerator % denominator;
    return result;
}
#endif
