// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// QtCore probe for the Mac OS X 10.2 Jaguar port (milestone 2). Each check
// prints PASS or FAIL with a detail; the exit status is the failure count.
#include <QtCore/QCoreApplication>
#include <QtCore/QDateTime>
#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QLocale>
#include <QtCore/QProcess>
#include <QtCore/QSettings>
#include <QtCore/QStringList>
#include <QtCore/QSysInfo>
#include <QtCore/QTextCodec>
#include <QtCore/QTextStream>
#include <QtCore/QThread>
#include <QtCore/QTimer>
#include <cstdio>

static int failures = 0;

static void report(const char *name, bool ok, const QString &detail = QString())
{
    if (!ok)
        ++failures;
    std::printf("%s: %s%s%s\n", ok ? "PASS" : "FAIL", name,
                detail.isEmpty() ? "" : " - ", detail.toLocal8Bit().constData());
    std::fflush(stdout);
}

class Worker : public QThread
{
public:
    int result;
    Worker() : result(0) {}
    void run() { for (int i = 1; i <= 100; ++i) result += i; }
};

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    report("sysinfo", true, QString::fromLatin1("MacintoshVersion=0x%1")
           .arg(int(QSysInfo::MacintoshVersion), 0, 16));

    const QLocale system = QLocale::system();
    report("locale/system-name", !system.name().isEmpty(), system.name());
    const QString number = system.toString(1234567.25, 'f', 2);
    report("locale/number", number.contains(QLatin1String("1")), number);
    const QString date = system.toString(QDate(2026, 10, 5), QLocale::LongFormat);
    report("locale/long-date", !date.isEmpty(), date);
    const QString month = system.monthName(10);
    report("locale/month-name", !month.isEmpty(), month);

    const QString dirPath = QDir::tempPath() + QLatin1String("/qtkit-jaguar-probe");
    QDir().mkpath(dirPath);
    QFile file(dirPath + QLatin1String("/probe.txt"));
    bool fileOk = file.open(QIODevice::WriteOnly) && file.write("jaguar\n") == 7;
    file.close();
    fileOk = fileOk && file.open(QIODevice::ReadOnly) && file.readAll() == "jaguar\n";
    file.close();
    report("io/file-roundtrip", fileOk, file.fileName());

    QFile hidden(dirPath + QLatin1String("/.hidden"));
    hidden.open(QIODevice::WriteOnly);
    hidden.close();
    report("io/hidden-dotfile", QFileInfo(hidden.fileName()).isHidden());

    report("io/bundle-app", QFileInfo(QLatin1String("/Applications/TextEdit.app")).isBundle(),
           QLatin1String("/Applications/TextEdit.app"));
    report("io/plain-directory-not-bundle", !QFileInfo(dirPath).isBundle());
    report("io/dir-list", QDir(QLatin1String("/System/Library")).entryList().size() > 3);

    QSettings settings(dirPath + QLatin1String("/probe.ini"), QSettings::IniFormat);
    settings.setValue(QLatin1String("group/key"), 42);
    settings.sync();
    report("settings/ini", QSettings(dirPath + QLatin1String("/probe.ini"), QSettings::IniFormat)
           .value(QLatin1String("group/key")).toInt() == 42);

    Worker worker;
    worker.start();
    report("thread/run-join", worker.wait(5000) && worker.result == 5050);

    QTimer::singleShot(50, &app, SLOT(quit()));
    QTime clock;
    clock.start();
    app.exec();
    report("eventloop/timer", clock.elapsed() >= 40, QString::number(clock.elapsed()) + QLatin1String(" ms"));

    QProcess process;
    process.start(QLatin1String("/bin/echo"), QStringList() << QLatin1String("jaguar"));
    const bool processOk = process.waitForFinished(5000) && process.readAll().trimmed() == "jaguar";
    report("process/echo", processOk);

    QTextCodec *codec = QTextCodec::codecForName("ISO-8859-5");
    report("codec/iso-8859-5", codec && codec->toUnicode("\xd0\xd4").length() == 2);
    report("datetime/utc", QDateTime::currentDateTime().toUTC().isValid());

    std::printf("---- qtcore-probe: %d failed ----\n", failures);
    return failures;
}
