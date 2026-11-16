// SPDX-License-Identifier: LGPL-2.1-only OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
// Copyright (C) 2026 OpenKaryon

__attribute__((visibility("hidden"))) void *__dso_handle = &__dso_handle;
extern void __cxa_finalize(void *);

__attribute__((destructor)) static void finalize_dso(void)
{
    __cxa_finalize(&__dso_handle);
}
