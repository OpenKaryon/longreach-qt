// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

#ifndef SMOKE_WIN95_CODE_IMAGE_H
#define SMOKE_WIN95_CODE_IMAGE_H

#if defined(Q_OS_WIN) && defined(QT_WIN95_SUPPORT)
#include <windows.h>
#include <cstdio>
#include <cstring>

extern "C" {
extern const unsigned char __RUNTIME_PSEUDO_RELOC_LIST__[];
extern const unsigned char __RUNTIME_PSEUDO_RELOC_LIST_END__[];
}

// Compare this fixed-base image's loaded code with its own file. No Qt calls:
// the diagnostic must also work before QApplication construction. Reading all
// code pages changes paging/cache state, so this is an explicit diagnostic,
// never a replacement for the normal gallery selftest.
inline int verifyWin95CodeImage()
{
    const unsigned char *base = reinterpret_cast<const unsigned char *>(GetModuleHandleA(0));
    const IMAGE_DOS_HEADER *dos = reinterpret_cast<const IMAGE_DOS_HEADER *>(base);
    if (!base || dos->e_magic != IMAGE_DOS_SIGNATURE)
        return 2;
    const IMAGE_NT_HEADERS *nt = reinterpret_cast<const IMAGE_NT_HEADERS *>(base + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE
            || nt->OptionalHeader.ImageBase != reinterpret_cast<ULONG_PTR>(base)
            || nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_BASERELOC].Size
            || __RUNTIME_PSEUDO_RELOC_LIST__ != __RUNTIME_PSEUDO_RELOC_LIST_END__) {
        std::puts("CODE comparison unavailable: image has runtime relocations");
        return 2;
    }
    char path[MAX_PATH];
    const DWORD length = GetModuleFileNameA(0, path, sizeof(path));
    if (!length || length >= sizeof(path))
        return 2;
    FILE *file = std::fopen(path, "rb");
    if (!file)
        return 2;
    unsigned char expected[4096];
    unsigned int pages = 0, mismatches = 0, sections = 0;
    int result = 0;
    const IMAGE_SECTION_HEADER *section = IMAGE_FIRST_SECTION(nt);
    for (unsigned int i = 0; i < nt->FileHeader.NumberOfSections; ++i) {
        if (!(section[i].Characteristics & IMAGE_SCN_CNT_CODE))
            continue;
        ++sections;
        const DWORD bytes = section[i].Misc.VirtualSize < section[i].SizeOfRawData
            ? section[i].Misc.VirtualSize : section[i].SizeOfRawData;
        if (std::fseek(file, section[i].PointerToRawData, SEEK_SET)) {
            result = 2;
            break;
        }
        for (DWORD offset = 0; offset < bytes; offset += sizeof(expected)) {
            const DWORD count = bytes - offset < sizeof(expected) ? bytes - offset : sizeof(expected);
            if (std::fread(expected, 1, count, file) != count) {
                result = 2;
                break;
            }
            const DWORD rva = section[i].VirtualAddress + offset;
            const unsigned char *actual = base + rva;
            ++pages;
            if (std::memcmp(expected, actual, count)) {
                ++mismatches;
                if (mismatches <= 8) {
                    DWORD first = 0;
                    while (first < count && expected[first] == actual[first])
                        ++first;
                    std::printf("CODE mismatch page RVA=%08lX first RVA=%08lX expected=%02X actual=%02X\n",
                                static_cast<unsigned long>(rva), static_cast<unsigned long>(rva + first),
                                unsigned(expected[first]), unsigned(actual[first]));
                    std::fflush(stdout);
                }
                result = 1;
            }
        }
        if (result == 2)
            break;
    }
    std::fclose(file);
    std::printf("CODE comparison: sections=%u pages=%u mismatched-pages=%u result=%d\n",
                sections, pages, mismatches, result);
    std::fflush(stdout);
    return sections ? result : 2;
}
#endif
#endif
