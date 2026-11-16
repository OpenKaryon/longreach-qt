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
