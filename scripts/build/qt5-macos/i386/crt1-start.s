# SPDX-License-Identifier: LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
# Copyright (C) 2026 OpenKaryon
#
# Entry point of an i386 executable for Mac OS X 10.6 (crt1.10.6.o, with
# crt1-start.c). The kernel starts the main thread here with argc, argv[],
# 0, envp[], 0, apple[] on the stack. This passes argc, argv and envp to
# _start() on a 16-byte aligned stack, as the i386 ABI of Mac OS X requires.
        .text
        .globl  start
        .align  2
start:
        pushl   $0              # end of the frame chain, for debuggers
        movl    %esp, %ebp
        andl    $-16, %esp
        subl    $16, %esp
        movl    4(%ebp), %ebx   # argc
        movl    %ebx, 0(%esp)
        leal    8(%ebp), %ecx   # argv
        movl    %ecx, 4(%esp)
        addl    $1, %ebx        # envp = argv + argc + 1
        sall    $2, %ebx
        addl    %ecx, %ebx
        movl    %ebx, 8(%esp)
        call    __start
        hlt

.subsections_via_symbols
