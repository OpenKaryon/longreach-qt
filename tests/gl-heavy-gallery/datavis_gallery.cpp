// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Visual QtDataVisualization tab: Q3DBars/Q3DScatter/Q3DSurface, each embedded
// via createWindowContainer, one per sub-tab - the 3D-chart counterpart of the
// 2D QtCharts tab.
#include "gl-heavy.h"
#include "glcaps.h"

#include <QWidget>
#include <QApplication>
#include <QColor>
#include <QEvent>
#include <QLinearGradient>
#include <QObject>
#include <QPlatformSurfaceEvent>
#include <QTimer>
#include <QList>
#include <QStringList>
#include <QTabWidget>
#include <QVBoxLayout>

#include <QtDataVisualization/Q3DBars>
#include <QtDataVisualization/Q3DScatter>
#include <QtDataVisualization/Q3DSurface>
#include <QtDataVisualization/Q3DTheme>
#include <QtDataVisualization/Q3DCamera>

#include <QtDataVisualization/QAbstract3DSeries>
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

#include <QtMath>

#if QT_VERSION_MAJOR < 6
QT_BEGIN_NAMESPACE
using namespace QtDataVisualization;   // no namespace in Qt 6
QT_END_NAMESPACE
#endif

static QWidget *wrapContainer(QWindow *win, const char *name)
{
    win->setObjectName(QString::fromLatin1(name));
    QObject::connect(win, &QObject::destroyed, win, [name]() {
        qInfo("[datavis] window destroyed: %s", name);
    });
    QObject::connect(qApp, &QCoreApplication::aboutToQuit, win, [win, name]() {
        qInfo("[datavis] aboutToQuit close: %s", name);
        win->hide();
        win->destroy();
    });
    auto *container = QWidget::createWindowContainer(win);
    container->setObjectName(QString::fromLatin1(name) + QStringLiteral("-container"));
    QObject::connect(container, &QObject::destroyed, container, [name]() {
        qInfo("[datavis] container destroyed: %s", name);
    });
    container->setMinimumSize(360, 300);
    return container;
}

static void remarkTheme(Q3DTheme *theme)
{
    theme->setBackgroundColor(theme->backgroundColor());
    theme->setWindowColor(theme->windowColor());
    theme->setGridLineColor(theme->gridLineColor());
    theme->setLabelBackgroundColor(theme->labelBackgroundColor());
    theme->setLabelTextColor(theme->labelTextColor());
    theme->setBackgroundEnabled(theme->isBackgroundEnabled());
    theme->setGridEnabled(theme->isGridEnabled());
    theme->setLightColor(theme->lightColor());
    theme->setBaseColors(theme->baseColors());
    theme->setColorStyle(theme->colorStyle());
    theme->setLightStrength(theme->lightStrength());
    theme->setAmbientLightStrength(theme->ambientLightStrength());
}

static void remarkSeries(const QList<QAbstract3DSeries *> &series)
{
    for (QAbstract3DSeries *s : series) {
        const QAbstract3DSeries::Mesh mesh = s->mesh();
        s->setBaseColor(s->baseColor());
        s->setBaseGradient(s->baseGradient());
        s->setColorStyle(s->colorStyle());
        if (!glCaps().surfaceSupported() && s->type() == QAbstract3DSeries::SeriesTypeBar) {
            s->setMesh(mesh == QAbstract3DSeries::MeshCube
                       ? QAbstract3DSeries::MeshBevelBar
                       : QAbstract3DSeries::MeshCube);
        }
        s->setMesh(mesh);
        s->setMeshSmooth(s->isMeshSmooth());
    }
}

