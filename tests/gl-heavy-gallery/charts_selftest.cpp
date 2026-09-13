// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Headless QtCharts checks: series/set data manipulation, axis ranges, and -
// since QLegendMarker subclasses have protected constructors and are only
// ever created by QLegend itself - iterating a real legend's markers and
// qobject_cast'ing them by series type, which is the only legitimate way to
// touch those classes.
#include "../common/smokecheck.h"
#include "gl-heavy.h"

#include <QtCharts/QChart>
#if QT_VERSION_MAJOR >= 6
#include <QtCharts/QColorAxis>   // no Qt 5 counterpart
#endif
#include <QtCharts/QLegend>
#include <QtCharts/QLegendMarker>
#include <QtCharts/QXYLegendMarker>
#include <QtCharts/QBarLegendMarker>
#include <QtCharts/QPieLegendMarker>
#include <QtCharts/QAreaLegendMarker>

#include <QtCharts/QLineSeries>
#include <QtCharts/QAreaSeries>
#include <QtCharts/QBarSeries>
#include <QtCharts/QBarSet>
#include <QtCharts/QPieSeries>
#include <QtCharts/QPieSlice>
#include <QtCharts/QBoxPlotSeries>
#include <QtCharts/QBoxSet>
#include <QtCharts/QBoxPlotLegendMarker>
#include <QtCharts/QCandlestickSeries>
#include <QtCharts/QCandlestickSet>
#include <QtCharts/QCandlestickLegendMarker>

#include <QtCharts/QValueAxis>
#include <QtCharts/QBarCategoryAxis>
#include <QtCharts/QAbstractAxis>
#include <QtCharts/QAbstractSeries>
#include <QtCharts/QXYSeries>

#include <QtCharts/QVBarModelMapper>
#include <QtCharts/QHXYModelMapper>
#include <QtCharts/QVPieModelMapper>
#include <QtCharts/QBarModelMapper>
#include <QtCharts/QXYModelMapper>
#include <QtCharts/QPieModelMapper>
#include <QtCharts/QBoxPlotModelMapper>
#include <QtCharts/QVBoxPlotModelMapper>
#include <QtCharts/QHBoxPlotModelMapper>
#include <QtCharts/QCandlestickModelMapper>
#include <QtCharts/QVCandlestickModelMapper>
#include <QtCharts/QHCandlestickModelMapper>
#include <QtCharts/QHBarModelMapper>
#include <QtCharts/QHPieModelMapper>
#include <QtCharts/QVXYModelMapper>

#include <QStandardItemModel>

#if QT_VERSION_MAJOR < 6
QT_CHARTS_USE_NAMESPACE   // Qt 6 does not put QtCharts in a namespace
#endif

