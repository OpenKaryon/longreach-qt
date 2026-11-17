# SPDX-License-Identifier: GPL-3.0-or-later

from pathlib import Path
import sys


def edit(name, replacements):
    path = Path(name)
    original = path.read_text(encoding="latin1")
    updated = original
    for old, new in replacements:
        if new in updated:
            continue
        if updated.count(old) != 1:
            raise RuntimeError(f"unexpected text in {path}: {old!r}")
        updated = updated.replace(old, new)
    if updated != original:
        path.write_text(updated, encoding="latin1")


def guard(body):
    return body, f"#ifndef __ANDROID__\n{body}#endif\n"


edit("src/corelib/thread/qthread_unix.cpp", (
    guard("    pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, NULL);\n"),
    guard("    pthread_setcancelstate(PTHREAD_CANCEL_ENABLE, NULL);\n    pthread_testcancel();\n"),
    (
        "    if (code == EPERM) {\n"
        "        // caller does not have permission to set the scheduling\n"
        "        // parameters/policy\n"
        "        pthread_attr_setinheritsched(&attr, PTHREAD_INHERIT_SCHED);\n"
        "        code =\n            pthread_create(&d->thread_id, &attr, QThreadPrivate::start, this);\n    }\n",
        "#if defined(QT_HAS_THREAD_PRIORITY_SCHEDULING)\n"
        "    if (code == EPERM) {\n"
        "        // caller does not have permission to set the scheduling\n"
        "        // parameters/policy\n"
        "        pthread_attr_setinheritsched(&attr, PTHREAD_INHERIT_SCHED);\n"
        "        code =\n            pthread_create(&d->thread_id, &attr, QThreadPrivate::start, this);\n    }\n#endif\n",
    ),
    (
        "    int code = pthread_cancel(d->thread_id);\n",
        "#ifdef __ANDROID__\n"
        '    qWarning("QThread::terminate: Android does not support thread cancellation");\n'
        "#else\n    int code = pthread_cancel(d->thread_id);\n",
    ),
    ("        d->terminated = true;\n    }\n}\n\nbool QThread::wait", "        d->terminated = true;\n    }\n#endif\n}\n\nbool QThread::wait"),
    (
        "    pthread_setcancelstate(enabled ? PTHREAD_CANCEL_ENABLE : PTHREAD_CANCEL_DISABLE, NULL);\n"
        "    if (enabled)\n        pthread_testcancel();\n",
        "#ifdef __ANDROID__\n    Q_UNUSED(enabled)\n#else\n"
        "    pthread_setcancelstate(enabled ? PTHREAD_CANCEL_ENABLE : PTHREAD_CANCEL_DISABLE, NULL);\n"
        "    if (enabled)\n        pthread_testcancel();\n#endif\n",
    ),
))

edit("src/corelib/codecs/qtextcodec.cpp", (
    (
        "#if defined (_XOPEN_UNIX) && !defined(Q_OS_QNX) && !defined(Q_OS_OSF)\n#include <langinfo.h>",
        "#if defined (_XOPEN_UNIX) && !defined(Q_OS_QNX) && !defined(Q_OS_OSF) && !defined(__ANDROID__)\n"
        "#include <langinfo.h>",
    ),
    (
        '    localeMapper = QTextCodec::codecForName("System");\n#else\n\n#ifndef QT_NO_ICONV',
        '    localeMapper = QTextCodec::codecForName("System");\n'
        '#elif defined(__ANDROID__)\n    localeMapper = QTextCodec::codecForName("UTF-8");\n'
        '#else\n\n#ifndef QT_NO_ICONV',
    ),
))

