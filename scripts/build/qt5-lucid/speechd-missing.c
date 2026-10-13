/* SPDX-License-Identifier: GPL-3.0-or-later */
/* Copyright (C) 2026 OpenKaryon */

/* spd_list_modules where libspeechd lacks it (Lucid's 0.6): no modules. Qt
   indexes the list without checking it for NULL. */
char **longreach_speechd_no_modules(void)
{
    static char *none[] = { 0 };
    return none;
}
