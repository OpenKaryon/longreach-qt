// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

#include <ctype.h>
#include <errno.h>
#ifndef EILSEQ
#define EILSEQ 92
#endif
#include <locale.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <xlocale.h>

struct jaguar_locale {
    char *name[7];
    struct lconv formatting;
};
static pthread_mutex_t locale_mutex = PTHREAD_MUTEX_INITIALIZER;

static char *enter(locale_t locale, int category) {
    pthread_mutex_lock(&locale_mutex);
    if (!locale || !locale->name[category])
        return NULL;
    const char *old = setlocale(category, NULL);
    char *saved = old ? strdup(old) : NULL;
    if (saved)
        setlocale(category, locale->name[category]);
    return saved;
}

static void leave(int category, char *saved) {
    int error = errno;
    if (saved) {
        setlocale(category, saved);
        free(saved);
    }
    pthread_mutex_unlock(&locale_mutex);
    errno = error;
}

void freelocale(locale_t locale) {
    if (!locale)
        return;
    for (int category = LC_COLLATE; category <= LC_MESSAGES; ++category)
        free(locale->name[category]);
    free(locale->formatting.decimal_point);
    free(locale->formatting.thousands_sep);
    free(locale->formatting.grouping);
    free(locale->formatting.int_curr_symbol);
    free(locale->formatting.currency_symbol);
    free(locale->formatting.mon_decimal_point);
    free(locale->formatting.mon_thousands_sep);
    free(locale->formatting.mon_grouping);
    free(locale->formatting.positive_sign);
    free(locale->formatting.negative_sign);
    free(locale);
}

static int capture_formatting(locale_t locale) {
    char *numeric = strdup(setlocale(LC_NUMERIC, NULL));
    char *monetary = strdup(setlocale(LC_MONETARY, NULL));
    if (!numeric || !monetary) {
        free(numeric);
        free(monetary);
        return ENOMEM;
    }
    setlocale(LC_NUMERIC, locale->name[LC_NUMERIC]);
    setlocale(LC_MONETARY, locale->name[LC_MONETARY]);
    const struct lconv *format = localeconv();
    locale->formatting = *format;
#define JAGUAR_COPY(field) locale->formatting.field = strdup(format->field)
    JAGUAR_COPY(decimal_point);
    JAGUAR_COPY(thousands_sep);
    JAGUAR_COPY(grouping);
    JAGUAR_COPY(int_curr_symbol);
    JAGUAR_COPY(currency_symbol);
    JAGUAR_COPY(mon_decimal_point);
    JAGUAR_COPY(mon_thousands_sep);
    JAGUAR_COPY(mon_grouping);
    JAGUAR_COPY(positive_sign);
    JAGUAR_COPY(negative_sign);
#undef JAGUAR_COPY
    setlocale(LC_NUMERIC, numeric);
    setlocale(LC_MONETARY, monetary);
    free(numeric);
    free(monetary);
    const struct lconv *f = &locale->formatting;
    return f->decimal_point && f->thousands_sep && f->grouping &&
           f->int_curr_symbol && f->currency_symbol && f->mon_decimal_point &&
           f->mon_thousands_sep && f->mon_grouping && f->positive_sign &&
           f->negative_sign ? 0 : ENOMEM;
}

struct lconv *localeconv_l(locale_t locale) {
    return locale ? &locale->formatting : localeconv();
}

locale_t newlocale(int mask, const char *name, locale_t base) {
    if (!name || (mask & ~LC_ALL_MASK)) {
        errno = EINVAL;
        return NULL;
    }

    locale_t locale = calloc(1, sizeof(*locale));
    if (!locale)
        return NULL;

    int error = 0;
    pthread_mutex_lock(&locale_mutex);
    for (int category = LC_COLLATE; category <= LC_MESSAGES; ++category) {
        const char *selected = "C";
        if (base && base->name[category])
            selected = base->name[category];
        if (mask & (1 << category)) {
            const char *old = setlocale(category, NULL);
            char *saved = old ? strdup(old) : NULL;
            if (!saved) {
                error = ENOMEM;
                break;
            }
            selected = setlocale(category, name);
            locale->name[category] = selected ? strdup(selected) : NULL;
            error = selected ? ENOMEM : ENOENT;
            setlocale(category, saved);
            free(saved);
        } else {
            locale->name[category] = strdup(selected);
            error = ENOMEM;
        }
        if (!locale->name[category])
            break;
        error = 0;
    }
    if (!error)
        error = capture_formatting(locale);
    pthread_mutex_unlock(&locale_mutex);
    if (error) {
        freelocale(locale);
        errno = error;
        return NULL;
    }
    freelocale(base);
    return locale;
}

long double strtold(const char *s, char **end) { return strtod(s, end); }

