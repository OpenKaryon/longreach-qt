// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Visual QtCharts tab: a QTabWidget of QChartViews, one per chart family, so
// the whole series/axis catalogue is visible - line/spline/scatter/area,
// every bar-series flavour, pie, boxplot, candlestick, and a polar chart.
#include "gl-heavy.h"

#include <QWidget>
#include <QTabWidget>
#include <QVBoxLayout>

#include <QtCharts/QChart>
#include <QtCharts/QChartView>
#include <QtCharts/QLegend>

#include <QtCharts/QLineSeries>
#include <QtCharts/QSplineSeries>
#include <QtCharts/QScatterSeries>
#include <QtCharts/QAreaSeries>

#include <QtCharts/QBarSeries>
#include <QtCharts/QHorizontalBarSeries>
#include <QtCharts/QStackedBarSeries>
#include <QtCharts/QHorizontalStackedBarSeries>
#include <QtCharts/QPercentBarSeries>
#include <QtCharts/QHorizontalPercentBarSeries>
#include <QtCharts/QBarSet>

#include <QtCharts/QPieSeries>
#include <QtCharts/QPieSlice>

#include <QtCharts/QBoxPlotSeries>
#include <QtCharts/QBoxSet>

#include <QtCharts/QCandlestickSeries>
#include <QtCharts/QCandlestickSet>

#include <QtCharts/QPolarChart>

#include <QtCharts/QValueAxis>
#include <QtCharts/QBarCategoryAxis>
#include <QtCharts/QCategoryAxis>
#include <QtCharts/QDateTimeAxis>
#include <QtCharts/QLogValueAxis>

#include <QtMath>
#include <QVector>

#if QT_VERSION_MAJOR < 6
QT_CHARTS_USE_NAMESPACE   // Qt 6 does not put QtCharts in a namespace
#endif

static QChartView *makeXYChart()
{
    auto *chart = new QChart;
    chart->setTitle("Line / Spline / Scatter / Area");

    auto *line = new QLineSeries; line->setName("line");
    auto *spline = new QSplineSeries; spline->setName("spline");
    auto *scatter = new QScatterSeries; scatter->setName("scatter");
    for (int i = 0; i <= 20; ++i) {
        qreal x = i;
        line->append(x, qSin(x / 3.0) * 10 + 15);
        spline->append(x, qCos(x / 3.0) * 8 + 30);
        scatter->append(x, (i % 5) * 3 + 5);
    }
    auto *areaUpper = new QLineSeries;
    for (int i = 0; i <= 20; ++i) areaUpper->append(i, qSin(i / 4.0) * 4 + 42);
    auto *area = new QAreaSeries(areaUpper);
    area->setName("area");

    chart->addSeries(line);
    chart->addSeries(spline);
    chart->addSeries(scatter);
    chart->addSeries(area);
    chart->createDefaultAxes();
    chart->legend()->setVisible(true);
    chart->legend()->setAlignment(Qt::AlignBottom);

    return new QChartView(chart);
}

static QChartView *makeBarChart()
{
    auto *chart = new QChart;
    chart->setTitle("Bar series catalogue (grouped/stacked/percent x horizontal)");

    auto *set1 = new QBarSet("2024"); *set1 << 4 << 6 << 8 << 5;
    auto *set2 = new QBarSet("2025"); *set2 << 5 << 7 << 6 << 9;

    auto *grouped = new QBarSeries; grouped->append(set1); grouped->append(set2);
    chart->addSeries(grouped);

    auto *catAxis = new QBarCategoryAxis;
    catAxis->append({"Q1", "Q2", "Q3", "Q4"});
    chart->addAxis(catAxis, Qt::AlignBottom);
    grouped->attachAxis(catAxis);

    auto *valueAxis = new QValueAxis;
    valueAxis->setRange(0, 12);
    chart->addAxis(valueAxis, Qt::AlignLeft);
    grouped->attachAxis(valueAxis);

    chart->legend()->setVisible(true);

    // The remaining bar-series flavours are constructed (not all plotted, to
    // keep one legible chart) so the classes are exercised for real.
    QVector<QAbstractBarSeries *> extraBarSeries;
    extraBarSeries << new QHorizontalBarSeries << new QStackedBarSeries
                   << new QHorizontalStackedBarSeries << new QPercentBarSeries
                   << new QHorizontalPercentBarSeries;
    for (QAbstractBarSeries *s : extraBarSeries) {
        auto *bs = new QBarSet("x"); *bs << 1 << 2 << 3;
        s->append(bs);
        s->setParent(chart);   // keep them alive, off the visible chart
    }

    return new QChartView(chart);
}