if sys.argv[1:] == ["quick"]:
    edit("src/gui/kernel/qwidget.cpp", (
        ("void QWidgetPrivate::setStyle_helper(QStyle *newStyle, bool propagate, bool",
         "#ifndef QT_NO_STYLE_STYLESHEET\n"
         "// Keep the weak-pointer null check across synchronous style events with Clang.\n"
         "__attribute__((noinline)) static QStyle *donutStylePointer(const QWeakPointer<QStyle> &style)\n"
         "{\n    return style.data();\n}\n"
         "#endif\n\n"
         "void QWidgetPrivate::setStyle_helper(QStyle *newStyle, bool propagate, bool"),
        ("if (QStyleSheetStyle *proxy = qobject_cast<QStyleSheetStyle *>(origStyle.data()))\n"
         "        proxy->deref();",
         "if (QStyleSheetStyle *proxy = qobject_cast<QStyleSheetStyle *>(donutStylePointer(origStyle)))\n"
         "        proxy->deref();"),
    ))
    edit("src/plugins/platforms/minimal/minimal.pro", (
        ("INSTALLS += target",
         "INSTALLS += target\n\ninclude(../fontdatabases/basicunix/basicunix.pri)"),
    ))
    edit("src/plugins/platforms/minimal/qminimalintegration.h", (
        ("#include <QtGui/QPlatformScreen>",
         "#include <QtGui/QPlatformScreen>\n#include \"qbasicunixfontdatabase.h\""),
        ("private:\n    QList<QPlatformScreen *> mScreens;",
         "    QPlatformFontDatabase *fontDatabase() const { return &mFontDatabase; }\n\n"
         "private:\n    mutable QBasicUnixFontDatabase mFontDatabase;\n"
         "    QList<QPlatformScreen *> mScreens;"),
    ))
    edit("src/3rdparty/sqlite/sqlite3.c", (
        ("#if !defined(fdatasync) && !defined(__linux__)",
         "#if !defined(fdatasync) && (!defined(__linux__) || defined(__ANDROID__))"),
    ))
    edit("src/network/kernel/qhostinfo_unix.cpp", (
        ("QString QHostInfo::localDomainName()\n{\n#if !defined(Q_OS_VXWORKS)",
         "QString QHostInfo::localDomainName()\n{\n#if !defined(Q_OS_VXWORKS) && !defined(__ANDROID__)"),
    ))
    edit("src/network/kernel/qnetworkinterface_unix.cpp", (
        ("    QSet<QByteArray> result;\n#ifdef QT_NO_IPV6IFNAME",
         "    QSet<QByteArray> result;\n#if defined(QT_NO_IPV6IFNAME) || defined(__ANDROID__)"),
    ))
    edit("src/3rdparty/libtiff/libtiff/tif_config.h", (
        ("!defined(Q_OS_VXWORKS) && !defined(Q_OS_ANDROID)\n#define HAVE_SEARCH_H 1",
         "!defined(Q_OS_VXWORKS) && !defined(Q_OS_ANDROID) && !defined(__ANDROID__)\n#define HAVE_SEARCH_H 1"),
    ))
    date = Path("src/3rdparty/javascriptcore/JavaScriptCore/runtime/DatePrototype.cpp")
    original = date.read_text(encoding="latin1")
    updated = original.replace("#if !PLATFORM(MAC) && HAVE(LANGINFO_H)\n",
                               "#if !PLATFORM(MAC) && HAVE(LANGINFO_H) && !defined(__ANDROID__)\n")
    updated = updated.replace("#if HAVE(LANGINFO_H)\n", "#if HAVE(LANGINFO_H) && !defined(__ANDROID__)\n")
    marker = "#elif (OS(WINCE) && !PLATFORM(QT)) || OS(SYMBIAN)"
    android = ('#elif defined(__ANDROID__)\n'
               '    static const char* const formatStrings[] = { "%a %b %d %Y %H:%M:%S", "%m/%d/%Y", "%H:%M:%S" };\n')
    if android not in updated:
        assert updated.count(marker) == 1
        updated = updated.replace(marker, android + marker)
    if updated != original:
        date.write_text(updated, encoding="latin1")
