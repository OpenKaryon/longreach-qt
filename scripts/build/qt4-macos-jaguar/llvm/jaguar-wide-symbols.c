// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

#include <stddef.h>

size_t wcslen(const wchar_t *s) {
    const wchar_t *end = s;
    while (*end)
        ++end;
    return (size_t)(end - s);
}

int wmemcmp(const wchar_t *lhs, const wchar_t *rhs, size_t count) {
    for (; count; --count, ++lhs, ++rhs)
        if (*lhs != *rhs)
            return *lhs < *rhs ? -1 : 1;
    return 0;
}

wchar_t *wmemchr(const wchar_t *s, wchar_t c, size_t count) {
    for (; count; --count, ++s)
        if (*s == c)
            return (wchar_t *)s;
    return NULL;
}