// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Headless behavioural self-test over the 2D graphics / animation / state-machine
// classes. Where possible a check renders with QPainter into a QImage and asserts
// on actual pixels, so it verifies real drawing (not just object construction)
// while staying headless and diff-able across OSes.
#include "../common/smokecheck.h"
#include "graphics.h"

#include <QVariantAnimation>
#include <QEventLoop>
#include <QTimer>

// QVariantAnimation is abstract in Qt 4 (updateCurrentValue() is pure there);
// a concrete subclass works on all three.
class SmokeVariantAnimation : public QVariantAnimation
{
protected:
    void updateCurrentValue(const QVariant &) {}
};

#include <QImage>
#include <QPixmap>
#include <QBitmap>
#include <QSvgWidget>
#include <QSvgRenderer>
#include <QGraphicsSvgItem>
#include <QPicture>
#include <QPainter>
#include <QPen>
#include <QBrush>
#include <QLinearGradient>
#include <QRadialGradient>
#include <QConicalGradient>
#include <QPainterPath>
#include <QPainterPathStroker>
#include <QPolygon>
#include <QPolygonF>
#include <QRegion>
#include <QTransform>
#if QT_VERSION_MAJOR < 6
#include <QMatrix>       // replaced by QTransform in Qt 6
#endif
#include <QStaticText>
#include <QFont>
#include <QFontMetrics>
#include <QColor>

#include <QPropertyAnimation>
#include <QVariantAnimation>
#include <QParallelAnimationGroup>
#include <QSequentialAnimationGroup>
#include <QPauseAnimation>
#include <QEasingCurve>
#include <QTimeLine>
#include <QObject>

#include <QStateMachine>
#include <QState>
#include <QFinalState>
#include <QSignalTransition>

#include <QGraphicsScene>
#include <QGraphicsPathItem>
#include <QGraphicsPixmapItem>
#include <QGraphicsPolygonItem>
#include <QGraphicsOpacityEffect>
#include <QGraphicsColorizeEffect>
#include <QGraphicsBlurEffect>
#include <QGraphicsDropShadowEffect>

// A minimal QObject with an animatable int property, used by the animation checks.
class Animatable : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int pos READ pos WRITE setPos)
public:
    int pos() const { return m_pos; }
    void setPos(int p) { m_pos = p; }
private:
    int m_pos = 0;
};

// Helper: is pixel roughly this colour (tolerance for antialiasing).
static bool near(QRgb got, const QColor &want, int tol = 24)
{
    return qAbs(qRed(got)   - want.red())   <= tol
        && qAbs(qGreen(got) - want.green()) <= tol
        && qAbs(qBlue(got)  - want.blue())  <= tol;
}

