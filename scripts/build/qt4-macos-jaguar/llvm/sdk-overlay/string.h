// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

#ifndef JAGUAR_COMPAT_STRING_H
#define JAGUAR_COMPAT_STRING_H
#include_next <string.h>
#include <errno.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif
extern const char *const sys_errlist[];
extern const int sys_nerr;
#ifdef __cplusplus
}
#endif

static __inline__ int strerror_r(int code, char *buffer, size_t size) {
    if (code < 0 || code >= sys_nerr)
        return EINVAL;
    const char *message = sys_errlist[code];
    size_t length = strlen(message);
    if (length >= size) {
        if (size) {
            memcpy(buffer, message, size - 1);
            buffer[size - 1] = 0;
        }
        return ERANGE;
    }
    memcpy(buffer, message, length + 1);
    return 0;
}
#endif
