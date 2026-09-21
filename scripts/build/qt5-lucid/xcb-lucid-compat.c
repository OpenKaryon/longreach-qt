// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

/*
 * Core libxcb functions newer than Lucid's libxcb 1.5 that the 1.11
 * extension wrappers call. The wrappers are compiled with these names
 * redirected here (see build-xdeps.sh); each forwards to the system libxcb's
 * function when it has one (looked up at run time, so a binary built for
 * Lucid still uses it on newer systems) and otherwise takes the path a
 * 1.5-era library would.
 *
 * fd passing (libxcb 1.10) is used only by MIT-SHM 1.2's CreateSegment and
 * AttachFd. Qt uses them only when the X server offers SHM 1.2, which
 * Lucid's X.Org 1.7 does not; there Qt stays on SysV shared memory.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>
#include <xcb/xcb.h>

void qt_lucid_xcb_send_fd(xcb_connection_t *c, int fd)
{
    typedef void (*Fn)(xcb_connection_t *, int);
    static Fn fn;
    static int resolved;
    if (!resolved) {
        fn = (Fn)dlsym(RTLD_DEFAULT, "xcb_send_fd");
        resolved = 1;
    }
    if (fn)
        fn(c, fd);
    else
        close(fd); /* xcb_send_fd takes ownership of the descriptor */
}

int *qt_lucid_xcb_get_reply_fds(xcb_connection_t *c, void *reply, size_t reply_size)
{
    typedef int *(*Fn)(xcb_connection_t *, void *, size_t);
    static Fn fn;
    static int resolved;
    if (!resolved) {
        fn = (Fn)dlsym(RTLD_DEFAULT, "xcb_get_reply_fds");
        resolved = 1;
    }
    return fn ? fn(c, reply, reply_size) : NULL;
}

/* libxcb 1.6. Without it, a reply that is not wanted is still read and
 * freed, which is what discarding means for the caller. */
void qt_lucid_xcb_discard_reply(xcb_connection_t *c, unsigned int sequence)
{
    typedef void (*Fn)(xcb_connection_t *, unsigned int);
    static Fn fn;
    static int resolved;
    if (!resolved) {
        fn = (Fn)dlsym(RTLD_DEFAULT, "xcb_discard_reply");
        resolved = 1;
    }
    if (fn) {
        fn(c, sequence);
        return;
    }
    xcb_void_cookie_t cookie = { sequence };
    xcb_generic_error_t *error = NULL;
    free(xcb_wait_for_reply(c, cookie.sequence, &error));
    free(error);
}

/* Pure size helpers the 1.11 generator emits (libxcb 1.8/1.9); computed
 * here exactly as libxcb does. */
int qt_lucid_xcb_str_sizeof(const void *buffer)
{
    return (int)(sizeof(xcb_str_t) + ((const xcb_str_t *)buffer)->name_len);
}

int qt_lucid_xcb_sumof(uint8_t *list, int len)
{
    int sum = 0;
    for (int i = 0; i < len; ++i)
        sum += list[i];
    return sum;
}
