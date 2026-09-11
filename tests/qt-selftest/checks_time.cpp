// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Date/time, timezone, locale, collation, easing curves. Headless.
#include "../common/smokecheck.h"
#include "checks.h"

#include <QDate>
#include <QTime>
#include <QDateTime>
#if SMOKE_QT5
#include <QTimeZone>
#endif
#include <QLocale>
#if SMOKE_QT5
#include <QCollator>
#endif
#include <QElapsedTimer>
#if SMOKE_QT5
#include <QDeadlineTimer>
#endif
#include <QEasingCurve>
#include <QThread>
#include <QSysInfo>
#if SMOKE_QT5
#include <QOperatingSystemVersion>
#endif

namespace {

bool isWindowsXpFamily()
{
#ifdef Q_OS_WIN
#if SMOKE_QT5
    const QOperatingSystemVersion current = QOperatingSystemVersion::current();
    return current.type() == QOperatingSystemVersion::Windows && current.majorVersion() <= 5;
#else
    return QSysInfo::windowsVersion() <= QSysInfo::WV_2003;
#endif
#else
    return false;
#endif
}

} // namespace

void checkTime(SmokeReporter &r)
{
    r.check("time/date", [&r](QString &d) {
        QDate dt(2026,7,24);
        if (!dt.isValid()) { d="invalid"; return false; }
        return dt.dayOfWeek()==5 && dt.addMonths(1).month()==8 && dt.daysInMonth()==31;
    });
    r.check("time/time", [&r](QString &d) {
        QTime t(10,30,15);
        return t.addSecs(45).toString("hh:mm:ss")=="10:31:00";
    });
    r.check("time/datetime-iso", [&r](QString &d) {
        QDateTime dt = QDateTime::fromString("2026-07-24T10:00:00", Qt::ISODate);
        if (!dt.isValid()) { d="parse"; return false; }
        return dt.addDays(7).date().day()==31 && dt.toString(Qt::ISODate).startsWith("2026-07-24");
    });
    r.check("time/timezone", [&r](QString &d) {
#if SMOKE_QT5
        QTimeZone utc("UTC");
        if (!utc.isValid()) { r.skip(d,"no tz data"); return false; }
        QTimeZone tz("Europe/Moscow");
        if (!tz.isValid()) { r.skip(d,"tz db missing"); return false; }
        QDateTime dt(QDate(2026,1,1), QTime(12,0), tz);
        return dt.timeZone().isValid() && utc.offsetFromUtc(dt)==0;
#else
        r.skip(d, QStringLiteral("QTimeZone arrived in Qt 5"));
        return false;
#endif
    });
    r.check("time/elapsedtimer", [&r](QString &d) {
        QElapsedTimer t; t.start();
#if SMOKE_QT5
        // Sleep() may return up to one system tick early when the wait is
        // shorter than the tick (15.6 ms on XP): a 5 ms sleep measured 3 ms
        // there. Wait longer and allow one tick of early return.
        QThread::msleep(50);
        const qint64 minimum = 30;
#else
        while (t.elapsed() < 5) {}
        const qint64 minimum = 4;
#endif
        const qint64 ms = t.elapsed();
        d = QString::number(ms) + QLatin1String(" ms measured");
        return ms >= minimum && !t.hasExpired(1000000);
    });
    r.check("time/deadlinetimer", [&r](QString &d) {
#if SMOKE_QT5
        QDeadlineTimer dl(50);
        return dl.remainingTime()>0 && !dl.hasExpired();
#else
        r.skip(d, QStringLiteral("QDeadlineTimer arrived in Qt 5"));
        return false;
#endif
    });
    r.check("locale/format-number", [&r](QString &d) {
        QLocale de(QLocale::German), en(QLocale::English);
        QString dn = de.toString(1234.5, 'f', 1);
        QString enum_ = en.toString(1234.5, 'f', 1);
        return dn.contains(",") && enum_.contains(".");
    });
    r.check("locale/date-parse", [&r](QString &d) {
        QLocale c(QLocale::C);
        QDate dt = c.toDate("2026-07-24", "yyyy-MM-dd");
        return dt.isValid() && dt.year()==2026;
    });
    r.check("collator/sort", [&](QString &d) {
#if SMOKE_QT5
        // Braces, not parentheses: QCollator col(QLocale(QLocale::English))
        // is a most vexing parse, and clang rejects it outright where gcc let
        // it through ("parameter declarator cannot be qualified").
        QCollator col{QLocale(QLocale::English)};
        col.setNumericMode(true);
        // Numeric collation comes from the backend: the kit builds -no-icu, and the
        // posix fallback on Linux ignores setNumericMode(). (QT_CONFIG(icu) is not
        // public, hence the platform guard.)
#if defined(Q_OS_WIN) || defined(Q_OS_MACOS)
        // On Windows it needs SORT_DIGITSASNUMBERS, which XP rejects.
        if (isWindowsXpFamily()) {
            r.skip(d, QStringLiteral("numeric collation needs SORT_DIGITSASNUMBERS, which is Vista+"));
            return false;
        }
        // numeric-aware: "item2" < "item10"
        return col.compare("item2","item10") < 0;
#else
        r.skip(d, QStringLiteral("numeric collation needs ICU; this kit builds -no-icu"));
        return false;
#endif
#else
        r.skip(d, QStringLiteral("QCollator arrived in Qt 5"));
        return false;
#endif
    });
    r.check("easingcurve", [&r](QString &d) {
        QEasingCurve e(QEasingCurve::InOutQuad);
        double mid = e.valueForProgress(0.5);
        return e.valueForProgress(0.0)==0.0 && e.valueForProgress(1.0)==1.0 && mid>0.4 && mid<0.6;
    });
}
