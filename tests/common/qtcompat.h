// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// What the three Qt generations spell differently, in one place.
//
// The suite is one source tree serving Qt 4.8.7, Qt 5.15 and Qt 6.8, and most
// of it needs no help: the QtCore/QtGui/QtWidgets core is remarkably stable.
// What differs falls into three kinds, and only the first belongs in a header
// like this one:
//
//   1. spellings - a name that exists in every version under different words,
//      or a convenience that arrived later and can be written by hand. Those
//      are aliased here, once, so no check has to carry an #if for them.
//   2. behaviour - a class that exists everywhere but answers differently.
//      Those belong in the check, guarded, because the guard *is* the point
//      being made.
//   3. absence - a module or class that simply is not there. Those are handled
//      by smoke_require_modules() in CMake, or by a SMOKE_HAVE_ define, so a
//      check reports SKIP under its own name instead of vanishing.
//
// SMOKE_QT5 below is the test to write when something needs kind 2. Prefer it
// over QT_VERSION_MAJOR, which Qt 4 does not define at all - an `#if
// QT_VERSION_MAJOR < 6` there evaluates an undefined identifier as 0 and
// happens to give the right answer, which is exactly the kind of accident that
// stops being right later.

#ifndef SMOKE_QTCOMPAT_H
#define SMOKE_QTCOMPAT_H

#include <QtGlobal>
#include <QString>

// True on Qt 5 and Qt 6, false on Qt 4. Most of what this suite has to guard is
// "did this arrive with Qt 5", not "which of the three is this".
#if QT_VERSION >= QT_VERSION_CHECK(5, 0, 0)
#  define SMOKE_QT5 1
#else
#  define SMOKE_QT5 0
#endif

// The stream manipulators moved into the Qt namespace in 5.14; pulling the
// global ones in lets every call site say Qt::endl on all three versions.
#if QT_VERSION < QT_VERSION_CHECK(5, 14, 0) && !defined(Q_MOC_RUN)
#  include <QTextStream>
namespace Qt {
using ::endl;
using ::flush;
using ::bin;
using ::dec;
using ::hex;
}
#endif

#if !SMOKE_QT5

// QStringLiteral arrived in Qt 5; the fallback builds the same QString at run
// time (sizeof - 1, as the argument is always a literal).
#  ifndef QStringLiteral
#    define QStringLiteral(str) QString::fromUtf8("" str "", sizeof(str) - 1)
#  endif

// QStringView, QLatin1StringView and friends are Qt 5.10+/6 spellings with no
// Qt 4 equivalent worth faking - a check that wants one should guard on
// SMOKE_QT5 and say so, rather than get a silent substitute here.

#endif // !SMOKE_QT5

#endif // SMOKE_QTCOMPAT_H
