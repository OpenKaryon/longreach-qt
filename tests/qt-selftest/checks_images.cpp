// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Image format plugins - round-trip every writable format in memory and decode
// it back. Exercises exactly the imageformat plugins the XP backport cares
// about, with no image files on disk. Headless.
#include "../common/smokecheck.h"
#include "checks.h"

#include <QImage>
#include <QImageReader>
#include <QImageWriter>
#include <QImageIOHandler>
#include <QPainter>
#include <QColor>
#include <QBuffer>

void checkImages(SmokeReporter &r)
{
    QImage src(32,24,QImage::Format_ARGB32);
    src.fill(Qt::transparent);
    { QPainter p(&src); p.fillRect(0,0,16,24,Qt::red); p.fillRect(16,0,16,24,QColor(0,128,255)); }

    r.check("image/formats-available", [&](QString &d) {
        d = QString("write=%1 read=%2")
                .arg(QImageWriter::supportedImageFormats().size())
                .arg(QImageReader::supportedImageFormats().size());
        return QImageWriter::supportedImageFormats().size() >= 3;
    });

    const char *want[] = { "png","jpg","bmp","ppm","xpm","xbm","ico","tiff","webp","svg","gif" };
    for (const char *fmt : want) {
        QByteArray f(fmt);
        r.check(QString("image/%1").arg(fmt), [&, f](QString &d) {
#if !SMOKE_QT5
            if (f == "gif") {
                r.skip(d, QStringLiteral("Qt 4 GIF handler is decoder-only despite advertising write support"));
                return false;
            }
#endif
            bool canWrite = QImageWriter::supportedImageFormats().contains(f);
            bool canRead  = QImageReader::supportedImageFormats().contains(f);
            if (!canWrite && !canRead) { r.skip(d, "plugin not built"); return false; }
            if (!canWrite) { r.skip(d, "decode-only (no encoder)"); return false; }
            QByteArray blob; QBuffer buf(&blob); buf.open(QIODevice::WriteOnly);
            QImageWriter w(&buf, f);
            if (!w.write(src)) { d="encode: "+w.errorString(); return false; }
            buf.close();
            QBuffer in(&blob); in.open(QIODevice::ReadOnly);
            QImageReader rd(&in, f);
            QImage back = rd.read();
            if (back.isNull()) { d="decode: "+rd.errorString(); return false; }
            if (back.size()!=src.size()) { d=QString("size %1x%2").arg(back.width()).arg(back.height()); return false; }
            return true;
        });
    }
}
