// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Visual side of the graphics smoke app: tabs that exercise QPainter drawing,
// running animations, and the graphics-effect family - the things a headless
// self-test cannot show. On Windows XP this is where you eyeball
// antialiasing, gradients, text rendering, layered/shaped windows and the
// backported GL/raster paths.
#include "graphics.h"
// SMOKE_QT5 below; undefined it reads as 0 and lets the Qt 4 branch into the
// Qt 5 and Qt 6 Windows builds.
#include "../common/qtcompat.h"

#include <QWidget>
#include <QTabWidget>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QLabel>
#include <QPushButton>
#include <QComboBox>

#include <QPainter>
#include <QPainterPath>
#include <QLinearGradient>
#include <QRadialGradient>
#include <QConicalGradient>
#include <QPen>
#include <QBrush>
#include <QFont>
#include <QPixmap>
#include <QRegion>

#include <QPropertyAnimation>
#include <QSequentialAnimationGroup>
#include <QEasingCurve>

#include <QGraphicsOpacityEffect>
#include <QGraphicsColorizeEffect>
#include <QGraphicsBlurEffect>
#include <QGraphicsDropShadowEffect>

// <QtMath> is the Qt 5 umbrella spelling; the header itself has been
// qmath.h since Qt 4, and that name works on all three.
#include <QtCore/qmath.h>
#include <cmath>

// ---- A canvas that shows off 2D painting primitives ------------------------
class PainterCanvas : public QWidget
{
public:
    PainterCanvas() { setMinimumSize(400, 320); }

protected:
    void paintEvent(QPaintEvent *) override
    {
        QPainter p(this);
        p.setRenderHint(QPainter::Antialiasing);
        p.setRenderHint(QPainter::TextAntialiasing);
        p.fillRect(rect(), Qt::white);

        // Linear gradient bar
        QLinearGradient lg(10, 10, 190, 10);
        lg.setColorAt(0, QColor(30, 60, 200));
        lg.setColorAt(1, QColor(200, 60, 30));
        p.fillRect(QRect(10, 10, 180, 30), lg);

        // Radial + conical swatches
        QRadialGradient rg(90, 110, 45);
        rg.setColorAt(0, Qt::yellow); rg.setColorAt(1, Qt::darkGreen);
        p.setPen(Qt::NoPen); p.setBrush(rg);
        p.drawEllipse(QPointF(90, 110), 45, 45);

        QConicalGradient cg(200, 110, 0);
        cg.setColorAt(0.0, Qt::red); cg.setColorAt(0.5, Qt::green); cg.setColorAt(1.0, Qt::blue);
        p.setBrush(cg);
        p.drawEllipse(QPointF(200, 110), 45, 45);

        // Pen styles
        int y = 180;
        const Qt::PenStyle styles[] = { Qt::SolidLine, Qt::DashLine, Qt::DotLine, Qt::DashDotLine };
        for (Qt::PenStyle s : styles) {
            QPen pen(Qt::black, 2, s);
            p.setPen(pen);
            p.drawLine(10, y, 190, y);
            y += 14;
        }

        // A filled, stroked painter path (star)
        QPainterPath star;
        const QPointF c(300, 100);
        for (int i = 0; i < 5; ++i) {
            double a = -M_PI / 2 + i * 4 * M_PI / 5;
            QPointF pt(c.x() + 55 * std::cos(a), c.y() + 55 * std::sin(a));
            if (i == 0) star.moveTo(pt); else star.lineTo(pt);
        }
        star.closeSubpath();
        p.setPen(QPen(QColor(120, 0, 120), 2));
        p.setBrush(QColor(230, 180, 230));
        p.drawPath(star);

        // Transformed text
        p.save();
        p.translate(300, 220);
        p.rotate(-20);
        p.setPen(Qt::darkBlue);
        p.setFont(QFont("Arial", 16, QFont::Bold));
        p.drawText(0, 0, "Qt on XP");
        p.restore();

        // Plain text at a few sizes to eyeball the font backend
        p.setPen(Qt::black);
        int ty = 250;
        for (int pt10 : { 8, 10, 12, 14 }) {
            p.setFont(QFont("Arial", pt10));
            p.drawText(10, ty, QString("Font %1pt - AaBbGg 0123").arg(pt10));
            ty += pt10 + 8;
        }
    }
};