void checkPainter(SmokeReporter &r)
{
    r.check("painter/fill-and-pixel", [&](QString &d) {
        QImage img(40, 40, QImage::Format_ARGB32);
        img.fill(Qt::white);
        QPainter p(&img);
        p.fillRect(QRect(10, 10, 20, 20), QColor(200, 0, 0));
        p.end();
        if (!near(img.pixel(20, 20), QColor(200, 0, 0))) { d = "center not red"; return false; }
        if (!near(img.pixel(2, 2), Qt::white)) { d = "corner not white"; return false; }
        return true;
    });
    r.check("painter/pen-brush-shapes", [&](QString &d) {
        QImage img(60, 60, QImage::Format_ARGB32);
        img.fill(Qt::white);
        QPainter p(&img);
        p.setRenderHint(QPainter::Antialiasing);
        QPen pen(QColor(0, 0, 180)); pen.setWidth(3); pen.setJoinStyle(Qt::RoundJoin);
        p.setPen(pen);
        p.setBrush(QBrush(QColor(0, 160, 0)));
        p.drawEllipse(QRect(10, 10, 40, 40));
        p.end();
        // Inside the ellipse should be green, well outside should be white.
        return near(img.pixel(30, 30), QColor(0, 160, 0)) && near(img.pixel(1, 1), Qt::white);
    });
    r.check("painter/linear-gradient", [&](QString &d) {
        QImage img(100, 10, QImage::Format_ARGB32);
        QLinearGradient g(0, 0, 100, 0);
        g.setColorAt(0.0, Qt::black);
        g.setColorAt(1.0, Qt::white);
        QPainter p(&img);
        p.fillRect(img.rect(), g);
        p.end();
        int left = qRed(img.pixel(2, 5));
        int right = qRed(img.pixel(97, 5));
        if (!(left < 60 && right > 195)) { d = QString("left=%1 right=%2").arg(left).arg(right); return false; }
        return true;
    });
    r.check("painter/radial+conical-gradient", [&](QString &d) {
        QRadialGradient rg(50, 50, 50);
        rg.setColorAt(0, Qt::yellow); rg.setColorAt(1, Qt::blue);
        QConicalGradient cg(50, 50, 0);
        cg.setColorAt(0, Qt::red); cg.setColorAt(1, Qt::green);
        return rg.type() == QGradient::RadialGradient
            && cg.type() == QGradient::ConicalGradient
            && rg.stops().size() == 2;
    });
    r.check("painter/clip-region", [&](QString &d) {
        QImage img(40, 40, QImage::Format_ARGB32);
        img.fill(Qt::white);
        QPainter p(&img);
        QRegion clip(QRect(0, 0, 20, 40));
        p.setClipRegion(clip);
        p.fillRect(img.rect(), QColor(50, 50, 50));
        p.end();
        // Left half painted, right half clipped away (still white).
        return near(img.pixel(5, 20), QColor(50, 50, 50)) && near(img.pixel(35, 20), Qt::white);
    });
    r.check("painter/text-metrics", [&](QString &d) {
        QFont f("Arial", 12);
        QFontMetrics fm(f);
        // horizontalAdvance() arrived in Qt 5.11 as the correctly-named
        // replacement for width(), which measures the same thing.
#if QT_VERSION >= QT_VERSION_CHECK(5, 11, 0)
        int w = fm.horizontalAdvance("Hello");
#else
        int w = fm.width("Hello");
#endif
        QStaticText st("Static");
        st.prepare(QTransform(), f);
        if (w <= 0) { d = "advance<=0"; return false; }
        return st.text() == "Static" && fm.height() > 0;
    });
}

void checkPaths(SmokeReporter &r)
{
    r.check("path/build-and-contains", [&](QString &d) {
        QPainterPath path;
        path.moveTo(0, 0);
        path.lineTo(100, 0);
        path.cubicTo(100, 100, 0, 100, 0, 50);
        path.closeSubpath();
        if (path.elementCount() < 4) { d = QString("elements=%1").arg(path.elementCount()); return false; }
        return path.contains(QPointF(10, 25)) && !path.contains(QPointF(200, 200));
    });
    r.check("path/stroker", [&](QString &d) {
        QPainterPath line;
        line.moveTo(0, 0); line.lineTo(50, 0);
        QPainterPathStroker stroker;
        stroker.setWidth(10);
        stroker.setCapStyle(Qt::RoundCap);
        QPainterPath outline = stroker.createStroke(line);
        // A 10px-wide stroke around a horizontal line has area -> non-empty bounds.
        return outline.boundingRect().height() >= 9 && !outline.isEmpty();
    });
    r.check("path/polygon-boundingrect", [&](QString &d) {
        QPolygon poly;
        poly << QPoint(0, 0) << QPoint(30, 0) << QPoint(30, 20) << QPoint(0, 20);
        QPolygonF polyF(poly);
        QRect bb = poly.boundingRect();
        // QRect(topLeft, bottomRight) is inclusive of both corners, so a
        // 0..30 x 0..20 point spread is a 31x21 rect, not 30x20.
        return bb.width() == 31 && bb.height() == 21 && polyF.size() == 4;
    });
    r.check("path/fill-renders", [&](QString &d) {
        QImage img(40, 40, QImage::Format_ARGB32);
        img.fill(Qt::white);
        QPainterPath tri;
        tri.moveTo(20, 2); tri.lineTo(38, 38); tri.lineTo(2, 38); tri.closeSubpath();
        QPainter p(&img);
        p.fillPath(tri, QColor(120, 0, 120));
        p.end();
        return near(img.pixel(20, 30), QColor(120, 0, 120)) && near(img.pixel(2, 2), Qt::white);
    });
}

