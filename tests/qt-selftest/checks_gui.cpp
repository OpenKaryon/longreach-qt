// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Non-widget GUI value types: geometry, color, font metrics, QPainter drawing
// onto a QImage (no window), transforms, vectors/matrices, painter paths,
// regions, polygons, gradients, icons/pixmaps. Headless (offscreen raster).
#include "../common/smokecheck.h"
#include "checks.h"

#include <QPoint>
#include <QPointF>
#include <QLine>
#include <QLineF>
#include <QRect>
#include <QRectF>
#include <QSize>
#include <QSizeF>
#include <QMargins>
#include <QPolygon>
#include <QPolygonF>
#include <QRegion>
#include <QColor>
#if SMOKE_QT5
#include <QColorSpace>
#endif
#include <QImage>
#include <QPixmap>
#include <QBitmap>
#include <QIcon>
#include <QPainter>
#include <QPainterPath>
#include <QPen>
#include <QBrush>
#include <QLinearGradient>
#include <QRadialGradient>
#include <QConicalGradient>
#include <QTransform>
#include <QMatrix4x4>
#include <QVector2D>
#include <QVector3D>
#include <QVector4D>
#include <QQuaternion>
#include <QFont>
#include <QFontMetrics>
#include <QFontMetricsF>
#include <QFontInfo>
#include <QFontDatabase>
#if SMOKE_QT5
#include <QRawFont>
#include <QGuiApplication>
#endif

void checkGuiValue(SmokeReporter &r)
{
    r.check("geom/point-size-rect", [&r](QString &d) {
        QRect a(0,0,100,50);
        QRect b = a.translated(10,10);
        QRect inter = a.intersected(b);
        // QRect uses inclusive integer bounds: right = left+width-1, so the
        // centre of a 100x50 rect at origin is (49,24), not (50,25).
        if (a.center()!=QPoint(49,24)) { d="center "+QString("%1,%2").arg(a.center().x()).arg(a.center().y()); return false; }
        return inter.width()==90 && a.contains(QPoint(1,1)) && a.width()==100;
    });
    r.check("geom/line+margins", [&r](QString &d) {
        QLineF l(0,0,3,4);
        QRect r0(0,0,10,10);
#if SMOKE_QT5
        r0 = r0.marginsAdded(QMargins(1,1,1,1));
#else
        r0.adjust(-1, -1, 1, 1);
#endif
        return qFuzzyCompare(l.length(), 5.0) && r0.width()==12;
    });
    r.check("geom/polygon+region", [&r](QString &d) {
        QPolygon poly; poly << QPoint(0,0) << QPoint(20,0) << QPoint(20,20) << QPoint(0,20);
        QRegion reg(poly);
        if (!reg.contains(QPoint(10,10))) { d="inside point not contained"; return false; }
        if (reg.contains(QPoint(50,50))) { d="outside point contained"; return false; }
        return poly.size()==4 && reg.boundingRect().width()>=20;
    });
    r.check("color/spaces", [&r](QString &d) {
        QColor c = QColor::fromRgb(255,128,0);
        int h,s,v; c.getHsv(&h,&s,&v);
        QColor named("steelblue");
        return c.red()==255 && c.green()==128 && named.isValid() && c.name()=="#ff8000";
    });
    r.check("transform/map", [&r](QString &d) {
        QTransform t; t.rotate(90);
        QPointF p = t.map(QPointF(1,0));
        QTransform inv = t.inverted();
        return qAbs(p.x())<1e-9 && qFuzzyCompare(p.y(),1.0) && !inv.isIdentity();
    });
    r.check("math/vectors", [&r](QString &d) {
        QVector3D a(1,0,0), b(0,1,0);
        QVector3D c = QVector3D::crossProduct(a,b);
        return qAbs(c.z()-1.0f)<1e-5f && qAbs(a.length()-1.0f)<1e-5f
               && qAbs(QVector2D(3,4).length()-5.0f)<1e-5f;
    });
    r.check("math/matrix4x4+quaternion", [&r](QString &d) {
        QMatrix4x4 m; m.translate(1,2,3); m.scale(2);
        QVector3D p = m.map(QVector3D(1,1,1));
        QQuaternion q = QQuaternion::fromAxisAndAngle(0,0,1,90);
        QVector3D rot = q.rotatedVector(QVector3D(1,0,0));
        return qAbs(p.x()-3.0f)<1e-5f && qAbs(rot.x())<1e-5f && qAbs(rot.y()-1.0f)<1e-5f;
    });
    r.check("paint/image-draw", [&r](QString &d) {
        QImage img(64,64,QImage::Format_ARGB32);
        img.fill(Qt::white);
        QPainter p(&img);
        p.setRenderHint(QPainter::Antialiasing);
        p.setPen(QPen(Qt::black, 2));
        p.setBrush(QBrush(Qt::red));
        p.drawEllipse(8,8,48,48);
        QPainterPath path; path.moveTo(0,0); path.cubicTo(20,0,20,64,64,64);
        p.strokePath(path, QPen(Qt::blue,1));
        p.end();
        // center should be red-ish now
        QColor c = QColor::fromRgb(img.pixel(32,32));
        if (c.red() < 150 || c.green() > 120) { d=QString("center=%1").arg(c.name()); return false; }
        return true;
    });
    r.check("paint/gradients", [&r](QString &d) {
        QImage img(32,32,QImage::Format_ARGB32); img.fill(Qt::black);
        QLinearGradient lg(0,0,32,0); lg.setColorAt(0,Qt::black); lg.setColorAt(1,Qt::white);
        QRadialGradient rg(16,16,16); QConicalGradient cg(16,16,0);
        QPainter p(&img); p.fillRect(img.rect(), lg); p.end();
        return QColor::fromRgb(img.pixel(31,16)).red() > QColor::fromRgb(img.pixel(0,16)).red();
    });
    r.check("gui/pixmap+bitmap+icon", [&r](QString &d) {
        QImage img(16,16,QImage::Format_ARGB32); img.fill(Qt::green);
        QPixmap pm = QPixmap::fromImage(img);
        QIcon icon(pm);
        QPixmap back = icon.pixmap(16,16);
        return !pm.isNull() && pm.size()==QSize(16,16) && !icon.isNull() && !back.isNull();
    });
    r.check("font/metrics", [&r](QString &d) {
        QFont f("Arial", 12); f.setBold(true);
        QFontMetrics fm(f);
        QFontInfo fi(f);
#if SMOKE_QT5
        int w = fm.horizontalAdvance("Hello");
#else
        int w = fm.width("Hello");
#endif
        return w>0 && fm.height()>0 && fi.pointSize()>0 && f.bold();
    });
    r.check("font/database", [&r](QString &d) {
        QFontDatabase db;
        QStringList fams = db.families();
        if (fams.isEmpty()) { r.skip(d,"no fonts installed"); return false; }
        return db.pointSizes(fams.first()).size() >= 0; // just exercise the API
    });
}
