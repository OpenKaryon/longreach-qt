// SPDX-License-Identifier: LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
// Copyright (C) 2026 OpenKaryon

/*
 * libX11-xcb for the Lucid target. Ubuntu 10.04 ships libX11-xcb.so.1 in
 * libx11-xcb1, which a stock desktop does not install. Linking this static
 * stub instead keeps the library out of DT_NEEDED: it loads
 * libX11-xcb.so.1 on first use when it is installed, and otherwise
 * XGetXCBConnection returns null, which patches/qt5/linux/02 takes as
 * "run without Xlib".
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stddef.h>
#include <X11/Xlib.h>
#include <X11/Xlib-xcb.h>

static void *x11xcb(void)
{
    static void *handle;
    static int tried;
    if (!tried) {
        tried = 1;
        handle = dlopen("libX11-xcb.so.1", RTLD_NOW | RTLD_GLOBAL);
    }
    return handle;
}

xcb_connection_t *XGetXCBConnection(Display *dpy)
{
    typedef xcb_connection_t *(*Fn)(Display *);
    Fn fn = x11xcb() ? (Fn)dlsym(x11xcb(), "XGetXCBConnection") : NULL;
    return fn ? fn(dpy) : NULL;
}

void XSetEventQueueOwner(Display *dpy, enum XEventQueueOwner owner)
{
    typedef void (*Fn)(Display *, enum XEventQueueOwner);
    Fn fn = x11xcb() ? (Fn)dlsym(x11xcb(), "XSetEventQueueOwner") : NULL;
    if (fn)
        fn(dpy, owner);
}