void checkTransforms(SmokeReporter &r)
{
    r.check("transform/rotate-map", [&](QString &d) {
        QTransform t;
        t.rotate(90);
        QPointF mapped = t.map(QPointF(1, 0));
        // 90deg rotation sends (1,0) -> ~(0,1).
        if (qAbs(mapped.x()) > 1e-6 || qAbs(mapped.y() - 1.0) > 1e-6) {
            d = QString("mapped=(%1,%2)").arg(mapped.x()).arg(mapped.y());
            return false;
        }
        return t.isRotating();
    });
    r.check("transform/scale-translate-invert", [&](QString &d) {
        QTransform t;
        t.translate(10, 20).scale(2, 2);
        QPointF p = t.map(QPointF(5, 5));   // (10+2*5, 20+2*5) = (20,30)
        bool ok = qFuzzyCompare(p.x(), 20.0) && qFuzzyCompare(p.y(), 30.0);
        bool invertible = false;
        QTransform inv = t.inverted(&invertible);
        QPointF back = inv.map(p);
        return ok && invertible && qFuzzyCompare(back.x(), 5.0) && qFuzzyCompare(back.y(), 5.0);
    });
    r.check("transform/painter-shear-renders", [&](QString &d) {
        QImage img(60, 60, QImage::Format_ARGB32);
        img.fill(Qt::white);
        QPainter p(&img);
        p.translate(10, 10);
        p.shear(0.3, 0.0);
        p.fillRect(QRect(0, 0, 20, 20), QColor(0, 0, 0));
        p.end();
        // Something dark was drawn somewhere in the image.
        bool foundDark = false;
        for (int y = 0; y < 60 && !foundDark; ++y)
            for (int x = 0; x < 60; ++x)
                if (qRed(img.pixel(x, y)) < 80) { foundDark = true; break; }
        return foundDark;
    });
}