float strtof(const char *s, char **end) {
    double value = strtod(s, end);
    float narrowed = (float)value;
    if ((double)narrowed > __FLT_MAX__ || (double)narrowed < -__FLT_MAX__) {
        if (value <= __DBL_MAX__ && value >= -__DBL_MAX__)
            errno = ERANGE;
    } else if (value != 0 && narrowed == 0) {
        errno = ERANGE;
    }
    return narrowed;
}

#define JAGUAR_LOCALE_CALL(type, expression, category) \
    char *saved = enter(locale, category);             \
    type result = (expression);                        \
    leave(category, saved);                            \
    return result

float strtof_l(const char *s, char **end, locale_t locale) {
    JAGUAR_LOCALE_CALL(float, strtof(s, end), LC_NUMERIC);
}
double strtod_l(const char *s, char **end, locale_t locale) {
    JAGUAR_LOCALE_CALL(double, strtod(s, end), LC_NUMERIC);
}
long double strtold_l(const char *s, char **end, locale_t locale) {
    JAGUAR_LOCALE_CALL(long double, strtold(s, end), LC_NUMERIC);
}
long long strtoll_l(const char *s, char **end, int base, locale_t locale) {
    JAGUAR_LOCALE_CALL(long long, strtoll(s, end, base), LC_CTYPE);
}
unsigned long long strtoull_l(const char *s, char **end, int base, locale_t locale) {
    JAGUAR_LOCALE_CALL(unsigned long long, strtoull(s, end, base), LC_CTYPE);
}
int isdigit_l(int c, locale_t locale) {
    JAGUAR_LOCALE_CALL(int, isdigit(c), LC_CTYPE);
}
int isxdigit_l(int c, locale_t locale) {
    JAGUAR_LOCALE_CALL(int, isxdigit(c), LC_CTYPE);
}
int toupper_l(int c, locale_t locale) {
    JAGUAR_LOCALE_CALL(int, toupper(c), LC_CTYPE);
}
int tolower_l(int c, locale_t locale) {
    JAGUAR_LOCALE_CALL(int, tolower(c), LC_CTYPE);
}
int strcoll_l(const char *a, const char *b, locale_t locale) {
    JAGUAR_LOCALE_CALL(int, strcoll(a, b), LC_COLLATE);
}
size_t strxfrm_l(char *dest, const char *src, size_t n, locale_t locale) {
    JAGUAR_LOCALE_CALL(size_t, strxfrm(dest, src, n), LC_COLLATE);
}
size_t strftime_l(char *dest, size_t n, const char *format, const struct tm *time, locale_t locale) {
    JAGUAR_LOCALE_CALL(size_t, strftime(dest, n, format, time), LC_TIME);
}
size_t jaguar_mb_cur_max(locale_t locale) {
    JAGUAR_LOCALE_CALL(size_t, MB_CUR_MAX, LC_CTYPE);
}

int snprintf_l(char *out, size_t n, locale_t locale, const char *format, ...) {
    va_list args;
    va_start(args, format);
    char *saved = enter(locale, LC_NUMERIC);
    int result = vsnprintf(out, n, format, args);
    leave(LC_NUMERIC, saved);
    va_end(args);
    return result;
}
int asprintf_l(char **out, locale_t locale, const char *format, ...) {
    va_list args;
    va_start(args, format);
    char *saved = enter(locale, LC_NUMERIC);
    int result = vasprintf(out, format, args);
    leave(LC_NUMERIC, saved);
    va_end(args);
    return result;
}
int sscanf_l(const char *input, locale_t locale, const char *format, ...) {
    va_list args;
    va_start(args, format);
    char *saved = enter(locale, LC_NUMERIC);
    int result = vsscanf(input, format, args);
    leave(LC_NUMERIC, saved);
    va_end(args);
    return result;
}

#include <wchar.h>
#include <wctype.h>

#define JAGUAR_WCLASS(name, mask) \
    int name(wint_t c, locale_t locale) { \
        JAGUAR_LOCALE_CALL(int, !!__maskrune(c, mask), LC_CTYPE); \
    }

JAGUAR_WCLASS(iswspace_l, _CTYPE_S)
JAGUAR_WCLASS(iswprint_l, _CTYPE_R)
JAGUAR_WCLASS(iswcntrl_l, _CTYPE_C)
JAGUAR_WCLASS(iswupper_l, _CTYPE_U)
JAGUAR_WCLASS(iswlower_l, _CTYPE_L)
JAGUAR_WCLASS(iswalpha_l, _CTYPE_A)
JAGUAR_WCLASS(iswblank_l, _CTYPE_B)
JAGUAR_WCLASS(iswdigit_l, _CTYPE_D)
JAGUAR_WCLASS(iswpunct_l, _CTYPE_P)
JAGUAR_WCLASS(iswxdigit_l, _CTYPE_X)

