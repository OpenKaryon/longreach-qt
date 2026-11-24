// SPDX-License-Identifier: GPL-3.0-or-later
// Freestanding Linux i386 contract probe for the actual API10 compat.c wait4.
// No Android guest is involved; success does not qualify Android runtime use.
#include <errno.h>
#include <signal.h>
#include <sys/resource.h>
#include <sys/syscall.h>
#include <sys/wait.h>

__typeof__(__errno()) __errno(void)
{
    static __typeof__(*__errno()) value;
    return &value;
}

static int kernel_call0(int number)
{
    int result;
    __asm__ volatile("int $0x80" : "=a"(result) : "0"(number) : "cc", "memory");
    return result;
}

static int kernel_kill(int process, int signal_number)
{
    int result;
    __asm__ volatile("xchgl %%ebx, %1\n\tint $0x80\n\txchgl %%ebx, %1"
                     : "=a"(result), "+D"(process)
                     : "0"(__NR_kill), "c"(signal_number) : "cc", "memory");
    return result;
}

__attribute__((noreturn)) static void finish(int status)
{
    __asm__ volatile("int $0x80" : : "a"(__NR_exit), "b"(status) : "cc", "memory");
    __builtin_unreachable();
}

void _start(void)
{
    int status = 0;
    struct rusage usage;
    errno = 0;
    if (wait4(-1, &status, WNOHANG, &usage) != -1 || errno != ECHILD)
        finish(11);

    int child = kernel_call0(__NR_fork);
    if (child < 0)
        finish(12);
    if (child == 0)
        finish(37);
    usage.ru_utime.tv_sec = usage.ru_stime.tv_sec = -1;
    if (wait4(child, &status, 0, &usage) != child)
        finish(13);
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 37)
        finish(14);
    if (usage.ru_utime.tv_sec < 0 || usage.ru_stime.tv_sec < 0)
        finish(15);

    child = kernel_call0(__NR_fork);
    if (child < 0)
        finish(16);
    if (child == 0) {
        for (;;)
            kernel_call0(__NR_pause);
    }
    const int pending = wait4(child, &status, WNOHANG, 0);
    if (kernel_kill(child, SIGTERM) != 0)
        finish(17);
    const int reaped = wait4(child, &status, 0, 0);
    if (pending != 0 || reaped != child)
        finish(18);
    if (!WIFSIGNALED(status) || WTERMSIG(status) != SIGTERM)
        finish(19);
    finish(0);
}
