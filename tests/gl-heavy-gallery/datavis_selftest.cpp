// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Headless QtDataVisualization checks. Q3DBars/Q3DScatter/Q3DSurface derive
// from QWindow but do not create a native surface until shown, so they can be
// constructed and wired (series, proxies, themes, axes) headlessly - same
// approach as the Qt3D checks.
#include "../common/smokecheck.h"
#include "gl-heavy.h"

#include <QOffscreenSurface>
#include <QOpenGLContext>

#include <QtDataVisualization/Q3DBars>
#include <QtDataVisualization/Q3DScatter>
#include <QtDataVisualization/Q3DSurface>
#include <QtDataVisualization/Q3DTheme>
#include <QtDataVisualization/Q3DCamera>
#include <QtDataVisualization/Q3DScene>
#include <QtDataVisualization/Q3DInputHandler>

#include <QtDataVisualization/QBar3DSeries>
#include <QtDataVisualization/QBarDataProxy>
#include <QtDataVisualization/QBarDataItem>
#include <QtDataVisualization/QCategory3DAxis>
#include <QtDataVisualization/QValue3DAxis>

#include <QtDataVisualization/QScatter3DSeries>
#include <QtDataVisualization/QScatterDataProxy>
#include <QtDataVisualization/QScatterDataItem>

#include <QtDataVisualization/QSurface3DSeries>
#include <QtDataVisualization/QSurfaceDataProxy>
#include <QtDataVisualization/QSurfaceDataItem>
#include <QtDataVisualization/QHeightMapSurfaceDataProxy>

#include <QtDataVisualization/QCustom3DItem>
#include <QtDataVisualization/QCustom3DLabel>
#include <QtDataVisualization/QCustom3DVolume>

#include <QtDataVisualization/Q3DLight>
#include <QtDataVisualization/Q3DObject>
#include <QtDataVisualization/QAbstract3DAxis>
#include <QtDataVisualization/QAbstract3DSeries>
#include <QtDataVisualization/QAbstractDataProxy>
#include <QtDataVisualization/QAbstract3DInputHandler>
#include <QtDataVisualization/QTouch3DInputHandler>
#include <QtDataVisualization/QValue3DAxisFormatter>
#include <QtDataVisualization/QLogValue3DAxisFormatter>
#include <QtDataVisualization/QItemModelBarDataProxy>
#include <QtDataVisualization/QItemModelScatterDataProxy>
#include <QtDataVisualization/QItemModelSurfaceDataProxy>

#include <QStandardItemModel>

#if QT_VERSION_MAJOR < 6
QT_BEGIN_NAMESPACE
using namespace QtDataVisualization;   // no namespace in Qt 6
QT_END_NAMESPACE
#endif

namespace {

// The graphs need a live OpenGL context of at least 2.1: without one
// addSeries() crashes on a null renderer, and with a format reporting less
// than 2.1 DataVisualization calls qFatal() (Qt 5's offscreen plugin on GLX
// reports 2.0 whatever the driver gives). Returns the reason they cannot run,
// or an empty string.
QString glContextProblem()
{
    QOpenGLContext context;
    if (!context.create())
        return QStringLiteral("Q3D* graphs need a live OpenGL context");
    QOffscreenSurface surface;
    surface.setFormat(context.format());
    surface.create();
    if (!surface.isValid() || !context.makeCurrent(&surface))
        return QStringLiteral("Q3D* graphs need a live OpenGL context");
    const QSurfaceFormat format = context.format();
    const bool es = context.isOpenGLES();
    context.doneCurrent();
#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0)
    // Checked against Qt 5.15's abstract3drenderer.cpp and texturehelper.cpp.
    if (!es && qMakePair(format.majorVersion(), format.minorVersion()) < qMakePair(2, 1))
        return QStringLiteral("QtDataVisualization needs OpenGL 2.1 and aborts below it; "
                              "this context reports %1.%2")
                .arg(format.majorVersion()).arg(format.minorVersion());
#else
    Q_UNUSED(format)
    Q_UNUSED(es)
#endif
    return QString();
}

} // namespace

