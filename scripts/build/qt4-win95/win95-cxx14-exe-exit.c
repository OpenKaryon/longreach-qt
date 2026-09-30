// SPDX-License-Identifier: LGPL-2.1-only OR GPL-3.0-only
// Copyright (C) 2026 OpenKaryon

/* Experimental EXE-only MinGW-w64 CRT adaptation, not a DLL runtime.
 * MinGW-w64 4.0.4 crt/atonexit.c uses the system _onexit for executables
 * (__onexitbegin decodes to -1); its separate DLL table requires CRT locks
 * missing from the original Win95 MSVCRT. Keep the executable path only.
 */
#include <stdlib.h>
#include <errno.h>

#ifdef _WINDLL
#error This adaptation must never be used to link a DLL
#endif

typedef void (__cdecl *exit_callback)(void);
exit_callback *__onexitbegin;
exit_callback *__onexitend;
extern _onexit_t (__cdecl *__MINGW_IMP_SYMBOL(_onexit))(_onexit_t);
extern void *__cdecl _decode_pointer(void *);

_onexit_t __cdecl mingw_onexit(_onexit_t callback)
{
    if (_decode_pointer(__onexitbegin) != (void *)-1) {
        /* Reject DLL-table mode instead of silently losing synchronization. */
        errno = EINVAL;
        return NULL;
    }
    return (*__MINGW_IMP_SYMBOL(_onexit))(callback);
}

int __cdecl atexit(exit_callback callback)
{
    return mingw_onexit((_onexit_t)callback) ? 0 : -1;
}
