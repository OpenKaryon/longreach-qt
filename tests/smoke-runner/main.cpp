// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// smoke-runner - runs every other app in this suite with --selftest, prints a
// summary and writes a log next to itself.
//
// Deliberately a real Qt application rather than a shell script: it is built
// and shipped exactly like the apps it drives, so the same runner works on
// Windows, Linux and macOS instead of only on the host that happens to have
// the right shell. It also means the runner itself is a smoke test of
// QProcess, QFile and friends on the target.
//
//   smoke-runner              run every app's --selftest, write smoke-report.txt
//   smoke-runner --gui        additionally launch the GUI apps for eyeballing
//   smoke-runner --timeout=N  per-app timeout in seconds (default 180)
//   smoke-runner --reverse    reverse selftest order to diagnose resource leaks
//   smoke-runner --only=APP   run just one named app from the suite
//   smoke-runner --only=APP --app-arg=OPTION  append a diagnostic child option
//
// Exit code: 0 if every app that exists passed, 1 otherwise. Apps missing from
// the directory are reported as SKIP, not failure - the suite is deliberately
// built per platform (gl-heavy needs OpenGL, widgets needs QtWinExtras), so a
// target legitimately ships a subset.
#include <QCoreApplication>
#include <QDateTime>
#include <QElapsedTimer>
// smoke-runner includes no check harness - it drives the other apps rather
// than running checks itself - so it asks for the cross-version spellings
// directly instead of getting them through smokecheck.h.
#include "../common/qtcompat.h"

#include <QDir>
// Explicit on Qt 4, where it does not arrive transitively the way it does
// through Qt 5's headers.
#include <QVector>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QProcessEnvironment>
// QRegularExpression is Qt 5; Qt 4's regex engine is QRegExp, which is
// enough for the one line this file matches. Qt 5 and Qt 6 still get the
// PCRE-backed class - the guard is not an excuse to use the old one
// everywhere.
#if QT_VERSION >= QT_VERSION_CHECK(5, 0, 0)
#  include <QRegularExpression>
#else
#  include <QRegExp>
#endif
#include <QStringList>
#include <QTextStream>