// Asks a graph to repaint after its tab is shown again. QAbstract3DGraph
// renders from exposeEvent() and skips the frame when the window does not yet
// count as exposed (seen on Mesa 10.0 / SVGA3D: the old frame stayed on
// screen), so request an update now and once more shortly after.
class GraphRepainter : public QObject
{
public:
    explicit GraphRepainter(QAbstract3DGraph *graph, const QList<QAbstract3DSeries *> &series)
        : QObject(graph), m_graph(graph), m_series(series) { graph->installEventFilter(this); }
    ~GraphRepainter() override
    {
        qInfo("[datavis] repainter destroyed: %s", qPrintable(m_graph->objectName()));
    }

protected:
    bool eventFilter(QObject *watched, QEvent *event) override
    {
        const char *name = 0;
        switch (event->type()) {
        case QEvent::Expose:            name = "expose";   break;
        case QEvent::Show:              name = "show";     break;
        case QEvent::Hide:              name = "hide";     break;
        case QEvent::PlatformSurface:   name = "surface";  break;
        default: break;
        }

        if (name && m_graph->activeTheme()) {
            Q3DTheme *theme = m_graph->activeTheme();
            const char *detail = "";
            if (event->type() == QEvent::PlatformSurface) {
                detail = static_cast<QPlatformSurfaceEvent *>(event)->surfaceEventType()
                        == QPlatformSurfaceEvent::SurfaceCreated
                        ? " created" : " ABOUT TO BE DESTROYED";
            }
            // qInfo, not printf: keep these events in Qt's normal diagnostic
            // stream next to the driver's own output. The point is which shader
            // re-inits fall between which window events.
            qInfo("[datavis] %s%s: background=%s light=%s ambient=%.2f strength=%.2f theme=%d",
                  name, detail,
                  qPrintable(theme->backgroundColor().name()),
                  qPrintable(theme->lightColor().name()),
                  double(theme->ambientLightStrength()),
                  double(theme->lightStrength()),
                  int(theme->type()));
        }

        if (event->type() == QEvent::Show || event->type() == QEvent::Expose) {
            if (m_graph->activeTheme())
                remarkTheme(m_graph->activeTheme());
            remarkSeries(m_series);
            m_graph->requestUpdate();
            QTimer::singleShot(200, m_graph, [this]() {
                if (m_graph->activeTheme())
                    remarkTheme(m_graph->activeTheme());
                remarkSeries(m_series);
                m_graph->requestUpdate();
            });
        }
        return QObject::eventFilter(watched, event);
    }

private:
    QAbstract3DGraph *m_graph;
    QList<QAbstract3DSeries *> m_series;
};

// Settings every graph shares. Shadows are None from the start:
// QtDataVisualization would otherwise reject them asynchronously on drivers it
// takes for ES2 and reconfigure the graph a frame later.
static void applyPortableDefaults(QAbstract3DGraph *graph, const QColor &window)
{
    graph->setShadowQuality(QAbstract3DGraph::ShadowQualityNone);

    Q3DTheme *theme = graph->activeTheme();
    // Mesa 10.0 / SVGA3D can draw the background box black after the window is
    // shown again; the box is decorative, so it is left out there.
    theme->setBackgroundEnabled(glCaps().surfaceSupported());
    theme->setGridEnabled(true);
    theme->setWindowColor(window);

}

static QWidget *makeBarsTab()
{
    auto *graph = new Q3DBars;
    graph->activeTheme()->setType(glCaps().surfaceSupported()
                                  ? Q3DTheme::ThemeQt
                                  : Q3DTheme::ThemeDigia);
    applyPortableDefaults(graph, QColor(240, 240, 240));

    auto *series = new QBar3DSeries;
    QBarDataArray *data = new QBarDataArray;
    const QStringList rowLabels = {"r0", "r1", "r2", "r3"};
    const QStringList columnLabels = {"c0", "c1", "c2", "c3", "c4"};
    for (int row = 0; row < 4; ++row) {
        QBarDataRow *dataRow = new QBarDataRow;
        for (int col = 0; col < 5; ++col)
            *dataRow << QBarDataItem(qreal((row + 1) * (col + 1)));
        *data << dataRow;
    }
    series->dataProxy()->resetArray(data, rowLabels, columnLabels);
    if (!glCaps().surfaceSupported()) {
        Q3DTheme *theme = graph->activeTheme();
        QLinearGradient greenBars;
        greenBars.setColorAt(0.0, QColor(125, 210, 80));
        greenBars.setColorAt(0.55, QColor(180, 255, 115));
        greenBars.setColorAt(1.0, QColor(220, 255, 170));
        theme->setColorStyle(Q3DTheme::ColorStyleRangeGradient);
        theme->setBaseGradients(QList<QLinearGradient>() << greenBars);
        theme->setLightColor(Qt::white);
        theme->setLightStrength(1.0f);
        theme->setAmbientLightStrength(0.65f);
        // Known issue: on Mesa 10.0 / SVGA3D Q3DBars draws no axis labels, while
        // Q3DScatter, on the same path, does. Label text, colours, backgrounds and a
        // larger font change nothing; the difference is inside Bars3DRenderer's label
        // drawing.
        theme->setLabelTextColor(QColor(25, 25, 25));
        theme->setLabelBackgroundColor(QColor(255, 255, 255, 180));
        theme->setLabelBackgroundEnabled(true);
        theme->setLabelBorderEnabled(false);
        series->setBaseColor(QColor(180, 255, 115));
        series->setBaseGradient(greenBars);
        series->setColorStyle(Q3DTheme::ColorStyleRangeGradient);
    }
    graph->addSeries(series);
    new GraphRepainter(graph, QList<QAbstract3DSeries *>() << series);

    auto *columnAxis = new QCategory3DAxis;
    columnAxis->setTitle("column");
    columnAxis->setLabelAutoRotation(30.0f);
    columnAxis->setTitleVisible(true);
    columnAxis->setLabels(columnLabels);
    graph->setColumnAxis(columnAxis);

    auto *rowAxis = new QCategory3DAxis;
    rowAxis->setTitle("row");
    rowAxis->setLabelAutoRotation(30.0f);
    rowAxis->setTitleVisible(true);
    rowAxis->setLabels(rowLabels);
    graph->setRowAxis(rowAxis);

    auto *valueAxis = new QValue3DAxis;
    valueAxis->setTitle("value");
    valueAxis->setLabelAutoRotation(30.0f);
    valueAxis->setTitleVisible(true);
    valueAxis->setLabelFormat("%.0f");
    valueAxis->setSegmentCount(4);
    valueAxis->setSubSegmentCount(1);
    valueAxis->setRange(0, 20);
    graph->setValueAxis(valueAxis);

    graph->scene()->activeCamera()->setCameraPreset(Q3DCamera::CameraPresetIsometricLeftHigh);
    graph->scene()->activeCamera()->setZoomLevel(95.0f);

    return wrapContainer(graph, "bars");
}

