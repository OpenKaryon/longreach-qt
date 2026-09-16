// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// The two QtWidgets base classes the gallery uses concrete subclasses of
// without ever naming the bases - QGraphicsEffect and QGraphicsLayout - and
// QtMacExtras, which exists only in the macOS SDKs and so had never been
// reached from a suite verified on Windows and Linux.
//
// The effect and layout bases are covered the way they are meant to be used:
// by subclassing. Qt's own QGraphicsBlurEffect and QGraphicsLinearLayout are
// already exercised elsewhere; what was missing is the extension point behind
// them, which is what an application writes when the built-ins do not fit.
#include "../common/smokecheck.h"

#include <QGraphicsEffect>
#include <QGraphicsLayout>
#include <QGraphicsLayoutItem>
#include <QGraphicsScene>
#include <QGraphicsWidget>
#include <QPainter>
#include <QPixmap>

#ifdef SMOKE_HAVE_MACEXTRAS
#include <QMacPasteboardMime>
#include <QMacToolBar>
#include <QMacToolBarItem>
#endif

namespace {

// A custom effect: draw() is the single pure virtual, and sourcePixmap() is
// how an effect gets at what it is decorating.
class SmokeGraphicsEffect : public QGraphicsEffect
{
public:
    void draw(QPainter *painter) override
    {
        ++drawn;
        QPoint offset;
        const QPixmap source = sourcePixmap(Qt::LogicalCoordinates, &offset);
        if (!source.isNull())
            painter->drawPixmap(offset, source);
    }
    int drawn = 0;
};

// A custom layout: count/itemAt/removeAt from QGraphicsLayout plus sizeHint
// from QGraphicsLayoutItem are everything a layout has to answer.
class SmokeGraphicsLayout : public QGraphicsLayout
{
public:
    explicit SmokeGraphicsLayout(QGraphicsLayoutItem *parent = nullptr)
        : QGraphicsLayout(parent) {}

    int count() const override { return m_items.size(); }
    QGraphicsLayoutItem *itemAt(int i) const override { return m_items.value(i); }
    void removeAt(int index) override
    {
        if (index >= 0 && index < m_items.size())
            m_items.removeAt(index);
    }
    void addItem(QGraphicsLayoutItem *item) { m_items.append(item); }

protected:
    QSizeF sizeHint(Qt::SizeHint, const QSizeF &) const override { return QSizeF(64, 32); }

private:
    QList<QGraphicsLayoutItem *> m_items;
};

#ifdef SMOKE_HAVE_MACEXTRAS
// The pasteboard converter a macOS application registers to teach Qt about a
// custom flavour. Every method is pure virtual, so a subclass is the only way
// the class exists at all.
class SmokePasteboardMime : public QMacPasteboardMime
{
public:
    SmokePasteboardMime() : QMacPasteboardMime(MIME_ALL) {}

    QString convertorName() override { return QStringLiteral("qt-smoke"); }
    bool canConvert(const QString &mime, QString) override
    { return mime == QStringLiteral("text/plain"); }
    QString mimeFor(QString) override { return QStringLiteral("text/plain"); }
    QString flavorFor(const QString &) override { return QStringLiteral("public.utf8-plain-text"); }
    QVariant convertToMime(const QString &, QList<QByteArray> data, QString) override
    { return data.value(0); }
    QList<QByteArray> convertFromMime(const QString &, QVariant data, QString) override
    { return { data.toByteArray() }; }
};
#endif

} // namespace

void checkGraphicsExtensionPoints(SmokeReporter &r)
{
    r.check("widgets/custom-graphics-effect", [&](QString &d) {
        QGraphicsScene scene;
        auto *widget = new QGraphicsWidget;
        widget->resize(40, 20);
        scene.addItem(widget);

        auto *effect = new SmokeGraphicsEffect;
        QGraphicsEffect *effectBase = effect;
        widget->setGraphicsEffect(effectBase);
        effectBase->setEnabled(true);

        // Rendering the scene is what makes the effect's draw() run; a
        // QPixmap paint device needs no window and no GPU.
        QPixmap target(64, 32);
        target.fill(Qt::transparent);
        {
            QPainter painter(&target);
            scene.render(&painter);
        }

        bool ok = widget->graphicsEffect() == effectBase
            && effectBase->isEnabled()
            && effect->drawn > 0;
        if (!ok)
            d = QStringLiteral("effect was installed but never asked to draw");
        return ok;
    });

    r.check("widgets/custom-graphics-layout", [&](QString &d) {
        auto *host = new QGraphicsWidget;
        auto *child = new QGraphicsWidget(host);

        auto *layout = new SmokeGraphicsLayout;
        layout->addItem(child);
        host->setLayout(layout);

        QGraphicsLayout *layoutBase = layout;
        QGraphicsLayoutItem *itemBase = layout;
        layoutBase->setContentsMargins(2, 2, 2, 2);
        qreal left = 0, top = 0, right = 0, bottom = 0;
        layoutBase->getContentsMargins(&left, &top, &right, &bottom);

        const QSizeF hint = itemBase->effectiveSizeHint(Qt::PreferredSize);

        bool ok = layoutBase->count() == 1
            && layoutBase->itemAt(0) == child
            && qFuzzyCompare(left, qreal(2))
            && hint.width() >= 64;
        layoutBase->removeAt(0);
        if (ok && layoutBase->count() != 0)
            ok = false;
        delete host;
        if (!ok)
            d = QStringLiteral("custom layout did not answer for its item");
        return ok;
    });

    r.check("macextras/toolbar-and-pasteboard-mime", [&](QString &d) {
#ifdef SMOKE_HAVE_MACEXTRAS
        // No NSWindow is attached, so nothing is shown; the toolbar and its
        // items are ordinary QObjects until one is.
        QMacToolBar toolBar(QStringLiteral("qt-smoke"));
        QMacToolBarItem *item = toolBar.addItem(QIcon(), QStringLiteral("Item"));
        QMacToolBarItem *standalone = new QMacToolBarItem(&toolBar);
        standalone->setText(QStringLiteral("Standalone"));
        standalone->setStandardItem(QMacToolBarItem::Space);
        toolBar.addAllowedItem(QIcon(), QStringLiteral("Allowed"));

        SmokePasteboardMime mime;
        QMacPasteboardMime *mimeBase = &mime;

        bool ok = item != nullptr
            && standalone->standardItem() == QMacToolBarItem::Space
            && mimeBase->convertorName() == QStringLiteral("qt-smoke")
            && mimeBase->canConvert(QStringLiteral("text/plain"), QString());
        if (!ok)
            d = QStringLiteral("QtMacExtras objects did not behave as constructed");
        return ok;
#else
        r.skip(d, QStringLiteral("QtMacExtras is not in this SDK"));
        return false;
#endif
    });
}
