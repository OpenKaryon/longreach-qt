// SPDX-License-Identifier: GPL-3.0-or-later WITH GCC-exception-3.1
// Copyright (C) 2026 OpenKaryon

/* Declarations that let libgcc's Darwin crt3.o and crttms.o compile against
   the Mac OS X 10.2.8 SDK, which has no <dlfcn.h>: dlopen arrived in 10.3.

   The Jaguar toolchain never links either object. crt3.o emulates
   __cxa_atexit, and the compiler is configured with --disable-__cxa_atexit
   instead; crttms.o only serves -fgnu-tm. The file is copied next to those
   two sources as jaguar-dlfcn.h and included by name from them alone, so
   host-side builds such as libbacktrace still see the build machine's own
   <dlfcn.h>. */
#ifndef JAGUAR_LIBGCC_DLFCN_H
#define JAGUAR_LIBGCC_DLFCN_H

/* darwin-crt-tm.c uses uint32_t without including <stdint.h>; newer SDKs
   reach it through <dlfcn.h> and the Mach-O headers, the 10.2.8 SDK does not. */
#include <stdint.h>

#define RTLD_LAZY   0x1
#define RTLD_NOW    0x2
#define RTLD_LOCAL  0x4
#define RTLD_GLOBAL 0x8
#define RTLD_NOLOAD 0x10

typedef struct dl_info {
    const char *dli_fname;
    void *dli_fbase;
    const char *dli_sname;
    void *dli_saddr;
} Dl_info;

extern void *dlopen(const char *path, int mode) __attribute__((weak_import));
extern void *dlsym(void *handle, const char *symbol) __attribute__((weak_import));
extern int dladdr(const void *addr, Dl_info *info) __attribute__((weak_import));

#endif
