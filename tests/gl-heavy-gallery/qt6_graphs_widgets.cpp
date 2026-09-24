// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// QtGraphs' legend value type and the QtGraphsWidgets wrappers.
//
// A translation unit of its own, and that is a hard requirement rather than
// tidiness: QtGraphs and QtCharts declare classes of the same names, and
// qgraphsglobal.h refuses to compile - with a message saying so - if both are
// pulled into one file. qt6_views_and_graphs.cpp next door already includes
// QtCharts, and QLegendData lives in QtGraphs' qabstractseries.h, so covering
// it there is not possible at all. Nothing in this file includes QtCharts.
//
// The wrappers are the bridge for QWidget applications: a QtGraphs graph is a
// QML item, and each of these owns a QQuickWidget that hosts one.
//
// What they allow before that QQuickWidget exists was measured rather than
// assumed, and the answer is narrower than it looks. Constructing them is safe,
// widget() correctly answers null, and the metaobjects are fully formed - but
// every property accessor dereferences the not-yet-created graph object and
// segfaults. Not just the setters: reading barThickness() on a freshly
// constructed Q3DBarsWidgetItem is enough to crash on Qt 6.8. So the check
// stops at construction and type identity, which is all these classes can
// honestly be asked outside a real widget hierarchy.
#include "../common/smokecheck.h"

#include <QColor>
#include <QList>
#include <QString>

#ifdef SMOKE_HAVE_GRAPHS
#include <QLegendData>
#endif

#ifdef SMOKE_HAVE_GRAPHSWIDGETS
#include <Q3DBarsWidgetItem>
#include <Q3DGraphsWidgetItem>
#include <Q3DScatterWidgetItem>
#include <Q3DSurfaceWidgetItem>
#endif

void checkQt6GraphsWidgets(SmokeReporter &r)
{
    r.check("graphs/legend-data", [&r](QString &d) {
#ifdef SMOKE_HAVE_GRAPHS
        // A gadget, not a QObject: three fields a series fills in for whatever
        // draws the legend. Copyable and list-friendly like any value type.
        QLegendData legend;
        legend.color = QColor(Qt::red);
        legend.borderColor = QColor(Qt::black);
        legend.label = QStringLiteral("Series 1");
        const QLegendData copy = legend;
        QList<QLegendData> list;
        list.append(legend);
        d = QStringLiteral("\"%1\" %2 on %3, %4 in a list")
                .arg(copy.label).arg(copy.color.name()).arg(copy.borderColor.name())
                .arg(list.size());
        return copy.label == QStringLiteral("Series 1")
            && copy.color == QColor(Qt::red) && copy.borderColor == QColor(Qt::black)
            && list.size() == 1 && list.at(0).label == legend.label;
#else
#ifdef SMOKE_GRAPHS_STATIC_SYMBOL_COLLISION
        r.skip(d, QStringLiteral("static QtCharts and QtGraphs export colliding QValueAxis symbols"));
#else
        r.skip(d, QStringLiteral("QtGraphs is not in this SDK"));
#endif
        return false;
#endif
    });

    r.check("graphs/widget-items", [&r](QString &d) {
#ifdef SMOKE_HAVE_GRAPHSWIDGETS
        Q3DBarsWidgetItem bars;
        Q3DScatterWidgetItem scatter;
        Q3DSurfaceWidgetItem surface;
        Q3DGraphsWidgetItem *asBase = &bars;
        d = QStringLiteral("%1, %2 and %3 over %4, widget %5")
                .arg(QString::fromLatin1(bars.metaObject()->className()))
                .arg(QString::fromLatin1(scatter.metaObject()->className()))
                .arg(QString::fromLatin1(surface.metaObject()->className()))
                .arg(QString::fromLatin1(Q3DGraphsWidgetItem::staticMetaObject.className()))
                .arg(bars.widget() ? QLatin1String("attached") : QLatin1String("null"));
        return asBase == &bars && bars.widget() == nullptr
            && bars.metaObject()->inherits(&Q3DGraphsWidgetItem::staticMetaObject)
            && scatter.metaObject()->inherits(&Q3DGraphsWidgetItem::staticMetaObject)
            && surface.metaObject()->inherits(&Q3DGraphsWidgetItem::staticMetaObject);
#else
#ifdef SMOKE_GRAPHS_STATIC_SYMBOL_COLLISION
        r.skip(d, QStringLiteral("QtGraphsWidgets cannot link beside static QtCharts"));
#else
        r.skip(d, QStringLiteral("QtGraphsWidgets is not in this SDK"));
#endif
        return false;
#endif
    });
}