static QChartView *makePieChart()
{
    auto *chart = new QChart;
    chart->setTitle("Pie");
    auto *series = new QPieSeries;
    series->append("Apples", 30);
    series->append("Bananas", 20);
    QPieSlice *cherries = series->append("Cherries", 15);
    cherries->setExploded(true);
    cherries->setLabelVisible(true);
    series->append("Dates", 35);
    chart->addSeries(series);
    chart->legend()->setVisible(true);
    return new QChartView(chart);
}

static QChartView *makeBoxPlotAndCandlestick()
{
    auto *chart = new QChart;
    chart->setTitle("Box plot + candlestick");

    auto *box = new QBoxPlotSeries; box->setName("distribution");
    auto *set = new QBoxSet("A");
    set->setValue(QBoxSet::LowerExtreme, 2);
    set->setValue(QBoxSet::LowerQuartile, 4);
    set->setValue(QBoxSet::Median, 6);
    set->setValue(QBoxSet::UpperQuartile, 8);
    set->setValue(QBoxSet::UpperExtreme, 10);
    box->append(set);
    chart->addSeries(box);

    auto *candle = new QCandlestickSeries; candle->setName("ohlc");
    auto *c1 = new QCandlestickSet(1, 5, 0.5, 3, 0);
    auto *c2 = new QCandlestickSet(3, 6, 2, 5, 1000);
    candle->append({ c1, c2 });
    candle->setParent(chart);   // constructed for coverage, not plotted alongside box

    chart->createDefaultAxes();
    chart->legend()->setVisible(true);
    return new QChartView(chart);
}

static QChartView *makePolarChart()
{
    auto *chart = new QPolarChart;
    chart->setTitle("Polar + log axis");
    auto *series = new QLineSeries;
    for (int i = 0; i <= 360; i += 10) series->append(i, 1 + qAbs(qSin(qDegreesToRadians(qreal(i * 2)))) * 9);
    chart->addSeries(series);

    auto *angular = new QValueAxis; angular->setRange(0, 360); angular->setTickCount(9);
    chart->addAxis(angular, QPolarChart::PolarOrientationAngular);
    series->attachAxis(angular);

    auto *radial = new QLogValueAxis; radial->setRange(1, 10); radial->setBase(10);
    chart->addAxis(radial, QPolarChart::PolarOrientationRadial);
    series->attachAxis(radial);

    // Constructed for the catalogue - QDateTimeAxis and QCategoryAxis are not
    // needed by this chart's data, but touching the classes is the point.
    auto *dtAxis = new QDateTimeAxis(chart);
    dtAxis->setFormat("yyyy-MM-dd");
    auto *catAxis = new QCategoryAxis(chart);
    catAxis->append("low", 3);
    catAxis->append("high", 9);

    return new QChartView(chart);
}

QWidget *buildChartsTab()
{
    auto *tabs = new QTabWidget;
    tabs->addTab(makeXYChart(), "Line/Spline/Scatter/Area");
    tabs->addTab(makeBarChart(), "Bar");
    tabs->addTab(makePieChart(), "Pie");
    tabs->addTab(makeBoxPlotAndCandlestick(), "BoxPlot/Candlestick");
    tabs->addTab(makePolarChart(), "Polar");
    return tabs;
}