namespace {

// The apps this runner drives: tests/expected-apps.txt, which every Qt 4, 5
// and 6 target builds. Anything absent next to the runner is reported as not
// built. --reverse can diagnose order-dependent failures without changing the
// ordinary suite order.
const char *const kApps[] = {
    "qt-selftest",
    "widgets-gallery",
    "graphics-gallery",
    "quick-qml-gallery",
    "gl-heavy-gallery",
    "painting-lab",
    "multimedia-lab",
    "network-gui",
};

// GUI apps worth opening for manual inspection with --gui. qt-selftest is
// headless, so it is not in this list.
const char *const kGuiApps[] = {
    "widgets-gallery",
    "graphics-gallery",
    "quick-qml-gallery",
    "gl-heavy-gallery",
    "painting-lab",
    "multimedia-lab",
    "network-gui",
};

const char *const kDiagnosticsNote =
    "\n--- diagnostics note ---\n"
    "Pass/fail is determined by app exit status, crashes/timeouts and FAIL lines. "
    "Static Qt builds may still print expected plugin/backend/device warnings on "
    "minimal or legacy systems; compare noisy logs with docs/expected-smoke-warnings.md "
    "in the source tree.\n";

enum Outcome { Passed, Failed, Skipped };

struct Result {
    Result() : outcome(Skipped), exitCode(0) {}
    QString app;
    Outcome outcome;
    int exitCode;
    QString summary;    // the app's own "---- name: N passed ... ----" line
    QString note;       // why it was skipped, or how it failed
};

// A failure says both what crashed and the summary the app printed before it.
QString describeFailure(const Result &r)
{
    if (r.summary.isEmpty())
        return r.note;
    return QStringLiteral("%1  [%2]").arg(r.summary, r.note);
}

// Resolves an app name to a path in dir, accounting for the platform's
// executable suffix.
QString resolve(const QDir &dir, const QString &name)
{
    QStringList candidates;
    candidates << name << name + QStringLiteral(".exe");
#ifdef Q_OS_MAC
    candidates << name + QStringLiteral(".app/Contents/MacOS/") + name;
#endif
    for (int i = 0; i < candidates.size(); ++i) {
        const QString &c = candidates.at(i);
        const QFileInfo fi(dir.absoluteFilePath(c));
        if (fi.exists() && fi.isFile())
            return fi.absoluteFilePath();
    }
    return QString();
}

// Pulls the app's own summary line out of its output, so the report can show
// per-app counts rather than just an exit code.
QString extractSummary(const QString &output)
{
#if QT_VERSION >= QT_VERSION_CHECK(5, 0, 0)
    static const QRegularExpression re(QStringLiteral("^-+ .*passed.*-+$"),
                                       QRegularExpression::MultilineOption);
    const QRegularExpressionMatch m = re.match(output);
    return m.hasMatch() ? m.captured(0).trimmed() : QString();
#else
    // QRegExp has no multiline mode, so the search is per line instead of
    // one pass with ^ and $ anchored inside the string.
    QRegExp re(QString::fromLatin1("^-+ .*passed.*-+$"));
    const QStringList lines = output.split(QLatin1Char('\n'));
    for (int i = 0; i < lines.size(); ++i) {
        const QString line = lines.at(i).trimmed();
        if (re.exactMatch(line))
            return line;
    }
    return QString();
#endif
}

// Keep a short on-disk trail before starting each child. A legacy guest can
// crash before the final report is written, in which case this identifies the
// application being launched when the machine stopped responding.
void appendProgress(const QString &path, const QString &line)
{
    QFile file(path);
    if (file.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
        QTextStream stream(&file);
        stream << line << Qt::endl;
        file.flush();
    }
}

Result runOne(const QDir &dir, const QString &name, int timeoutMs, QString *fullLog,
              const QStringList &extraArguments)
{
    Result r;
    r.app = name;

    const QString exe = resolve(dir, name);
    if (exe.isEmpty()) {
        r.note = QStringLiteral("not built for this platform");
        return r;
    }

    QProcess proc;
    proc.setProcessChannelMode(QProcess::MergedChannels);
    proc.setWorkingDirectory(dir.absolutePath());
    // Keep each child's flushed output even if the guest fails before the
    // final combined report. A QProcess pipe alone leaves it in our memory.
    const QString childLogPath = dir.absoluteFilePath(
        QStringLiteral("smoke-%1.log").arg(name));
    proc.setStandardOutputFile(childLogPath, QIODevice::Truncate);
#if defined(Q_OS_LINUX) && QT_VERSION_MAJOR >= 6
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    // These two applications intentionally exercise native GL/Vulkan paths.
    // The rest of the suite remains on the caller's offscreen platform: some
    // static widget/Quick teardown paths are not stable under Xvfb, while the
    // backend checks cannot create a platform Vulkan instance offscreen.
    if (env.contains(QStringLiteral("DISPLAY"))
            && (name == QStringLiteral("qt-selftest")
                || name == QStringLiteral("gl-heavy-gallery")))
        env.insert(QStringLiteral("QT_QPA_PLATFORM"), QStringLiteral("xcb"));
    proc.setProcessEnvironment(env);
#endif
    const QStringList childArguments = QStringList() << QStringLiteral("--selftest") << extraArguments;
    QElapsedTimer elapsed;
    elapsed.start();
    proc.start(exe, childArguments);

    if (!proc.waitForStarted(30000)) {
        r.outcome = Failed;
        r.note = QStringLiteral("failed to start: %1").arg(proc.errorString());
        fullLog->append(QStringLiteral("=== %1 === %2\n\n").arg(name, r.note));
        return r;
    }

    // Qt 4 returns false when waitForFinished() is called after the child has
    // already exited. Its actual exit status is checked below in either case.
    const bool finished = proc.state() == QProcess::NotRunning
            || proc.waitForFinished(timeoutMs);
    if (!finished) {
        // Preserve the wait failure before kill()/waitForFinished() can replace
        // QProcess's state and error with the cleanup result.
        const QProcess::ProcessState state = proc.state();
        const QProcess::ProcessError error = proc.error();
        const QString errorString = proc.errorString();
        const qint64 elapsedMs = elapsed.elapsed();
        r.outcome = Failed;
        r.note = error == QProcess::Timedout && state == QProcess::Running
                ? QStringLiteral("timed out after %1 s").arg(timeoutMs / 1000)
                : QStringLiteral("wait for completion failed");
        r.note += QStringLiteral("; state=%1 error=%2 (%3) elapsed-ms=%4")
                .arg(int(state)).arg(int(error)).arg(errorString).arg(elapsedMs);
        r.exitCode = proc.exitCode();
        if (state != QProcess::NotRunning) {
            proc.kill();
            proc.waitForFinished(5000);
        }
    }

    // Normalise line endings before anything looks at the text: on Windows the
    // children emit CRLF, and a stray \r before the newline is enough to stop
    // the summary regex below from matching at end-of-line.
    QFile childLog(childLogPath);
    QString output;
    if (childLog.open(QIODevice::ReadOnly))
        output = QString::fromLocal8Bit(childLog.readAll());
    else {
        r.outcome = Failed;
        if (!r.note.isEmpty())
            r.note += QStringLiteral("; ");
        r.note += QStringLiteral("cannot read child output: %1").arg(childLog.errorString());
    }
    output.replace(QLatin1String("\r\n"), QLatin1String("\n"));
    fullLog->append(QStringLiteral("=== %1 %2 ===\n%3\n")
                   .arg(name, childArguments.join(QLatin1String(" ")), output));

    r.summary = extractSummary(output);
    if (r.outcome == Failed)          // already decided by wait/output failure
        return r;

    r.exitCode = proc.exitCode();
    const bool crashed = proc.exitStatus() != QProcess::NormalExit;
    if (crashed) {
        r.outcome = Failed;
        // On Windows the "exit code" of a crashed process is the exception
        // code, so print it: 0xC0000005 is an access violation, 0xC0000374 a
        // corrupted heap, and so on. Worth the hex - it is often the whole
        // diagnosis, and it costs nothing to carry.
        r.note = QStringLiteral("crashed, exception 0x%1")
                     .arg(quint32(r.exitCode), 8, 16, QLatin1Char('0'));
    } else if (r.exitCode != 0) {
        r.outcome = Failed;
        r.note = QStringLiteral("exit code %1").arg(r.exitCode);
    } else {
        r.outcome = Passed;
    }
    return r;
}

} // namespace

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    const QStringList args = app.arguments();

    const bool launchGui = args.contains(QStringLiteral("--gui"));
    const bool reverseOrder = args.contains(QStringLiteral("--reverse"));
    int timeoutMs = 180000;
    QString onlyApp;
    QStringList extraArguments;
    for (int i = 0; i < args.size(); ++i) {
        const QString &a = args.at(i);
        if (a.startsWith(QStringLiteral("--app-arg=")))
            extraArguments.append(a.mid(10));
        if (a.startsWith(QStringLiteral("--only="))) {
            onlyApp = a.mid(7);
            bool known = false;
            for (unsigned int j = 0; j < sizeof(kApps) / sizeof(kApps[0]); ++j)
                known = known || onlyApp == QString::fromLatin1(kApps[j]);
            if (!known) {
                QTextStream error(stderr);
                error << "--only requires a known suite application name" << Qt::endl;
                return 2;
            }
        }
        if (a.startsWith(QStringLiteral("--timeout="))) {
            bool ok = false;
            const int secs = a.section(QLatin1Char('='), 1).toInt(&ok);
            if (ok && secs > 0)
                timeoutMs = secs * 1000;
        }
    }

    // Diagnostic child options must never silently change an entire suite run.
    if (!extraArguments.isEmpty() && onlyApp.isEmpty()) {
        QTextStream error(stderr);
        error << "--app-arg requires --only=APP" << Qt::endl;
        return 2;
    }

    QDir dir(QCoreApplication::applicationDirPath());
