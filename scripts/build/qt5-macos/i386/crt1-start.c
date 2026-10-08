// SPDX-License-Identifier: LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
// Copyright (C) 2026 OpenKaryon
//
// C half of the i386 crt1.10.6.o (see crt1-start.s). The SDKs this kit builds
// with carry no i386 startup object, and from 10.8 on there is none at all
// (LC_MAIN replaced it). This is what one does on 10.5 and newer: dyld has
// already run the libSystem initializers, so all that is left is to publish
// the program variables, which dyld looks up in the main executable by these
// names for libSystem's _NSGetArgv() and friends, and to call main().
#include <stddef.h>

extern int main(int argc, const char *argv[], const char *envp[], const char *apple[]);
extern void exit(int) __attribute__((noreturn));

int NXArgc = 0;
const char **NXArgv = NULL;
const char **environ = NULL;
const char *__progname = NULL;

__attribute__((noreturn, used)) void _start(int argc, const char *argv[], const char *envp[])
{
    NXArgc = argc;
    NXArgv = argv;
    environ = envp;
    __progname = "";
    if (argv[0] != NULL) {
        const char *p = argv[0];
        __progname = p;
        for (; *p; ++p) {
            if (*p == '/')
                __progname = p + 1;
        }
    }
    const char **apple = envp;
    while (*apple != NULL)
        ++apple;
    ++apple;
    exit(main(argc, argv, envp, apple));
}