void checkCharts(SmokeReporter &r)
{
    r.check("charts/xyseries-append", [&](QString &d) {
        QLineSeries line;
        for (int i = 0; i < 5; ++i) line.append(i, i * i);
        if (line.count() != 5) { d = QString("count=%1").arg(line.count()); return false; }
        // Reached through the real bases every axis/series type derives from.
        QXYSeries *asXY = &line;
        QAbstractSeries *asSeries = &line;
        QValueAxis axis;
        QAbstractAxis *asAxis = &axis;
        return line.at(3) == QPointF(3, 9) && asXY == asSeries
            && asSeries->type() == QAbstractSeries::SeriesTypeLine
            && asAxis->type() == QAbstractAxis::AxisTypeValue;
    });
    r.check("charts/areaseries-wraps-upper", [&](QString &d) {
        auto *upper = new QLineSeries;
        upper->append(0, 0); upper->append(1, 5);
        QAreaSeries area(upper);
        return area.upperSeries() == upper;
    });
    r.check("charts/barset-values", [&](QString &d) {
        QBarSet set("s");
        set << 1 << 2 << 3;
        if (set.count() != 3) { d = QString("count=%1").arg(set.count()); return false; }
        return qFuzzyCompare(set.sum(), 6.0) && qFuzzyCompare(set.at(1), 2.0);
    });
    r.check("charts/barseries-append-set", [&](QString &d) {
        QBarSeries series;
        auto *set = new QBarSet("a"); *set << 1 << 2;
        series.append(set);
        return series.barSets().contains(set) && series.count() == 1;
    });
    r.check("charts/valueaxis-barcategoryaxis-range", [&](QString &d) {
        QValueAxis v; v.setRange(0, 100); v.setTickCount(5);
        QBarCategoryAxis c; c.append({"a", "b", "c"});
        return qFuzzyCompare(v.min(), 0.0) && qFuzzyCompare(v.max(), 100.0)
            && c.categories().size() == 3;
    });
    r.check("charts/pieseries-slices", [&](QString &d) {
        QPieSeries pie;
        pie.append("x", 10);
        pie.append("y", 30);
        if (pie.slices().size() != 2) { d = "slice count"; return false; }
        qreal total = 0;
        for (QPieSlice *s : pie.slices()) total += s->percentage();
        return qAbs(total - 1.0) < 1e-6;
    });
    r.check("charts/boxset-quartiles", [&](QString &d) {
        QBoxSet box;
        box.setValue(QBoxSet::LowerExtreme, 1);
        box.setValue(QBoxSet::Median, 5);
        box.setValue(QBoxSet::UpperExtreme, 9);
        return qFuzzyCompare(box.at(QBoxSet::Median), 5.0);
    });
    r.check("charts/candlestickset-ohlc", [&](QString &d) {
        QCandlestickSet set(1.0, 5.0, 0.5, 3.0, 1000);
        return qFuzzyCompare(set.open(), 1.0) && qFuzzyCompare(set.high(), 5.0)
            && qFuzzyCompare(set.low(), 0.5) && qFuzzyCompare(set.close(), 3.0);
    });
    r.check("charts/legend-markers-by-type", [&](QString &d) {
        auto *chart = new QChart;
        auto *line = new QLineSeries; line->append(0, 0); line->append(1, 1);
        auto *bar = new QBarSeries; auto *bs = new QBarSet("b"); *bs << 1; bar->append(bs);
        auto *pie = new QPieSeries; pie->append("s", 1);
        auto *areaUpper = new QLineSeries; areaUpper->append(0, 0); areaUpper->append(1, 2);
        auto *area = new QAreaSeries(areaUpper);
        chart->addSeries(line);
        chart->addSeries(bar);
        chart->addSeries(pie);
        chart->addSeries(area);
        chart->legend()->setVisible(true);

        int xy = 0, barM = 0, pieM = 0, areaM = 0;
        for (QLegendMarker *m : chart->legend()->markers()) {
            if (qobject_cast<QAreaLegendMarker *>(m)) ++areaM;
            else if (qobject_cast<QXYLegendMarker *>(m)) ++xy;
            else if (qobject_cast<QBarLegendMarker *>(m)) ++barM;
            else if (qobject_cast<QPieLegendMarker *>(m)) ++pieM;
        }
        delete chart;
        if (xy < 1 || barM < 1 || pieM < 1 || areaM < 1) {
            d = QString("xy=%1 bar=%2 pie=%3 area=%4").arg(xy).arg(barM).arg(pieM).arg(areaM);
            return false;
        }
        return true;
    });
    r.check("charts/model-mappers", [&](QString &d) {
        QStandardItemModel model(3, 2);
        for (int row = 0; row < 3; ++row)
            for (int col = 0; col < 2; ++col)
                model.setData(model.index(row, col), (row + 1) * (col + 1));

        auto *barSeries = new QBarSeries;
        auto *barMapper = new QVBarModelMapper;
        barMapper->setModel(&model);
        barMapper->setFirstBarSetColumn(0);
        barMapper->setLastBarSetColumn(1);
        barMapper->setSeries(barSeries);

        auto *xySeries = new QLineSeries;
        auto *xyMapper = new QHXYModelMapper;
        xyMapper->setModel(&model);
        xyMapper->setXRow(0);
        xyMapper->setYRow(1);
        xyMapper->setSeries(xySeries);

        auto *pieSeries = new QPieSeries;
        auto *pieMapper = new QVPieModelMapper;
        pieMapper->setModel(&model);
        pieMapper->setValuesColumn(0);
        pieMapper->setLabelsColumn(1);
        pieMapper->setSeries(pieSeries);

        // Reached through the real bases every V/H model-mapper variant
        // derives from (model()/series() are protected on the base - only
        // the V/H subclasses expose them publicly - so the upcast itself,
        // not a call through it, is what touches the base class here).
        QBarModelMapper *barBase = barMapper;
        QXYModelMapper *xyBase = xyMapper;
        QPieModelMapper *pieBase = pieMapper;

        bool ok = barBase != nullptr && xyBase != nullptr && pieBase != nullptr
               && barMapper->model() == &model && xyMapper->model() == &model
               && pieMapper->model() == &model && barMapper->series() == barSeries
               && xyMapper->series() == xySeries && pieMapper->series() == pieSeries;
        delete barMapper; delete xyMapper; delete pieMapper;
        delete barSeries; delete xySeries; delete pieSeries;
        return ok;
    });
    r.check("charts/remaining-hv-model-mappers", [&](QString &d) {
        // The other half of each V/H model-mapper pair (only one side of
        // each was constructed above).
        QStandardItemModel model(3, 2);
        auto *hBarSeries = new QBarSeries;
        auto *hBarMapper = new QHBarModelMapper;
        hBarMapper->setModel(&model);
        hBarMapper->setSeries(hBarSeries);

        auto *vXySeries = new QLineSeries;
        auto *vXyMapper = new QVXYModelMapper;
        vXyMapper->setModel(&model);
        vXyMapper->setSeries(vXySeries);

        auto *hPieSeries = new QPieSeries;
        auto *hPieMapper = new QHPieModelMapper;
        hPieMapper->setModel(&model);
        hPieMapper->setSeries(hPieSeries);

        bool ok = hBarMapper->model() == &model && hBarMapper->series() == hBarSeries
               && vXyMapper->model() == &model && vXyMapper->series() == vXySeries
               && hPieMapper->model() == &model && hPieMapper->series() == hPieSeries;
        delete hBarMapper; delete vXyMapper; delete hPieMapper;
        delete hBarSeries; delete vXySeries; delete hPieSeries;
        return ok;
    });
    r.check("charts/boxplot-candlestick-model-mappers", [&](QString &d) {
        QStandardItemModel model(5, 4);
        for (int row = 0; row < 5; ++row)
            for (int col = 0; col < 4; ++col)
                model.setData(model.index(row, col), (row + 1) * (col + 1));

        auto *boxSeries = new QBoxPlotSeries;
        auto *boxMapper = new QVBoxPlotModelMapper;
        boxMapper->setModel(&model);
        boxMapper->setFirstBoxSetColumn(0);
        boxMapper->setLastBoxSetColumn(3);
        boxMapper->setSeries(boxSeries);
        auto *hBoxMapper = new QHBoxPlotModelMapper;
        hBoxMapper->setModel(&model);

        auto *candleSeries = new QCandlestickSeries;
        auto *candleMapper = new QVCandlestickModelMapper;
        candleMapper->setModel(&model);
        candleMapper->setOpenRow(0);
        candleMapper->setHighRow(1);
        candleMapper->setLowRow(2);
        candleMapper->setCloseRow(3);
        candleMapper->setSeries(candleSeries);
        auto *hCandleMapper = new QHCandlestickModelMapper;
        hCandleMapper->setModel(&model);

        // Reached through the real bases the V/H box-plot/candlestick
        // mappers derive from.
        QBoxPlotModelMapper *boxBase = boxMapper;
        QCandlestickModelMapper *candleBase = candleMapper;

        bool ok = boxBase != nullptr && candleBase != nullptr
               && boxMapper->model() == &model && boxMapper->series() == boxSeries
               && hBoxMapper->model() == &model
               && candleMapper->model() == &model && candleMapper->series() == candleSeries
               && hCandleMapper->model() == &model;
        delete boxMapper; delete hBoxMapper; delete candleMapper; delete hCandleMapper;
        delete boxSeries; delete candleSeries;
        return ok;
    });
    r.check("charts/boxplot-candlestick-legend-markers", [&](QString &d) {
        auto *chart = new QChart;
        auto *box = new QBoxPlotSeries;
        auto *boxSet = new QBoxSet("box"); boxSet->setValue(QBoxSet::Median, 5);
        box->append(boxSet);
        auto *candle = new QCandlestickSeries;
        candle->append(new QCandlestickSet(1, 5, 0.5, 3, 0));
        chart->addSeries(box);
        chart->addSeries(candle);
        chart->legend()->setVisible(true);

        int boxM = 0, candleM = 0;
        for (QLegendMarker *m : chart->legend()->markers()) {
            if (qobject_cast<QBoxPlotLegendMarker *>(m)) ++boxM;
            else if (qobject_cast<QCandlestickLegendMarker *>(m)) ++candleM;
        }
        delete chart;
        if (boxM < 1 || candleM < 1) { d = QString("box=%1 candle=%2").arg(boxM).arg(candleM); return false; }
        return true;
    });
    r.check("charts/color-axis", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        // A colour axis maps a value range onto a gradient. Qt 5's QtCharts
        // had no such axis type, which is why it appears here rather than in
        // the axis catalogue above.
        QColorAxis colorAxis;
        colorAxis.setMin(0.0);
        colorAxis.setMax(10.0);
        colorAxis.setTickCount(5);
        QAbstractAxis *axisBase = &colorAxis;
        bool ok = qFuzzyCompare(colorAxis.max(), 10.0)
            && colorAxis.tickCount() == 5
            && axisBase->type() == QAbstractAxis::AxisTypeColor;
        if (!ok)
            d = QStringLiteral("colour axis did not keep its range");
        return ok;
#else
        r.skip(d, QStringLiteral("QColorAxis is Qt 6 only"));
        return false;
#endif
    });
}