#ifdef Q_OS_MAC
    // Finder launches the runner from inside its bundle; siblings are beside it.
    if (dir.dirName() == QStringLiteral("MacOS")
            && QFileInfo(dir.absoluteFilePath(QStringLiteral("../Info.plist"))).exists()) {
        dir.cdUp();
        dir.cdUp();
        dir.cdUp();
    }
#endif
    QTextStream out(stdout);

    QString fullLog;
    fullLog += QStringLiteral("qt smoke run - %1\ndirectory: %2\n\n")
                   .arg(QDateTime::currentDateTime().toString(Qt::ISODate),
                        dir.absolutePath());
    const QString logPath = dir.absoluteFilePath(QStringLiteral("smoke-report.txt"));
    {
        QFile logFile(logPath);
        if (logFile.open(QIODevice::WriteOnly | QIODevice::Text)) {
            QTextStream stream(&logFile);
            stream << fullLog << Qt::flush;
        }
    }

    QVector<Result> results;
    const unsigned int appCount = sizeof(kApps) / sizeof(kApps[0]);
    for (unsigned int i = 0; i < appCount; ++i) {
        const char *name = kApps[reverseOrder ? appCount - 1 - i : i];
        const QString appName = QString::fromLatin1(name);
        if (!onlyApp.isEmpty() && appName != onlyApp)
            continue;
        out << "running " << appName << " --selftest ..." << Qt::endl;
        appendProgress(logPath, QStringLiteral("starting %1 --selftest").arg(appName));
        const int transcriptStart = fullLog.size();
        const Result r = runOne(dir, appName, timeoutMs, &fullLog, extraArguments);
        results.append(r);
        if (fullLog.size() > transcriptStart)
            appendProgress(logPath, fullLog.mid(transcriptStart));
        appendProgress(logPath, QStringLiteral("finished %1: %2")
                       .arg(appName, QString::fromLatin1(r.outcome == Passed ? "PASS"
                                                          : r.outcome == Failed ? "FAIL" : "SKIP")));
        if (r.outcome == Failed)
            appendProgress(logPath, describeFailure(r));
        if (r.outcome == Skipped)
            out << "  SKIP  (" << r.note << ")" << Qt::endl;
        else if (r.outcome == Failed)
            out << "  FAIL  " << describeFailure(r) << Qt::endl;
        else
            out << "  ok    " << r.summary << Qt::endl;
    }

    int passed = 0, failed = 0, skipped = 0;
    QString table = QStringLiteral("\n--- summary ---\n");
    for (int i = 0; i < results.size(); ++i) {
        const Result &r = results.at(i);
        const char *tag = r.outcome == Passed ? "PASS"
                        : r.outcome == Failed ? "FAIL" : "SKIP";
        const QString detail = r.outcome == Failed ? describeFailure(r)
                             : r.summary.isEmpty() ? r.note : r.summary;
        table += QStringLiteral("%1  %2  %3\n")
                     .arg(QString::fromLatin1(tag), -4)
                     .arg(r.app, -20)
                     .arg(detail);
        if (r.outcome == Passed) ++passed;
        else if (r.outcome == Failed) ++failed;
        else ++skipped;
    }
    table += QStringLiteral("\n%1 passed, %2 failed, %3 not built for this platform\n")
                 .arg(passed).arg(failed).arg(skipped);
    table += QString::fromLatin1(kDiagnosticsNote);

    out << table << Qt::flush;
    fullLog += table;

    QFile logFile(logPath);
    if (logFile.open(QIODevice::WriteOnly | QIODevice::Text)) {
        QTextStream ts(&logFile);
        ts << fullLog;
        logFile.close();
        out << "report written to " << logPath << Qt::endl;
    } else {
        out << "WARNING: could not write " << logPath << ": "
            << logFile.errorString() << Qt::endl;
    }

    if (launchGui) {
        out << "\nlaunching GUI apps for manual inspection ..." << Qt::endl;
        for (unsigned int i = 0; i < sizeof(kGuiApps) / sizeof(kGuiApps[0]); ++i) {
            const char *name = kGuiApps[i];
            if (!onlyApp.isEmpty() && QString::fromLatin1(name) != onlyApp)
                continue;
            const QString exe = resolve(dir, QString::fromLatin1(name));
            if (exe.isEmpty())
                continue;
            if (QProcess::startDetached(exe, QStringList()))
                out << "  opened " << name << Qt::endl;
            else
                out << "  could not open " << name << Qt::endl;
        }
        out << "close the windows after inspecting them." << Qt::endl;
    }

    return failed == 0 ? 0 : 1;
}
