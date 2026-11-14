// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

#include <stdio.h>
#include <stdlib.h>
#include <limits.h>
#include <errno.h>

typedef __WINT_TYPE__ wint_t;
#define WEOF ((wint_t)-1)

/* These entry points serve libc++'s wide standard streams on Jaguar. */
wint_t fputwc(wchar_t c, FILE *stream) {
    char bytes[MB_LEN_MAX];
    int count = wctomb(bytes, c);
    if (count < 0)
        return WEOF;
    return fwrite(bytes, 1, count, stream) == (size_t)count ? (wint_t)c : WEOF;
}

wint_t getwc(FILE *stream) {
    char bytes[MB_LEN_MAX];
    wchar_t value;
    for (size_t count = 0; count < sizeof(bytes);) {
        int byte = getc(stream);
        if (byte == EOF)
            return WEOF;
        bytes[count++] = (char)byte;
        if (mbtowc(&value, bytes, count) >= 0)
            return (wint_t)value;
        if (count >= MB_CUR_MAX)
            return WEOF;
    }
    return WEOF;
}

wint_t ungetwc(wint_t c, FILE *stream) {
    char bytes[MB_LEN_MAX];
    if (c == WEOF)
        return WEOF;
    int count = wctomb(bytes, (wchar_t)c);
    if (count < 0)
        return WEOF;
    while (count)
        if (ungetc((unsigned char)bytes[--count], stream) == EOF)
            return WEOF;
    return c;
}

extern double pow(double, double);
double exp2(double exponent) { return pow(2.0, exponent); }
extern double acos(double);
extern double tan(double);
float acosf(float value) { return (float)acos(value); }
float tanf(float value) { return (float)tan(value); }

extern double sqrt(double);
float sqrtf(float value) { return (float)sqrt(value); }
