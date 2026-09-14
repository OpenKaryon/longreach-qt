// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Print enough about a fatal exception to find it in the binary afterwards.
//
// Written for the XP box, where qt-selftest runs every check, prints its
// summary, returns 0 from main() - and then dies with 0xC0000005 on the way
// out, during static destruction. There is no crash report to read there the
// way macOS hands one over, and attaching a debugger to a teardown that happens
// after main() is awkward, so the process reports on itself instead.
//
// What is printed is chosen to survive a stripped, -Os, no-frame-pointer build:
//
//   - the exception code and the faulting address
//   - the module base, so the address can be turned into an RVA and looked up
//     with nm/objdump on the very same binary
//   - the addresses on the stack that fall inside this module's code, which is
//     a crude but effective substitute for a backtrace when frame pointers have
//     been optimised away
//
// Windows only, and deliberately printf rather than QTextStream: by the time
// this runs, Qt's own machinery is half torn down.
#ifndef CRASHINFO_H
#define CRASHINFO_H

#ifdef Q_OS_WIN

#include <qt_windows.h>
#include <cstdio>

namespace SmokeCrashInfo {

inline const char *exceptionName(DWORD code)
{
    switch (code) {
    case EXCEPTION_ACCESS_VIOLATION:      return "access violation";
    case EXCEPTION_ARRAY_BOUNDS_EXCEEDED: return "array bounds exceeded";
    case EXCEPTION_DATATYPE_MISALIGNMENT: return "datatype misalignment";
    case EXCEPTION_ILLEGAL_INSTRUCTION:   return "illegal instruction";
    case EXCEPTION_IN_PAGE_ERROR:         return "in-page error";
    case EXCEPTION_INT_DIVIDE_BY_ZERO:    return "integer divide by zero";
    case EXCEPTION_PRIV_INSTRUCTION:      return "privileged instruction";
    case EXCEPTION_STACK_OVERFLOW:        return "stack overflow";
    case 0xC0000374:                      return "heap corruption";
    case 0xC0000409:                      return "stack buffer overrun";
    default:                              return "unknown";
    }
}

inline LONG WINAPI report(EXCEPTION_POINTERS *info)
{
    const EXCEPTION_RECORD *er = info->ExceptionRecord;
    const CONTEXT *cr = info->ContextRecord;

    // A null module name has no encoding. The ANSI spelling also works on
    // Win9x, where GetModuleHandleW can be an unimplemented export stub.
    const BYTE *base = reinterpret_cast<const BYTE *>(GetModuleHandleA(nullptr));
    DWORD imageSize = 0;
    if (base) {
        const IMAGE_DOS_HEADER *dos = reinterpret_cast<const IMAGE_DOS_HEADER *>(base);
        const IMAGE_NT_HEADERS *nt =
            reinterpret_cast<const IMAGE_NT_HEADERS *>(base + dos->e_lfanew);
        imageSize = nt->OptionalHeader.SizeOfImage;
    }

    const BYTE *fault = reinterpret_cast<const BYTE *>(er->ExceptionAddress);

    std::printf("\n=== fatal exception ===\n");
    std::printf("code    0x%08lX (%s)\n",
                static_cast<unsigned long>(er->ExceptionCode),
                exceptionName(er->ExceptionCode));
    if (er->ExceptionCode == EXCEPTION_ACCESS_VIOLATION && er->NumberParameters >= 2) {
        std::printf("tried to %s address 0x%08lX\n",
                    er->ExceptionInformation[0] ? "write" : "read",
                    static_cast<unsigned long>(er->ExceptionInformation[1]));
        const void *target = reinterpret_cast<const void *>(er->ExceptionInformation[1]);
        MEMORY_BASIC_INFORMATION targetMemory;
        if (VirtualQuery(target, &targetMemory, sizeof(targetMemory)))
            std::printf("access target region base=%p allocation=%p bytes=%lu state=%08lX protect=%08lX type=%08lX\n",
                        targetMemory.BaseAddress, targetMemory.AllocationBase,
                        static_cast<unsigned long>(targetMemory.RegionSize),
                        static_cast<unsigned long>(targetMemory.State),
                        static_cast<unsigned long>(targetMemory.Protect),
                        static_cast<unsigned long>(targetMemory.Type));
        else
            std::printf("access target query failed: error=%lu\n", static_cast<unsigned long>(GetLastError()));
    }
    std::printf("at      %p\n", static_cast<const void *>(fault));
#if defined(_M_IX86) || defined(__i386__)
    std::printf("registers EAX=%08lX EBX=%08lX ECX=%08lX EDX=%08lX ESP=%08lX\n",
                static_cast<unsigned long>(cr->Eax), static_cast<unsigned long>(cr->Ebx),
                static_cast<unsigned long>(cr->Ecx), static_cast<unsigned long>(cr->Edx),
                static_cast<unsigned long>(cr->Esp));
    std::printf("context EIP=%08lX EBP=%08lX ESI=%08lX EDI=%08lX CS=%04lX DS=%04lX\n",
                static_cast<unsigned long>(cr->Eip), static_cast<unsigned long>(cr->Ebp),
                static_cast<unsigned long>(cr->Esi), static_cast<unsigned long>(cr->Edi),
                static_cast<unsigned long>(cr->SegCs), static_cast<unsigned long>(cr->SegDs));
#endif
    MEMORY_BASIC_INFORMATION memory;
    if (VirtualQuery(fault, &memory, sizeof(memory)))
        std::printf("fault region base=%p allocation=%p bytes=%lu state=%08lX protect=%08lX type=%08lX\n",
                    memory.BaseAddress, memory.AllocationBase,
                    static_cast<unsigned long>(memory.RegionSize), static_cast<unsigned long>(memory.State),
                    static_cast<unsigned long>(memory.Protect), static_cast<unsigned long>(memory.Type));
    if (!IsBadReadPtr(fault, 16)) {
        std::printf("bytes  ");
        for (int i = 0; i < 16; ++i)
            std::printf(" %02X", static_cast<unsigned int>(fault[i]));
        std::printf("\n");
    }
    std::printf("module  %p + 0x%lX bytes\n",
                static_cast<const void *>(base),
                static_cast<unsigned long>(imageSize));
    if (base && fault >= base && fault < base + imageSize) {
        std::printf("RVA     0x%08lX   <- look this up in the binary\n",
                    static_cast<unsigned long>(fault - base));
    } else {
        std::printf("RVA     (faulting address is outside this module)\n");
    }

    // Frame pointers are gone at -Os: report what looks like return addresses into
    // this module from the raw stack (candidates, not a backtrace). The stack
    // pointer's name depends on the toolchain's macros and the architecture,
    // ARM64 included.
#if defined(_M_IX86) || defined(__i386__)
    const void **sp = reinterpret_cast<const void **>(cr->Esp);
#elif defined(_M_ARM64) || defined(__aarch64__)
    const void **sp = reinterpret_cast<const void **>(cr->Sp);
#elif defined(_M_ARM) || defined(__arm__)
    const void **sp = reinterpret_cast<const void **>(cr->Sp);
#else
    const void **sp = reinterpret_cast<const void **>(cr->Rsp);
#endif
    std::printf("stack candidates (RVA):\n");
    int printed = 0;
    for (int i = 0; i < 4096 && printed < 24; ++i) {
        const BYTE *value = nullptr;
        // Reading the stack can itself fault if we walk off the end of it.
        if (IsBadReadPtr(sp + i, sizeof(void *)))
            break;
        value = reinterpret_cast<const BYTE *>(sp[i]);
        if (base && value > base && value < base + imageSize) {
            std::printf("  0x%08lX\n", static_cast<unsigned long>(value - base));
            ++printed;
        }
    }
    if (!printed)
        std::printf("  (none found)\n");
    std::printf("=== end ===\n");
    std::fflush(stdout);

    return EXCEPTION_EXECUTE_HANDLER;   // die, but quietly and without a dialog
}

// Installed once, early. Stays installed through static destruction, which is
// the whole point - the crash being chased happens after main() returns.
inline void install()
{
#if defined(QT_WIN95_SUPPORT)
    // Flush before calling either Qt or the Windows exception machinery. An
    // empty child log alone otherwise cannot distinguish pre-main loading
    // from QApplication construction or a failed handler installation.
    std::fputs("Startup: installing exception handler\n", stdout);
    std::fflush(stdout);
#endif
    SetUnhandledExceptionFilter(report);
    // XP pops up "the application has encountered a problem" otherwise, which
    // blocks the runner until it times out.
    SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);
#if defined(QT_WIN95_SUPPORT)
    std::fputs("Startup: exception handler installed\n", stdout);
    std::fflush(stdout);
#endif
}

} // namespace SmokeCrashInfo

#endif // Q_OS_WIN

#endif // CRASHINFO_H