static QWidget *makeScatterTab()
{
    auto *graph = new Q3DScatter;
    graph->activeTheme()->setType(Q3DTheme::ThemeDigia);
    applyPortableDefaults(graph, QColor(230, 233, 238));

    auto *series = new QScatter3DSeries;
    QScatterDataArray data;
    for (int i = 0; i < 60; ++i)
        data << QScatterDataItem(QVector3D(qSin(i * 0.3) * 5, (i % 10) * 0.5, qCos(i * 0.3) * 5));
    series->dataProxy()->addItems(data);
    graph->addSeries(series);
    new GraphRepainter(graph, QList<QAbstract3DSeries *>() << series);

    graph->scene()->activeCamera()->setCameraPreset(Q3DCamera::CameraPresetFront);

    return wrapContainer(graph, "scatter");
}

static QWidget *makeSurfaceTab()
{
    // Q3DSurface needs more than a GL 2.1 context, and where its shader fails the
    // other graphs sharing the context stop drawing too, so it is not built there.
    if (!glCaps().surfaceSupported()) {
        QStringList missing;
        if (glCaps().vertexTextureUnits <= 0)
            missing << QStringLiteral("vertex texture fetch (GL_MAX_VERTEX_TEXTURE_IMAGE_UNITS is 0)");
        if (!glCaps().gpuShader4)
            missing << QStringLiteral("the flat qualifier (GL_EXT_gpu_shader4 is absent)");
        return makeUnsupportedPlaceholder(
            QStringLiteral("Q3DSurface is not available on this driver"),
            QStringLiteral("The surface graph samples textures in the vertex stage and shades "
                           "flat, and this driver offers neither: %1.\n\n"
                           "Bars and Scatter on the other sub-tabs do not need either and are "
                           "unaffected. Building the graph anyway would take them down with it, "
                           "so it is left out rather than shown broken.")
                .arg(missing.join(QStringLiteral(", and "))));
    }

    auto *graph = new Q3DSurface;
    graph->activeTheme()->setType(Q3DTheme::ThemeEbony);
    applyPortableDefaults(graph, QColor(24, 24, 28));

    auto *series = new QSurface3DSeries;
    QSurfaceDataArray *data = new QSurfaceDataArray;
    const int n = 20;
    for (int i = 0; i < n; ++i) {
        QSurfaceDataRow *row = new QSurfaceDataRow;
        for (int j = 0; j < n; ++j) {
            float x = i - n / 2.0f, z = j - n / 2.0f;
            *row << QSurfaceDataItem(QVector3D(x, qSin(x * 0.4f) * qCos(z * 0.4f) * 3.0f, z));
        }
        *data << row;
    }
    series->dataProxy()->resetArray(data);
    graph->addSeries(series);
    new GraphRepainter(graph, QList<QAbstract3DSeries *>() << series);

    return wrapContainer(graph, "surface");
}

QWidget *buildDataVisTab()
{
    auto *tabs = new QTabWidget;
    tabs->addTab(makeBarsTab(), "Bars (Q3DBars)");
    tabs->addTab(makeScatterTab(), "Scatter (Q3DScatter)");
    if (!glCaps().surfaceSupported()) {
        tabs->addTab(makeUnsupportedPlaceholder(
            QStringLiteral("Q3DSurface visual graph is disabled on this OpenGL driver"),
            QStringLiteral("Bars and Scatter remain available. Q3DSurface needs "
                           "OpenGL features this driver does not provide, and "
                           "opening it can leave the sibling DataVisualization "
                           "graphs in a broken GL state.")),
            "Surface (Q3DSurface)");
    } else {
        tabs->addTab(makeSurfaceTab(), "Surface (Q3DSurface)");
    }
    return tabs;
}
