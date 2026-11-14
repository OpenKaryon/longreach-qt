// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

#ifndef JAGUAR_COMPAT_STDIO_H
#define JAGUAR_COMPAT_STDIO_H
#ifdef __STRICT_ANSI__
#pragma push_macro("__STRICT_ANSI__")
#undef __STRICT_ANSI__
#include_next <stdio.h>
#pragma pop_macro("__STRICT_ANSI__")
#else
#include_next <stdio.h>
#endif
#endif
