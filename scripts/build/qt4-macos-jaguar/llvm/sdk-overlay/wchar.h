// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

#ifndef JAGUAR_COMPAT_WCHAR_H
#define JAGUAR_COMPAT_WCHAR_H
#include <stddef.h>
#include <stdio.h>
#include <time.h>
#include <sys/_types/_mbstate_t.h>

typedef __WINT_TYPE__ wint_t;
#define WEOF ((wint_t)-1)

#ifdef __cplusplus
extern "C" {
#endif
long wcstol(const wchar_t *, wchar_t **, int);
unsigned long wcstoul(const wchar_t *, wchar_t **, int);
long long wcstoll(const wchar_t *, wchar_t **, int);
unsigned long long wcstoull(const wchar_t *, wchar_t **, int);
float wcstof(const wchar_t *, wchar_t **);
double wcstod(const wchar_t *, wchar_t **);
long double wcstold(const wchar_t *, wchar_t **);
wint_t getwc(FILE *);
wint_t ungetwc(wint_t, FILE *);
wint_t fputwc(wchar_t, FILE *);
int swprintf(wchar_t *, size_t, const wchar_t *, ...);

static __inline__ wchar_t *wcschr(const wchar_t *s, wchar_t c) {
    for (; *s != c; ++s)
        if (!*s)
            return 0;
    return (wchar_t *)s;
}

static __inline__ wchar_t *wcsrchr(const wchar_t *s, wchar_t c) {
    const wchar_t *last = 0;
    do {
        if (*s == c)
            last = s;
    } while (*s++);
    return (wchar_t *)last;
}

static __inline__ wchar_t *wcspbrk(const wchar_t *s, const wchar_t *accept) {
    for (; *s; ++s)
        if (wcschr(accept, *s))
            return (wchar_t *)s;
    return 0;
}

static __inline__ wchar_t *wcsstr(const wchar_t *s, const wchar_t *needle) {
    for (;;) {
        const wchar_t *candidate = s;
        const wchar_t *part = needle;
        while (*part && *candidate == *part) {
            ++candidate;
            ++part;
        }
        if (!*part)
            return (wchar_t *)s;
        if (!*s++)
            return 0;
    }
}

static __inline__ size_t wcslen(const wchar_t *s) {
    const wchar_t *end = s;
    while (*end)
        ++end;
    return (size_t)(end - s);
}

static __inline__ int wmemcmp(const wchar_t *lhs, const wchar_t *rhs, size_t count) {
    for (; count; --count, ++lhs, ++rhs)
        if (*lhs != *rhs)
            return *lhs < *rhs ? -1 : 1;
    return 0;
}

static __inline__ wchar_t *wmemcpy(wchar_t *dest, const wchar_t *src, size_t count) {
    return (wchar_t *)__builtin_memcpy(dest, src, count * sizeof(wchar_t));
}

static __inline__ wchar_t *wmemmove(wchar_t *dest, const wchar_t *src, size_t count) {
    return (wchar_t *)__builtin_memmove(dest, src, count * sizeof(wchar_t));
}

static __inline__ wchar_t *wmemset(wchar_t *dest, wchar_t value, size_t count) {
    for (size_t i = 0; i < count; ++i)
        dest[i] = value;
    return dest;
}

static __inline__ wchar_t *wmemchr(const wchar_t *s, wchar_t c, size_t n) {
    for (; n; --n, ++s)
        if (*s == c)
            return (wchar_t *)s;
    return 0;
}
#ifdef __cplusplus
}
#endif
#endif
