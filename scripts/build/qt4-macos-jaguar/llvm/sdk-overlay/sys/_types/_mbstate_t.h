// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

#ifndef JAGUAR_COMPAT_MBSTATE_T_H
#define JAGUAR_COMPAT_MBSTATE_T_H
/* Storage reserved for a restartable multibyte implementation. */
typedef struct {
    unsigned char bytes[4];
    unsigned int count;
} mbstate_t;
#endif