// ---- An animated bouncing tile ---------------------------------------------
static QWidget *buildAnimationTab()
{
    auto *page = new QWidget;
    auto *lay = new QVBoxLayout(page);
    auto *info = new QLabel("A tile animated with QPropertyAnimation + QEasingCurve "
                            "(bounces horizontally, looping).");
    info->setWordWrap(true);
    lay->addWidget(info);

    auto *field = new QWidget;
    field->setMinimumHeight(120);
    field->setStyleSheet("background:#202830;");
    lay->addWidget(field, 1);

    auto *tile = new QLabel(field);
    tile->setFixedSize(60, 60);
    tile->setStyleSheet("background:#e0a020; border-radius:8px;");
    tile->move(10, 30);

    auto *anim = new QPropertyAnimation(tile, "pos", page);
    anim->setDuration(1600);
    anim->setStartValue(QPoint(10, 30));
    anim->setKeyValueAt(0.5, QPoint(300, 30));
    anim->setEndValue(QPoint(10, 30));
    anim->setEasingCurve(QEasingCurve::InOutCubic);
    anim->setLoopCount(-1);
    anim->start();

    return page;
}

// ---- Graphics effects applied to labels ------------------------------------
static QLabel *swatch(const QString &text, const QColor &bg)
{
    auto *l = new QLabel(text);
    l->setAlignment(Qt::AlignCenter);
    l->setFixedSize(110, 70);
    l->setStyleSheet(QString("background:%1; color:white; font-weight:bold;").arg(bg.name()));
    return l;
}

static QWidget *buildEffectsTab()
{
    auto *page = new QWidget;
    auto *lay = new QHBoxLayout(page);

    auto *opacity = swatch("Opacity", QColor(40, 120, 200));
    auto *oe = new QGraphicsOpacityEffect(opacity); oe->setOpacity(0.45);
    opacity->setGraphicsEffect(oe);

    auto *colorize = swatch("Colorize", QColor(40, 120, 200));
    auto *ce = new QGraphicsColorizeEffect(colorize); ce->setColor(Qt::red);
    colorize->setGraphicsEffect(ce);

    auto *blur = swatch("Blur", QColor(40, 120, 200));
    auto *be = new QGraphicsBlurEffect(blur); be->setBlurRadius(6);
    blur->setGraphicsEffect(be);

    auto *shadow = swatch("Shadow", QColor(40, 120, 200));
    auto *se = new QGraphicsDropShadowEffect(shadow); se->setOffset(5, 5); se->setBlurRadius(12);
    shadow->setGraphicsEffect(se);

    lay->addStretch();
    for (QLabel *w : { opacity, colorize, blur, shadow }) lay->addWidget(w);
    lay->addStretch();
    return page;
}

QWidget *buildGraphicsGallery()
{
    auto *tabs = new QTabWidget;
    tabs->addTab(new PainterCanvas, "Painter");
    tabs->addTab(buildAnimationTab(), "Animation");
    tabs->addTab(buildEffectsTab(), "Effects");
    return tabs;
}

// ---- Frameless, translucent, non-rectangular window ------------------------
class ShapedWindow : public QWidget
{
public:
    explicit ShapedWindow(QWidget *parent)
        : QWidget(parent, Qt::Window | Qt::FramelessWindowHint)
    {
#if defined(Q_OS_WIN) && !SMOKE_QT5
        if (QSysInfo::WindowsVersion < QSysInfo::WV_2000) {
            // Win9x/NT4 have window regions but no layered-window alpha API.
            // Preserve the shaped window with an opaque elliptical region.
            setMask(QRegion(QRect(4, 4, 252, 192), QRegion::Ellipse));
        } else
#endif
        setAttribute(Qt::WA_TranslucentBackground);
        setAttribute(Qt::WA_DeleteOnClose);
        setObjectName("graphics-shaped-window");
        resize(260, 200);
        auto *close = new QPushButton("Close", this);
        close->move(90, 150);
        // Pointer-to-member connect is Qt 5; Qt 4 takes SIGNAL/SLOT strings,
        // and both name the same signal and slot.
#if SMOKE_QT5
        connect(close, &QPushButton::clicked, this, &QWidget::close);
#else
        connect(close, SIGNAL(clicked()), this, SLOT(close()));
#endif
    }

protected:
    void paintEvent(QPaintEvent *) override
    {
        QPainter p(this);
        p.setRenderHint(QPainter::Antialiasing);
        QRadialGradient g(width() / 2.0, height() / 2.0, width() / 2.0);
        g.setColorAt(0, QColor(80, 160, 240, 235));
        g.setColorAt(1, QColor(20, 40, 90, 180));
        p.setPen(Qt::NoPen);
        p.setBrush(g);
        p.drawEllipse(rect().adjusted(4, 4, -4, -4));
        p.setPen(Qt::white);
        p.setFont(QFont("Arial", 12, QFont::Bold));
        p.drawText(rect().adjusted(0, 30, 0, 0), Qt::AlignHCenter | Qt::AlignTop,
                   "Shaped +\ntranslucent\nwindow");
    }
};

void showShapedWindow(QWidget *parent)
{
    auto *w = new ShapedWindow(parent);
    w->show();
}
