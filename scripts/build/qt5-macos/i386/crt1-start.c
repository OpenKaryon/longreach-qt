// SPDX-License-Identifier: LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
// Copyright (C) 2026 OpenKaryon
//
// The i386 startup object crt1.10.6.o. The SDKs this kit builds with carry no
// i386 startup object, and from 10.8 on there is none at all (LC_MAIN replaced
// it). This is what one does on 10.5 and newer: dyld has already run the
// libSystem initializers, so all that is left is to publish the program
// variables, which dyld looks up in the main executable by these names for
// libSystem's _NSGetArgv() and friends, and to call main().
#include <stddef.h>

// The entry point. The kernel jumps here, it does not call: there is no return
// address, argc, argv[], 0, envp[], 0, apple[] lie on the stack, and the stack
// is not aligned, which no C function prologue can take. So start aligns the
// stack to 16 bytes, as the i386 ABI of Mac OS X requires, and passes argc,
// argv and envp to _start().
__asm__(
    ".text\n"
    ".globl start\n"
    ".align 2\n"
    "start:\n"
    "    pushl $0\n"                // end of the frame chain, for debuggers
    "    movl  %esp, %ebp\n"
    "    andl  $-16, %esp\n"
    "    subl  $16, %esp\n"
    "    movl  4(%ebp), %ebx\n"     // argc
    "    movl  %ebx, 0(%esp)\n"
    "    leal  8(%ebp), %ecx\n"     // argv
    "    movl  %ecx, 4(%esp)\n"
    "    addl  $1, %ebx\n"          // envp = argv + argc + 1
    "    sall  $2, %ebx\n"
    "    addl  %ecx, %ebx\n"
    "    movl  %ebx, 8(%esp)\n"
    "    call  __start\n"
    "    hlt\n");

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
