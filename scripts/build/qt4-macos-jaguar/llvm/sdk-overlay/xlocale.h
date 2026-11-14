// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

#ifndef JAGUAR_PROBE_XLOCALE_H
#define JAGUAR_PROBE_XLOCALE_H
/* Syntax probe declarations. Runtime definitions are still required. */
#include <stddef.h>
#include <locale.h>

#define LC_COLLATE_MASK (1 << LC_COLLATE)
#define LC_CTYPE_MASK (1 << LC_CTYPE)
#define LC_MONETARY_MASK (1 << LC_MONETARY)
#define LC_NUMERIC_MASK (1 << LC_NUMERIC)
#define LC_TIME_MASK (1 << LC_TIME)
#define LC_MESSAGES_MASK (1 << LC_MESSAGES)
#define LC_ALL_MASK (LC_COLLATE_MASK | LC_CTYPE_MASK | LC_MONETARY_MASK | LC_NUMERIC_MASK | LC_TIME_MASK | LC_MESSAGES_MASK)

typedef struct jaguar_locale *locale_t;

#ifdef __cplusplus
extern "C" {
#endif
locale_t newlocale(int, const char *, locale_t);
void freelocale(locale_t);
struct lconv *localeconv_l(locale_t);
int toupper_l(int, locale_t);
int tolower_l(int, locale_t);
int strcoll_l(const char *, const char *, locale_t);
size_t strxfrm_l(char *, const char *, size_t, locale_t);
size_t strftime_l(char *, size_t, const char *, const struct tm *, locale_t);
size_t jaguar_mb_cur_max(locale_t);
#define MB_CUR_MAX_L(loc) jaguar_mb_cur_max(loc)

#if defined(_LIBCPP_HAS_WIDE_CHARACTERS) && _LIBCPP_HAS_WIDE_CHARACTERS
int iswctype_l(wint_t, wctype_t, locale_t);
int iswspace_l(wint_t, locale_t);
int iswprint_l(wint_t, locale_t);
int iswcntrl_l(wint_t, locale_t);
int iswupper_l(wint_t, locale_t);
int iswlower_l(wint_t, locale_t);
int iswalpha_l(wint_t, locale_t);
int iswblank_l(wint_t, locale_t);
int iswdigit_l(wint_t, locale_t);
int iswpunct_l(wint_t, locale_t);
int iswxdigit_l(wint_t, locale_t);
wint_t towupper_l(wint_t, locale_t);
wint_t towlower_l(wint_t, locale_t);
int wcscoll_l(const wchar_t *, const wchar_t *, locale_t);
size_t wcsxfrm_l(wchar_t *, const wchar_t *, size_t, locale_t);
wint_t btowc_l(int, locale_t);
int wctob_l(wint_t, locale_t);
size_t wcsnrtombs_l(char *, const wchar_t **, size_t, size_t, mbstate_t *, locale_t);
size_t wcrtomb_l(char *, wchar_t, mbstate_t *, locale_t);
size_t mbsnrtowcs_l(wchar_t *, const char **, size_t, size_t, mbstate_t *, locale_t);
size_t mbrtowc_l(wchar_t *, const char *, size_t, mbstate_t *, locale_t);
int mbtowc_l(wchar_t *, const char *, size_t, locale_t);
size_t mbrlen_l(const char *, size_t, mbstate_t *, locale_t);
size_t mbsrtowcs_l(wchar_t *, const char **, size_t, mbstate_t *, locale_t);
#endif

float strtof_l(const char *, char **, locale_t);
double strtod_l(const char *, char **, locale_t);
long double strtold_l(const char *, char **, locale_t);
long long strtoll_l(const char *, char **, int, locale_t);
unsigned long long strtoull_l(const char *, char **, int, locale_t);
int isdigit_l(int, locale_t);
int isxdigit_l(int, locale_t);
int snprintf_l(char *, size_t, locale_t, const char *, ...);
int asprintf_l(char **, locale_t, const char *, ...);
int sscanf_l(const char *, locale_t, const char *, ...);
#ifdef __cplusplus
}
#endif
#endif
