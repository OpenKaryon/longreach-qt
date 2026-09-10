// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Shared PASS/FAIL harness for the qt-smoke suite.
//
// Every check prints one line:   PASS: <name>        or   FAIL: <name> - <why>
// At the end SmokeReporter::summary() prints a totals line and returns an exit
// code (0 = all passed). This format is identical for the console app and the
// --selftest mode of the GUI apps, so results are diff-able across OSes
// (Windows XP / 11, Linux, ...).
#ifndef SMOKECHECK_H
#define SMOKECHECK_H

#include <QString>
#include <QStringList>
#include <QtGlobal>
#include <cstdio>
#include <functional>
#include <QFile>

// Every app includes this header, so the cross-version spellings ride along
// with it and no check has to remember to ask for them.
#include "qtcompat.h"

class SmokeReporter
{
public:
    explicit SmokeReporter(const QString &suite) : m_suite(suite) {}
    ~SmokeReporter() { if (m_log) std::fclose(m_log); }
    SmokeReporter(const SmokeReporter &) = delete;
    SmokeReporter &operator=(const SmokeReporter &) = delete;

    // Preserve flushed progress even if the guest OS crashes before a parent
    // QProcess can drain stdout. Enabled explicitly by the app under diagnosis.
    bool setLogFile(const QString &path)
    {
        if (m_log) std::fclose(m_log);
        m_log = std::fopen(QFile::encodeName(path).constData(), "w");
        return m_log != nullptr;
    }

    // Run one named check. The functor returns true on success, or throws /
    // returns false on failure. `detail` (set via fail()) explains a failure.
    void check(const QString &name, const std::function<bool(QString &)> &fn)
    {
        QString detail;
        bool ok = false;
        m_currentSkipped = false;
        if (m_trace) {
            std::printf("RUN: %s\n", qPrintable(name));
            std::fflush(stdout);
            if (m_log) { std::fprintf(m_log, "RUN: %s\n", qPrintable(name)); std::fflush(m_log); }
        }
        // A check reports failure by returning false and filling `detail`.
        ok = fn(detail);
        if (m_currentSkipped) {
            ++m_skipped;
            std::printf("SKIP: %s - %s\n", qPrintable(name), qPrintable(detail));
            if (m_log) std::fprintf(m_log, "SKIP: %s - %s\n", qPrintable(name), qPrintable(detail));
        } else if (ok) {
            ++m_passed;
            std::printf("PASS: %s\n", qPrintable(name));
            if (m_log) std::fprintf(m_log, "PASS: %s\n", qPrintable(name));
        } else {
            ++m_failed;
            m_failedNames << name;
            std::printf("FAIL: %s - %s\n", qPrintable(name),
                        detail.isEmpty() ? "check returned false" : qPrintable(detail));
            if (m_log) std::fprintf(m_log, "FAIL: %s - %s\n", qPrintable(name),
                        detail.isEmpty() ? "check returned false" : qPrintable(detail));
        }
        std::fflush(stdout);
        if (m_log) std::fflush(m_log);
    }

    // Call inside a check to mark it not-applicable on this platform/config.
    void skip(QString &detail, const QString &why) { m_currentSkipped = true; detail = why; }

    int summary()
    {
        std::printf("---- %s: %d passed, %d failed, %d skipped ----\n",
                    qPrintable(m_suite), m_passed, m_failed, m_skipped);
        if (m_failed) std::printf("FAILED: %s\n", qPrintable(m_failedNames.join(", ")));
        std::fflush(stdout);
        if (m_log) {
            std::fprintf(m_log, "---- %s: %d passed, %d failed, %d skipped ----\n",
                         qPrintable(m_suite), m_passed, m_failed, m_skipped);
            std::fflush(m_log);
        }
        return m_failed == 0 ? 0 : 1;
    }

    int failed() const { return m_failed; }
    void setTrace(bool enabled) { m_trace = enabled; }

private:
    QString m_suite;
    int m_passed = 0, m_failed = 0, m_skipped = 0;
    bool m_currentSkipped = false;
    bool m_trace = false;
    QStringList m_failedNames;
    FILE *m_log = nullptr;
};

#endif // SMOKECHECK_H
