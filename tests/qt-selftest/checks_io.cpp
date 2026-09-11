// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Filesystem, settings, mime, storage, standard paths. Headless.
#include "../common/smokecheck.h"
#include "checks.h"

#include <QFile>
#if SMOKE_QT5
#include <QFileDevice>
#include <QSaveFile>
#endif
#include <QFileInfo>
#include <QDir>
#include <QDirIterator>
#include <QTemporaryFile>
#if SMOKE_QT5
#include <QTemporaryDir>
#endif
#include <QBuffer>
#include <QTextStream>
#include <QTextStreamManipulator>
#if SMOKE_QT5
#include <QStandardPaths>
#endif
#include <QSettings>
#if SMOKE_QT5
#include <QMimeDatabase>
#include <QMimeType>
#include <QStorageInfo>
#include <QFileSelector>
#include <QLockFile>
#endif

void checkIo(SmokeReporter &r)
{
    r.check("io/file+fileinfo", [&r](QString &d) {
#if SMOKE_QT5
        QTemporaryDir tmp;
        if (!tmp.isValid()) { d="no tempdir"; return false; }
        QString path = tmp.filePath("data.bin");
        QFile f(path);
        QFileDevice *device = &f;
        if (!f.open(QIODevice::WriteOnly)) { d="open write"; return false; }
        f.write(QByteArray(100,'x')); f.close();
        QFileInfo fi(path);
        return device->fileName() == path && fi.exists() && fi.size()==100 && fi.suffix()=="bin" && fi.isFile();
#else
        QTemporaryFile f;
        if (!f.open()) { d="open write"; return false; }
        f.write(QByteArray(100, 'x')); f.flush();
        QFileInfo fi(f.fileName());
        return fi.exists() && fi.size()==100 && fi.isFile();
#endif
    });
    r.check("io/savefile-atomic", [&r](QString &d) {
#if SMOKE_QT5
        QTemporaryDir tmp; QString path = tmp.filePath("out.txt");
        QSaveFile sf(path);
        if (!sf.open(QIODevice::WriteOnly)) { d="open"; return false; }
        sf.write("committed");
        if (!sf.commit()) { d="commit"; return false; }
        QFile in(path); in.open(QIODevice::ReadOnly);
        return in.readAll()=="committed";
#else
        r.skip(d, QStringLiteral("QSaveFile arrived in Qt 5"));
        return false;
#endif
    });
    r.check("io/dir+iterator", [&r](QString &d) {
#if SMOKE_QT5
        QTemporaryDir tmp; QDir dir(tmp.path());
        dir.mkpath("sub/deep");
        for (auto n : {"a.txt","b.txt","c.log"}) { QFile f(dir.filePath(n)); f.open(QIODevice::WriteOnly); f.write("x"); }
        int txt=0; QDirIterator it(tmp.path(), {"*.txt"}, QDir::Files, QDirIterator::Subdirectories);
        while (it.hasNext()) { it.next(); ++txt; }
        return dir.exists("sub/deep") && txt==2 && dir.entryList(QDir::Files).size()==3;
#else
        QDir dir(QDir::tempPath());
        int count = 0;
        QDirIterator it(dir.path(), QDir::Files);
        while (it.hasNext() && count < 2) { it.next(); ++count; }
        return dir.exists();
#endif
    });
    r.check("io/temporaryfile", [&r](QString &d) {
        QTemporaryFile tf;
        if (!tf.open()) { d="open"; return false; }
        tf.write("temp"); tf.flush();
        QString nm = tf.fileName();
        return !nm.isEmpty() && QFile::exists(nm);
    });
    r.check("io/settings-ini", [&r](QString &d) {
#if SMOKE_QT5
        QTemporaryDir tmp; QString path = tmp.filePath("cfg.ini");
        { QSettings s(path, QSettings::IniFormat);
          s.setValue("grp/n", 123); s.setValue("grp/s", "hi");
          s.beginGroup("arr"); s.setValue("k", QStringList{"a","b"}); s.endGroup(); s.sync(); }
        QSettings s2(path, QSettings::IniFormat);
        return s2.value("grp/n").toInt()==123 && s2.value("grp/s").toString()=="hi"
               && s2.value("arr/k").toStringList().size()==2;
#else
        QTemporaryFile tmp;
        if (!tmp.open()) { d="temp file"; return false; }
        const QString path = tmp.fileName(); tmp.close();
        QSettings s(path, QSettings::IniFormat); s.setValue("grp/n", 123); s.sync();
        return QSettings(path, QSettings::IniFormat).value("grp/n").toInt()==123;
#endif
    });
    r.check("io/standardpaths", [&r](QString &d) {
#if SMOKE_QT5
        QString tmp = QStandardPaths::writableLocation(QStandardPaths::TempLocation);
        QString name = QStandardPaths::displayName(QStandardPaths::HomeLocation);
        return !tmp.isEmpty() && !name.isEmpty();
#else
        r.skip(d, QStringLiteral("QStandardPaths arrived in Qt 5"));
        return false;
#endif
    });
    r.check("io/textstream-fields+codec", [&r](QString &d) {
        // Set an explicit codec: QTextStream defaults to the locale codec, which
        // on e.g. a non-UTF-8 locale would mangle "cafe" with an accent.
        QByteArray buf;
#if QT_VERSION_MAJOR < 6
        { QTextStream ts(&buf); ts.setCodec("UTF-8");
          ts << qSetFieldWidth(5) << 42 << reset << " " << QString::fromUtf8("caf\xc3\xa9"); }
        QTextStream in(&buf); in.setCodec("UTF-8");
#else
        { QTextStream ts(&buf); ts.setEncoding(QStringConverter::Utf8);
          ts << qSetFieldWidth(5) << 42 << Qt::reset << " " << QString::fromUtf8("caf\xc3\xa9"); }
        QTextStream in(&buf); in.setEncoding(QStringConverter::Utf8);
#endif
        QString all = in.readAll();
        if (!all.contains("42")) { d="field 42 missing"; return false; }
        if (!all.contains(QString::fromUtf8("caf\xc3\xa9"))) { d="utf8 cafe accent lost"; return false; }
        return true;
    });
    r.check("io/mimedatabase", [&r](QString &d) {
#if SMOKE_QT5
        QMimeDatabase db;
        QMimeType t = db.mimeTypeForFile("photo.png", QMimeDatabase::MatchExtension);
        if (!t.isValid()) { r.skip(d,"no shared-mime-info"); return false; }
        return t.name().contains("png");
#else
        r.skip(d, QStringLiteral("QMimeDatabase arrived in Qt 5"));
        return false;
#endif
    });
    r.check("io/storageinfo", [&r](QString &d) {
#if SMOKE_QT5
        QStorageInfo si = QStorageInfo::root();
        if (!si.isValid()) { r.skip(d,"no root volume info"); return false; }
        return si.bytesTotal() > 0;
#else
        r.skip(d, QStringLiteral("QStorageInfo arrived in Qt 5"));
        return false;
#endif
    });
    r.check("io/fileselector", [&r](QString &d) {
#if SMOKE_QT5
        QFileSelector fs;
        return !fs.allSelectors().isEmpty();
#else
        r.skip(d, QStringLiteral("QFileSelector arrived in Qt 5"));
        return false;
#endif
    });
    r.check("io/lockfile", [&r](QString &d) {
#if SMOKE_QT5
        QTemporaryDir tmp; QLockFile lf(tmp.filePath("x.lock"));
        if (!lf.tryLock(1000)) { d="lock"; return false; }
        lf.unlock();
        return true;
#else
        r.skip(d, QStringLiteral("QLockFile arrived in Qt 5"));
        return false;
#endif
    });
}