int iswctype_l(wint_t c, wctype_t type, locale_t locale) {
    JAGUAR_LOCALE_CALL(int, !!__maskrune(c, type), LC_CTYPE);
}
wint_t towupper_l(wint_t c, locale_t locale) {
    JAGUAR_LOCALE_CALL(wint_t, __toupper(c), LC_CTYPE);
}
wint_t towlower_l(wint_t c, locale_t locale) {
    JAGUAR_LOCALE_CALL(wint_t, __tolower(c), LC_CTYPE);
}
int mbtowc_l(wchar_t *out, const char *input, size_t n, locale_t locale) {
    JAGUAR_LOCALE_CALL(int, mbtowc(out, input, n), LC_CTYPE);
}
wint_t btowc_l(int c, locale_t locale) {
    wchar_t out = 0;
    char byte = (char)c;
    return c == EOF || mbtowc_l(&out, &byte, 1, locale) < 0 ? WEOF : (wint_t)out;
}
int wctob_l(wint_t c, locale_t locale) {
    char bytes[16];
    char *saved = enter(locale, LC_CTYPE);
    int result = c == WEOF ? -1 : wctomb(bytes, (wchar_t)c);
    leave(LC_CTYPE, saved);
    return result == 1 ? (unsigned char)bytes[0] : EOF;
}


static size_t decode(wchar_t *out, const char *input, size_t n, mbstate_t *state) {
    size_t count = state->count;
    size_t consumed = 0;
    while (consumed < n && count < sizeof(state->bytes)) {
        state->bytes[count++] = (unsigned char)input[consumed++];
        int result = mbtowc(out, (const char *)state->bytes, count);
        if (result >= 0) {
            state->count = 0;
            return result ? consumed : 0;
        }
        if (!state->bytes[count - 1] || count >= MB_CUR_MAX)
            break;
    }
    if (count < sizeof(state->bytes) && count < MB_CUR_MAX &&
        (!count || state->bytes[count - 1])) {
        state->count = count;
        return (size_t)-2;
    }
    state->count = 0;
    errno = EILSEQ;
    return (size_t)-1;
}

static mbstate_t decode_state;
size_t mbrtowc_l(wchar_t *out, const char *input, size_t n, mbstate_t *state, locale_t locale) {
    wchar_t discarded;
    char *saved = enter(locale, LC_CTYPE);
    if (!state)
        state = &decode_state;
    if (!input) {
        input = "";
        n = 1;
        out = NULL;
    }
    size_t result = decode(out ? out : &discarded, input, n, state);
    leave(LC_CTYPE, saved);
    return result;
}
size_t mbrlen_l(const char *input, size_t n, mbstate_t *state, locale_t locale) {
    return mbrtowc_l(NULL, input, n, state, locale);
}
size_t wcrtomb_l(char *out, wchar_t c, mbstate_t *state, locale_t locale) {
    (void)state;
    char scratch[16];
    if (!out) {
        out = scratch;
        c = 0;
    }
    char *saved = enter(locale, LC_CTYPE);
    int result = wctomb(out, c);
    if (result < 0)
        errno = EILSEQ;
    leave(LC_CTYPE, saved);
    return result < 0 ? (size_t)-1 : (size_t)result;
}
size_t mbsnrtowcs_l(wchar_t *dest, const char **src, size_t bytes, size_t n, mbstate_t *state, locale_t locale) {
    char *saved = enter(locale, LC_CTYPE);
    if (!state)
        state = &decode_state;
    mbstate_t copy = *state;
    mbstate_t *active = dest ? state : &copy;
    const char *current = *src;
    size_t written = 0;
    while (bytes && (!dest || written < n)) {
        wchar_t value;
        size_t length = decode(&value, current, bytes, active);
        if (length == (size_t)-1) {
            written = length;
            break;
        }
        if (length == (size_t)-2) {
            current += bytes;
            break;
        }
        if (dest)
            dest[written] = value;
        if (!length) {
            current = NULL;
            break;
        }
        current += length;
        bytes -= length;
        ++written;
    }
    if (dest)
        *src = current;
    leave(LC_CTYPE, saved);
    return written;
}
size_t mbsrtowcs_l(wchar_t *dest, const char **src, size_t n, mbstate_t *state, locale_t locale) {
    return mbsnrtowcs_l(dest, src, strlen(*src) + 1, n, state, locale);
}
size_t wcsnrtombs_l(char *dest, const wchar_t **src, size_t count, size_t n, mbstate_t *state, locale_t locale) {
    (void)state;
    char *saved = enter(locale, LC_CTYPE);
    const wchar_t *current = *src;
    size_t written = 0;
    while (count--) {
        char bytes[16];
        int length = wctomb(bytes, *current);
        if (length < 0) {
            errno = EILSEQ;
            written = (size_t)-1;
            break;
        }
        if (dest && (size_t)length > n - written)
            break;
        if (dest)
            memcpy(dest + written, bytes, length);
        if (!*current++) {
            current = NULL;
            break;
        }
        written += length;
    }
    if (dest)
        *src = current;
    leave(LC_CTYPE, saved);
    return written;
}

