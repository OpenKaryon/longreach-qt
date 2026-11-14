// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

#ifndef JAGUAR_COMPAT_STATVFS_H
#define JAGUAR_COMPAT_STATVFS_H
#include <sys/types.h>
#include <sys/mount.h>

struct statvfs {
    unsigned long f_frsize;
    unsigned long f_blocks;
    unsigned long f_bfree;
    unsigned long f_bavail;
};

static __inline__ int statvfs(const char *path, struct statvfs *out) {
    struct statfs fs;
    if (statfs(path, &fs) == -1)
        return -1;
    out->f_frsize = fs.f_bsize;
    out->f_blocks = fs.f_blocks;
    out->f_bfree = fs.f_bfree;
    out->f_bavail = fs.f_bavail < 0 ? 0 : fs.f_bavail;
    return 0;
}
#endif