void checkDataVis(SmokeReporter &r)
{
    const QString glProblem = glContextProblem();
    if (!glProblem.isEmpty()) {
        // One skip for the group rather than a crash: every check below builds
        // a Q3D* graph, so there is nothing left to exercise without a context.
        r.check("datavis/graphs", [&](QString &d) {
            r.skip(d, glProblem);
            return false;
        });
        return;
    }

    r.check("datavis/bars-series-proxy", [&](QString &d) {
        Q3DBars graph;
        auto *series = new QBar3DSeries;
        auto *data = new QBarDataArray;
        auto *row = new QBarDataRow; *row << QBarDataItem(1.0) << QBarDataItem(2.0);
        *data << row;
        series->dataProxy()->resetArray(data);
        graph.addSeries(series);
        if (graph.seriesList().size() != 1) { d = "series not added"; return false; }
        return series->dataProxy()->rowCount() == 1 && series->dataProxy()->rowAt(0)->size() == 2;
    });
    r.check("datavis/bars-axes", [&](QString &d) {
        Q3DBars graph;
        auto *rowAxis = new QCategory3DAxis;
        rowAxis->setLabels({"a", "b"});
        graph.setRowAxis(rowAxis);
        auto *valueAxis = new QValue3DAxis;
        valueAxis->setRange(0, 50);
        graph.setValueAxis(valueAxis);
        return graph.rowAxis() == rowAxis && graph.valueAxis() == valueAxis
            && qFuzzyCompare(valueAxis->max(), 50.0f);
    });
    r.check("datavis/scatter-series-proxy", [&](QString &d) {
        Q3DScatter graph;
        auto *series = new QScatter3DSeries;
        QScatterDataArray items;
        items << QScatterDataItem(QVector3D(0, 0, 0)) << QScatterDataItem(QVector3D(1, 1, 1));
        series->dataProxy()->addItems(items);
        graph.addSeries(series);
        return series->dataProxy()->itemCount() == 2 && graph.seriesList().contains(series);
    });
    r.check("datavis/surface-series-proxy", [&](QString &d) {
        Q3DSurface graph;
        auto *series = new QSurface3DSeries;
        auto *data = new QSurfaceDataArray;
        for (int i = 0; i < 3; ++i) {
            auto *row = new QSurfaceDataRow;
            for (int j = 0; j < 3; ++j) *row << QSurfaceDataItem(QVector3D(i, 0, j));
            *data << row;
        }
        series->dataProxy()->resetArray(data);
        graph.addSeries(series);
        return series->dataProxy()->rowCount() == 3 && series->dataProxy()->columnCount() == 3;
    });
    r.check("datavis/theme-camera-scene", [&](QString &d) {
        Q3DSurface graph;
        graph.activeTheme()->setType(Q3DTheme::ThemeRetro);
        graph.activeTheme()->setBackgroundEnabled(false);
        graph.scene()->activeCamera()->setCameraPreset(Q3DCamera::CameraPresetIsometricLeft);
        return graph.activeTheme()->type() == Q3DTheme::ThemeRetro
            && !graph.activeTheme()->isBackgroundEnabled()
            && graph.scene()->activeCamera()->cameraPreset() == Q3DCamera::CameraPresetIsometricLeft;
    });
    r.check("datavis/input-handler", [&](QString &d) {
        Q3DScatter graph;
        auto *handler = new Q3DInputHandler;
        graph.setActiveInputHandler(handler);
        return graph.activeInputHandler() == handler;
    });
    r.check("datavis/custom-item-label", [&](QString &d) {
        Q3DSurface graph;
        auto *item = new QCustom3DItem;
        item->setPosition(QVector3D(1, 1, 1));
        item->setScaling(QVector3D(0.5f, 0.5f, 0.5f));
        graph.addCustomItem(item);
        auto *label = new QCustom3DLabel;
        label->setText("peak");
        label->setPosition(QVector3D(0, 2, 0));
        graph.addCustomItem(label);
        return graph.customItems().size() == 2 && item->position() == QVector3D(1, 1, 1)
            && label->text() == "peak";
    });
    r.check("datavis/heightmap-proxy", [&](QString &d) {
        auto *proxy = new QHeightMapSurfaceDataProxy;
        proxy->setValueRanges(-1, 1, -1, 1);
        bool ok = qFuzzyCompare(proxy->minXValue(), -1.0f) && qFuzzyCompare(proxy->maxZValue(), 1.0f);
        delete proxy;
        return ok;
    });
    r.check("datavis/light-and-object-base", [&](QString &d) {
        Q3DScene scene;
        auto *light = new Q3DLight(&scene);
        light->setAutoPosition(true);
        // Reached through the real base every scene object derives from.
        Q3DObject *asObject = light;
        return light->isAutoPosition() && asObject->parentScene() == &scene;
    });
    r.check("datavis/abstract-bases-via-concrete", [&](QString &d) {
        auto *valueAxis = new QValue3DAxis;
        auto *barSeries = new QBar3DSeries;
        auto *barProxy = new QBarDataProxy;
        barSeries->setDataProxy(barProxy);
        // Reached through the real bases every concrete axis/series/proxy
        // type derives from.
        QAbstract3DAxis *axisBase = valueAxis;
        QAbstract3DSeries *seriesBase = barSeries;
        QAbstractDataProxy *proxyBase = barSeries->dataProxy();
        bool ok = axisBase->type() == QAbstract3DAxis::AxisTypeValue
            && seriesBase->type() == QAbstract3DSeries::SeriesTypeBar
            && proxyBase->type() == QAbstractDataProxy::DataTypeBar;
        delete valueAxis; delete barSeries;
        return ok;
    });
    r.check("datavis/touch-input-handler-base", [&](QString &d) {
        Q3DScatter graph;
        auto *touch = new QTouch3DInputHandler;
        graph.setActiveInputHandler(touch);
        // Reached through the real base every input handler derives from.
        QAbstract3DInputHandler *base = touch;
        return graph.activeInputHandler() == touch && base->inputView() == touch->inputView();
    });
    r.check("datavis/axis-formatters", [&](QString &d) {
        auto *linearFormatter = new QValue3DAxisFormatter;
        auto *logFormatter = new QLogValue3DAxisFormatter;
        logFormatter->setBase(10.0);
        QValue3DAxis axis;
        axis.setFormatter(linearFormatter);
        bool ok = axis.formatter() == linearFormatter && qFuzzyCompare(logFormatter->base(), 10.0);
        delete logFormatter;
        return ok;
    });
    r.check("datavis/custom-volume", [&](QString &d) {
        auto *volume = new QCustom3DVolume;
        volume->setPosition(QVector3D(0, 0, 0));
        volume->setScaling(QVector3D(1, 1, 1));
        volume->setTextureWidth(2); volume->setTextureHeight(2); volume->setTextureDepth(1);
        QVector<uchar> *texData = new QVector<uchar>(2 * 2 * 1 * 4, uchar(255));
        volume->setTextureData(texData);
        bool ok = volume->textureWidth() == 2 && volume->textureData()->size() == 16;
        delete volume;
        return ok;
    });
    r.check("datavis/itemmodel-bar-scatter-surface-proxies", [&](QString &d) {
        QStandardItemModel model(2, 2);
        for (int row = 0; row < 2; ++row)
            for (int col = 0; col < 2; ++col)
                model.setData(model.index(row, col), (row + 1) * (col + 1));

        QItemModelBarDataProxy barProxy(&model, QStringLiteral("display"));
        QItemModelScatterDataProxy scatterProxy(&model, QStringLiteral("display"),
                                                QStringLiteral("display"), QStringLiteral("display"));
        QItemModelSurfaceDataProxy surfaceProxy(&model, QStringLiteral("display"));

        return barProxy.itemModel() == &model && scatterProxy.itemModel() == &model
            && surfaceProxy.itemModel() == &model;
    });
}