static char *narrow(const wchar_t *input) {
    size_t length = wcstombs(NULL, input, 0);
    if (length == (size_t)-1) {
        errno = EILSEQ;
        return NULL;
    }
    char *result = malloc(length + 1);
    if (result)
        wcstombs(result, input, length + 1);
    return result;
}

#define JAGUAR_WIDE_NUMBER(name, narrow_name, type, extra, args)           \
    type name(const wchar_t *input, wchar_t **end extra) {                \
        char *converted = narrow(input);                                \
        if (end)                                                         \
            *end = (wchar_t *)input;                                     \
        if (!converted)                                                  \
            return 0;                                                    \
        char *stop;                                                      \
        type result = narrow_name args;                                  \
        int error = errno;                                               \
        if (end && stop != converted) {                                  \
            size_t offset = 0;                                           \
            size_t consumed = stop - converted;                          \
            while (*input && offset < consumed) {                        \
                char bytes[16];                                          \
                int length = wctomb(bytes, *input);                       \
                if (length < 0 || offset + (size_t)length > consumed)      \
                    break;                                               \
                offset += length;                                        \
                ++input;                                                 \
            }                                                            \
            *end = (wchar_t *)input;                                     \
        }                                                                \
        free(converted);                                                 \
        errno = error;                                                   \
        return result;                                                   \
    }
#define JAGUAR_BASE , int base
JAGUAR_WIDE_NUMBER(wcstol, strtol, long, JAGUAR_BASE, (converted, &stop, base))
JAGUAR_WIDE_NUMBER(wcstoul, strtoul, unsigned long, JAGUAR_BASE, (converted, &stop, base))
JAGUAR_WIDE_NUMBER(wcstoll, strtoll, long long, JAGUAR_BASE, (converted, &stop, base))
JAGUAR_WIDE_NUMBER(wcstoull, strtoull, unsigned long long, JAGUAR_BASE, (converted, &stop, base))
JAGUAR_WIDE_NUMBER(wcstof, strtof, float, , (converted, &stop))
JAGUAR_WIDE_NUMBER(wcstod, strtod, double, , (converted, &stop))
JAGUAR_WIDE_NUMBER(wcstold, strtold, long double, , (converted, &stop))


int wcscoll_l(const wchar_t *left, const wchar_t *right, locale_t locale) {
    char *saved = enter(locale, LC_CTYPE);
    char *a = narrow(left);
    char *b = narrow(right);
    leave(LC_CTYPE, saved);
    int result = a && b ? strcoll_l(a, b, locale) : wmemcmp(left, right, 0);
    if (!a || !b) {
        while (*left && *left == *right) {
            ++left;
            ++right;
        }
        result = (*left > *right) - (*left < *right);
    }
    free(a);
    free(b);
    return result;
}

size_t wcsxfrm_l(wchar_t *out, const wchar_t *src, size_t n, locale_t locale) {
    char *saved = enter(locale, LC_CTYPE);
    char *input = narrow(src);
    leave(LC_CTYPE, saved);
    if (!input)
        return (size_t)-1;
    size_t length = strxfrm_l(NULL, input, 0, locale);
    if (length < n) {
        char *key = malloc(length + 1);
        if (!key) {
            free(input);
            return (size_t)-1;
        }
        length = strxfrm_l(key, input, length + 1, locale);
        if (length < n)
            for (size_t i = 0; i <= length; ++i)
                out[i] = (unsigned char)key[i];
        free(key);
    }
    free(input);
    return length;
}

int swprintf(wchar_t *out, size_t n, const wchar_t *format, ...) {
    const wchar_t *end = format;
    while (*end && *end < 128)
        ++end;
    if (*end || (format[0] != L'%' ||
                 !((format[1] == L'f' && !format[2]) ||
                   (format[1] == L'L' && format[2] == L'f' && !format[3])))) {
        errno = EINVAL;
        return -1;
    }
    va_list args;
    va_start(args, format);
    char *narrow_output = NULL;
    pthread_mutex_lock(&locale_mutex);
    int result = vasprintf(&narrow_output, format[1] == L'L' ? "%Lf" : "%f", args);
    va_end(args);
    if (result >= 0) {
        size_t needed = mbstowcs(NULL, narrow_output, 0);
        if (needed < n) {
            mbstowcs(out, narrow_output, n);
            result = (int)needed;
        } else {
            result = -1;
        }
    }
    free(narrow_output);
    pthread_mutex_unlock(&locale_mutex);
    return result;
}
