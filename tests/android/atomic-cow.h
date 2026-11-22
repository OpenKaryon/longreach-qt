// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
#ifndef LONGREACH_ANDROID_ATOMIC_COW_H
#define LONGREACH_ANDROID_ATOMIC_COW_H

#if defined(LONGREACH_ANDROID_APK) && defined(__i386__) && SMOKE_QT5
#include <QAtomicInt>
#include <atomic>
#include <cerrno>
#include <cstring>
#include <new>
#include <sys/mman.h>
#include <sys/wait.h>
#include <unistd.h>

namespace SmokeAndroidAtomicCow {
enum Kind { QtAtomic, StdAtomic, BuiltinAtomic };

// A separate mapping keeps unrelated parent writes from resolving COW first.
// Failed CMPXCHG must preserve zero even when its no-op write faults after fork.
inline bool compare(Kind kind, void *page, int &observed)
{
    observed = 1;
    if (kind == QtAtomic)
        return static_cast<QAtomicInt *>(page)->testAndSetAcquire(1, 2, observed);
    if (kind == StdAtomic)
        return static_cast<std::atomic<int> *>(page)->compare_exchange_strong(
                observed, 2, std::memory_order_acquire, std::memory_order_acquire);
    return __atomic_compare_exchange_n(static_cast<int *>(page), &observed, 2,
                                      false, __ATOMIC_ACQUIRE, __ATOMIC_ACQUIRE);
}

inline int value(Kind kind, void *page)
{
    if (kind == QtAtomic)
        return static_cast<QAtomicInt *>(page)->loadAcquire();
    if (kind == StdAtomic)
        return static_cast<std::atomic<int> *>(page)->load(std::memory_order_acquire);
    return __atomic_load_n(static_cast<int *>(page), __ATOMIC_ACQUIRE);
}

inline bool check(Kind kind, QString &detail)
{
    const long pageSize = sysconf(_SC_PAGESIZE);
    if (pageSize <= 0) { detail = "cannot read page size"; return false; }
    for (int round = 0; round < 10; ++round) {
        void *page = mmap(nullptr, size_t(pageSize), PROT_READ | PROT_WRITE,
                          MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (page == MAP_FAILED) { detail = "mmap failed"; return false; }
        if (kind == QtAtomic) new (page) QAtomicInt(0);
        else if (kind == StdAtomic) new (page) std::atomic<int>(0);
        else new (page) int(0);
        int observed;
        const bool before = compare(kind, page, observed);
        const bool baseline = !before && observed == 0 && value(kind, page) == 0;
        const pid_t child = baseline ? fork() : -1;
        if (child == 0) _exit(0);
        int status = 0;
        pid_t waited = -1;
        if (child > 0) {
            do { waited = waitpid(child, &status, 0); } while (waited < 0 && errno == EINTR);
        }
        const bool reaped = child > 0 && waited == child && WIFEXITED(status)
                && WEXITSTATUS(status) == 0;
        const bool exchanged = reaped && compare(kind, page, observed);
        const int after = value(kind, page);
        const bool ok = baseline && reaped && !exchanged && observed == 0 && after == 0;
        // All three mapped types are trivially destructible.
        munmap(page, size_t(pageSize));
        if (!ok) {
            detail = QStringLiteral("round=%1 baseline=%2 child=%3 exchanged=%4 observed=%5 value=%6")
                    .arg(round).arg(baseline).arg(reaped).arg(exchanged).arg(observed).arg(after);
            return false;
        }
    }
    return true;
}

inline bool requested(int argc, char **argv)
{
    for (int i = 1; i < argc; ++i)
        if (std::strcmp(argv[i], "--atomic-cow") == 0) return true;
    return false;
}

inline int run()
{
    SmokeReporter reporter("android-atomic-cow");
    reporter.check("sync/atomic-cow-qt", [](QString &d) { return check(QtAtomic, d); });
    reporter.check("sync/atomic-cow-std", [](QString &d) { return check(StdAtomic, d); });
    reporter.check("sync/atomic-cow-builtin", [](QString &d) { return check(BuiltinAtomic, d); });
    return reporter.summary();
}
}
#endif
#endif
