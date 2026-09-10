// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Tee everything the app says into a log file beside the executable.
//
// Written because the interesting output from these test apps is what the GL
// driver says - shader compile and link logs, Qt's own warnings, the lifecycle
// tracing in the galleries - and on the machines that produce the interesting
// output there is no terminal to scroll back through. A Windows GUI build has
// no console at all unless one was inherited, and where there is one, the
// console buffer holds a few hundred lines of a driver that emits thousands.
// Reading the result off a photograph of the screen is not a way to work.
//
// Installed before QCoreApplication exists, so it needs argv[0] rather than
// QCoreApplication::applicationDirPath() to decide where the file goes. Every
// message is flushed as it arrives: the failures this exists for tend to end in
// a crash, and a buffered log of a crash is an empty log.
//
// The previous handler is kept and still called, so a console or a debugger
// attached to the process sees what it saw before.
#ifndef FILELOG_H
#define FILELOG_H

#include <QByteArray>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QString>
#include <QTextStream>
#include <QtGlobal>

namespace SmokeFileLog {

inline QFile *logFile()
{
    static QFile file;
    return &file;
}

inline QtMessageHandler *previousHandler()
{
    static QtMessageHandler handler = 0;
    return &handler;
}

inline const char *levelName(QtMsgType type)
{
    switch (type) {
    case QtDebugMsg:    return "debug";
    case QtInfoMsg:     return "info";
    case QtWarningMsg:  return "warning";
    case QtCriticalMsg: return "critical";
    case QtFatalMsg:    return "fatal";
    }
    return "?";
}

inline void handler(QtMsgType type, const QMessageLogContext &context, const QString &msg)
{
    QFile *file = logFile();
    if (file->isOpen()) {
        QTextStream out(file);
        out << QDateTime::currentDateTime().toString(QStringLiteral("hh:mm:ss.zzz"))
            << ' ' << levelName(type) << ": " << msg << '\n';
        out.flush();
        file->flush();
    }

    if (*previousHandler())
        (*previousHandler())(type, context, msg);
}

// Call from main() before constructing the application, passing argv[0].
// Returns the path written to, or an empty string if the file could not be
// opened - in which case nothing is installed and output carries on as before.
inline QString install(const char *argv0, const QString &name)
{
    const QString dir = QFileInfo(QFile::decodeName(argv0)).absolutePath();
    const QString path = QDir(dir).filePath(name);

    QFile *file = logFile();
    file->setFileName(path);
    if (!file->open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text))
        return QString();

    QTextStream out(file);
    out << "# " << name << " - written by " << QFile::decodeName(argv0) << '\n'
        << "# started " << QDateTime::currentDateTime().toString(Qt::ISODate)
        << ", Qt " QT_VERSION_STR "\n\n";
    out.flush();
    file->flush();

    *previousHandler() = qInstallMessageHandler(handler);
    return path;
}

} // namespace SmokeFileLog

#endif // FILELOG_H
