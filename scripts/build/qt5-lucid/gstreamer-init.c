/* SPDX-License-Identifier: GPL-3.0-or-later */
/* Copyright (C) 2026 OpenKaryon */

/* gst_init and gst_init_check, which the GStreamer stub archive leaves out:
   the real ones, then a fresh copy of the GStreamer data the archive mirrors,
   which gst_init sets (GST_TYPE_BUFFER, GST_TYPE_FRACTION and the other types
   Qt reads through macros). Without libgstreamer, gst_init_check fails and
   gst_init does nothing. */
#include <dlfcn.h>
#include <stddef.h>

typedef int gboolean;
typedef struct _GError GError;

void longreach_gst_mirror(void);

static void *gstreamer(const char *name)
{
    void *handle = dlopen("libgstreamer-1.0.so.0", RTLD_NOW | RTLD_GLOBAL);
    return handle ? dlsym(handle, name) : NULL;
}

gboolean gst_init_check(int *argc, char ***argv, GError **error)
{
    gboolean (*real)(int *, char ***, GError **) =
        (gboolean (*)(int *, char ***, GError **))gstreamer("gst_init_check");
    if (!real || !real(argc, argv, error))
        return 0;
    longreach_gst_mirror();
    return 1;
}

void gst_init(int *argc, char ***argv)
{
    void (*real)(int *, char ***) = (void (*)(int *, char ***))gstreamer("gst_init");
    if (real) {
        real(argc, argv);
        longreach_gst_mirror();
    }
}