void checkImageOps(SmokeReporter &r)
{
    r.check("image/scale-convert", [&](QString &d) {
        QImage img(20, 20, QImage::Format_RGB32);
        img.fill(Qt::red);
        QImage scaled = img.scaled(40, 10, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
        // Format_Grayscale8 arrived in Qt 5.5. Qt 4 has no 8-bit greyscale
        // format at all, so the nearest equivalent is an indexed 8-bit
        // image - which exercises the same conversion path.
#if QT_VERSION >= QT_VERSION_CHECK(5, 5, 0)
        QImage gray = img.convertToFormat(QImage::Format_Grayscale8);
#else
        QImage gray = img.convertToFormat(QImage::Format_Indexed8);
#endif
        return scaled.width() == 40 && scaled.height() == 10 && !gray.isNull();
    });
    r.check("image/pixmap-bitmap-mask", [&](QString &d) {
        QPixmap pm(30, 30);
        pm.fill(Qt::green);
        QBitmap mask(30, 30);
        mask.fill(Qt::color1);           // opaque mask
        pm.setMask(mask);
        QImage back = pm.toImage();
        return !pm.isNull() && pm.width() == 30 && !back.isNull() && !mask.isNull();
    });
    r.check("image/picture-record-replay", [&](QString &d) {
        QPicture pic;
        QPainter rp(&pic);
        rp.fillRect(QRect(0, 0, 10, 10), Qt::blue);
        rp.end();
        if (pic.isNull() || pic.boundingRect().isEmpty()) { d = "picture empty"; return false; }
        QImage img(20, 20, QImage::Format_ARGB32);
        img.fill(Qt::white);
        QPainter p(&img);
        p.drawPicture(0, 0, pic);
        p.end();
        return near(img.pixel(5, 5), Qt::blue);
    });
    r.check("image/svg-widget-renders", [&](QString &d) {
        static const char *svg =
            "<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'>"
            "<rect width='10' height='10' fill='lime'/></svg>";
        QSvgWidget widget;
        widget.load(QByteArray(svg));
        widget.resize(10, 10);
        QImage img(10, 10, QImage::Format_ARGB32);
        img.fill(Qt::white);
        QPainter p(&img);
        widget.renderer()->render(&p);
        p.end();
        return near(img.pixel(5, 5), Qt::green);
    });
}

void checkAnimations(SmokeReporter &r)
{
    r.check("anim/property-animation", [&](QString &d) {
        Animatable obj;
        QPropertyAnimation anim(&obj, "pos");
        anim.setStartValue(0);
        anim.setEndValue(100);
        anim.setDuration(1000);
        // QPropertyAnimation only writes the target property while its state
        // is Running/Paused (Stopped is a no-op guard) - start() then
        // pause() immediately so we can drive it by hand via setCurrentTime()
        // without a real event loop or timer.
        anim.start();
        anim.pause();
        anim.setCurrentTime(500);
        int mid = obj.pos();
        anim.setCurrentTime(1000);
        if (obj.pos() != 100) { d = QString("end pos=%1").arg(obj.pos()); return false; }
        return mid > 10 && mid < 90;     // linear default -> ~50
    });
    r.check("anim/easing-curve", [&](QString &d) {
        QEasingCurve ease(QEasingCurve::InOutQuad);
        qreal v0 = ease.valueForProgress(0.0);
        qreal v1 = ease.valueForProgress(1.0);
        qreal vm = ease.valueForProgress(0.5);
        return qFuzzyCompare(v0 + 1, 1.0) && qFuzzyCompare(v1, 1.0)
            && vm > 0.4 && vm < 0.6 && ease.type() == QEasingCurve::InOutQuad;
    });
    r.check("anim/variant-animation-interpolate", [&](QString &d) {
        // Exercise the actual registered QColor interpolator. Static Qt4
        // needs the GUI registration object retained by its linker.
        SmokeVariantAnimation va;
        va.setStartValue(QColor(Qt::black));
        va.setEndValue(QColor(Qt::white));
        va.setDuration(100);
#if !SMOKE_QT5
        // Advance the Qt4 timer before pausing and checking the midpoint.
        va.start();
        QEventLoop loop;
        QTimer::singleShot(32, &loop, SLOT(quit()));
        loop.exec();
        va.pause();
#endif
        va.setCurrentTime(50);
        QColor c = va.currentValue().value<QColor>();
        return c.red() > 80 && c.red() < 175;   // halfway grey
    });
    r.check("anim/groups", [&](QString &d) {
        Animatable a, b;
        auto *pa = new QParallelAnimationGroup;
        auto *a1 = new QPropertyAnimation(&a, "pos"); a1->setEndValue(10); a1->setDuration(100);
        auto *a2 = new QPropertyAnimation(&b, "pos"); a2->setEndValue(20); a2->setDuration(100);
        pa->addAnimation(a1); pa->addAnimation(a2);

        QSequentialAnimationGroup seq;
        seq.addAnimation(pa);
        seq.addPause(50);
        int total = pa->animationCount();
        // Parallel duration = max child; sequential = sum + pause.
        bool ok = total == 2 && pa->duration() == 100 && seq.duration() == 150
               && seq.animationCount() == 2;
        return ok;
    });
}

void checkStateMachine(SmokeReporter &r)
{
    r.check("statemachine/build-and-transition", [&](QString &d) {
        QStateMachine machine;
        auto *s1 = new QState(&machine);
        auto *s2 = new QState(&machine);
        auto *done = new QFinalState(&machine);

        QObject trigger;                 // emits a signal to drive a transition
        s1->addTransition(&trigger, SIGNAL(destroyed()), s2);
        s2->addTransition(done);
        machine.setInitialState(s1);
        // We only assert the graph is wired; running needs an event loop.
        bool ok = machine.configuration().isEmpty()   // not started yet
               && s1->parent() == &machine
               && machine.initialState() == s1;
        return ok;
    });
    r.check("statemachine/signal-transition", [&](QString &d) {
        QState parent;
        auto *s1 = new QState(&parent);
        auto *s2 = new QState(&parent);
        QObject src;
        QSignalTransition *t = s1->addTransition(&src, SIGNAL(destroyed()), s2);
        return t != nullptr && t->targetState() == s2 && t->sourceState() == s1;
    });
}

void checkGraphicsEffectsAndItems(SmokeReporter &r)
{
    r.check("gfxitem/path-pixmap-polygon", [&](QString &d) {
        QGraphicsScene scene;
        QPainterPath pp; pp.addEllipse(0, 0, 20, 20);
        auto *pi = scene.addPath(pp);
        QPixmap pm(10, 10); pm.fill(Qt::cyan);
        auto *px = scene.addPixmap(pm);
        QPolygonF poly; poly << QPointF(0, 0) << QPointF(10, 0) << QPointF(5, 10);
        auto *pg = scene.addPolygon(poly);
        return scene.items().size() == 3
            && qgraphicsitem_cast<QGraphicsPathItem *>(pi) != nullptr
            && qgraphicsitem_cast<QGraphicsPixmapItem *>(px) != nullptr
            && qgraphicsitem_cast<QGraphicsPolygonItem *>(pg) != nullptr;
    });
    r.check("gfxitem/svg-item", [&](QString &d) {
        static const char *svg =
            "<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'>"
            "<rect width='10' height='10' fill='red'/></svg>";
        QGraphicsScene scene;
        auto *item = new QGraphicsSvgItem;
        item->setSharedRenderer(new QSvgRenderer(QByteArray(svg), item));
        scene.addItem(item);
        return scene.items().contains(item) && item->renderer()->isValid();
    });
    r.check("gfxeffect/opacity-colorize-blur-shadow", [&](QString &d) {
        QGraphicsScene scene;
        auto *rect = scene.addRect(0, 0, 20, 20);

        QGraphicsOpacityEffect opacity; opacity.setOpacity(0.5);
        rect->setGraphicsEffect(&opacity);
        bool okOpacity = rect->graphicsEffect() == &opacity && qFuzzyCompare(opacity.opacity(), 0.5);

        QGraphicsColorizeEffect colorize; colorize.setColor(Qt::red);
        QGraphicsBlurEffect blur; blur.setBlurRadius(4);
        QGraphicsDropShadowEffect shadow; shadow.setOffset(3, 3);

        return okOpacity && colorize.color() == QColor(Qt::red)
            && qFuzzyCompare(blur.blurRadius(), qreal(4))
            && shadow.offset() == QPointF(3, 3);
    });
    r.check("gfxeffect/renders-through-scene", [&](QString &d) {
        QGraphicsScene scene(0, 0, 40, 40);
        auto *rect = scene.addRect(5, 5, 30, 30, QPen(Qt::NoPen), QBrush(QColor(0, 120, 0)));
        auto *op = new QGraphicsOpacityEffect; op->setOpacity(1.0);
        rect->setGraphicsEffect(op);
        QImage img(40, 40, QImage::Format_ARGB32);
        img.fill(Qt::white);
        QPainter p(&img);
        scene.render(&p);
        p.end();
        return near(img.pixel(20, 20), QColor(0, 120, 0), 40);
    });
}

#include "selftest.moc"   // Animatable's Q_OBJECT lives in this .cpp
