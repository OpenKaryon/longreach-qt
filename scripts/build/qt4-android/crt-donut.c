// SPDX-License-Identifier: LGPL-2.1-only OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
// Copyright (C) 2026 OpenKaryon

__attribute__((visibility("hidden"))) void *__dso_handle = &__dso_handle;
extern void __cxa_finalize(void *);

#if defined(__i386__) || defined(__arm__)
/* Keep atexit local to each legacy DSO, as in Android's crtbegin. ARM's old
 * libc export is unavailable in the API21 NDK; x86 already needs this on
 * API10. Both register through __cxa_atexit using this object's own handle. */
extern int __cxa_atexit(void (*)(void *), void *, void *);
__attribute__((visibility("hidden"))) int atexit(void (*callback)(void))
{
    return __cxa_atexit((void (*)(void *))callback, 0, &__dso_handle);
}
#endif

__attribute__((destructor)) static void finalize_dso(void)
{
    __cxa_finalize(&__dso_handle);
}
