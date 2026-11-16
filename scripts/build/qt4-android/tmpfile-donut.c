// SPDX-License-Identifier: LGPL-2.1-only OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
// Copyright (C) 2026 OpenKaryon

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

FILE *__wrap_tmpfile(void)
{
    const char *directory = getenv("TMPDIR");
    if (!directory || !*directory)
        directory = P_tmpdir;

    char path[PATH_MAX];
    int length = snprintf(path, sizeof(path), "%s/longreach-tmp-XXXXXX", directory);
    if (length < 0 || (size_t)length >= sizeof(path)) {
        errno = ENAMETOOLONG;
        return NULL;
    }

    int fd = mkstemp(path);
    if (fd < 0)
        return NULL;
    if (unlink(path) == 0) {
        FILE *file = fdopen(fd, "w+b");
        if (file)
            return file;
    }

    int saved = errno;
    close(fd);
    errno = saved;
    return NULL;
}
