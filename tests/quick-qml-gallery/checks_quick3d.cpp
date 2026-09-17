// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// QtQuick3D's C++-exported classes - almost everything else in the module is
// QML-only types. All of them are constructible headlessly for the same reason:
// they hold data, and nothing asks for an RHI or a GPU context until something
// actually renders them. QQuick3DGeometry holds vertices, QQuick3DTextureData
// holds pixels, and the two abstract ones are hooks Qt calls into rather than
// objects that reach out.
#include "../common/smokecheck.h"

#include <QQuick3DGeometry>
#include <QQuick3DObject>

#if QT_VERSION >= QT_VERSION_CHECK(6, 2, 0)
#  include <QQuick3DInstancing>
#  include <QQuick3DTextureData>
#endif
#if QT_VERSION >= QT_VERSION_CHECK(6, 6, 0)
#  include <QQuick3DRenderExtension>   // RenderExtension, added in 6.6
#endif
#include <QSize>

#ifdef SMOKE_HAVE_QUICK3D_EXTENSIONS
#include <QQuickView>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QCoreApplication>
#include <QElapsedTimer>
#include <QPointer>
#include <QProcess>
#include <QProcessEnvironment>
#include <QThread>

#include <ssg/qquick3dextensionhelpers.h>
#include <ssg/qssgrendercontextcore.h>
#include <ssg/qssgrenderextensions.h>
#include <ssg/qssgrenderhelpers.h>
#include <ssg/qssgrhicontext.h>

#include <atomic>
#include <cstdio>
#include <cstdlib>
#endif

namespace {
// QQuick3DObject::updateSpatialNode() is the one pure virtual - the real hook
// a custom scene-graph-backed item implements (QQuick3DGeometry itself is a
// concrete example of exactly this pattern).
class MinimalQuick3DObject : public QQuick3DObject {
public:
    QSSGRenderGraphObject *updateSpatialNode(QSSGRenderGraphObject *node) override { return node; }
};

#if QT_VERSION >= QT_VERSION_CHECK(6, 2, 0)
// QQuick3DInstancing's one pure virtual is the instance table itself: Qt asks
// for a packed buffer and how many instances are in it. Answering with a fixed
// two-instance table is enough to prove the hook without a renderer.
class TwoInstanceTable : public QQuick3DInstancing {
public:
    QByteArray getInstanceBuffer(int *instanceCount) override
    {
        if (instanceCount)
            *instanceCount = 2;
        m_buffer.fill(char(0), 2 * 96);   // Qt's instance entry is 96 bytes
        return m_buffer;
    }

private:
    QByteArray m_buffer;
};
#endif

#if QT_VERSION >= QT_VERSION_CHECK(6, 6, 0)
// QQuick3DRenderExtension is abstract to QML but not to C++: it implements
// updateSpatialNode() itself, so a subclass need only exist.
class MinimalRenderExtension : public QQuick3DRenderExtension {
};
#endif

#ifdef SMOKE_HAVE_QUICK3D_EXTENSIONS
std::atomic_int extensionPrepareData { 0 };
std::atomic_int extensionPrepareRender { 0 };
std::atomic_int extensionRender { 0 };
std::atomic_int extensionHelpersReached { 0 };
QPointer<QQuick3DObject> extensionModel;

class SmokeRenderBackend final : public QSSGRenderExtension
{
public:
    bool prepareData(QSSGFrameData &data) override
    {
        ++extensionPrepareData;
        QSSGRenderContextInterface *context = data.contextInterface();
        if (!context || !context->rhiContext() || !context->rhiContext()->isValid())
            return false;

        QSSGRhiContext *rhiContext = context->rhiContext().get();
        if (!rhiContext->rhi())
            return false;

        const QSSGCameraId camera = data.activeCamera();
        if (QQuick3DExtensionHelpers::isNull(camera))
            return false;
        const QMatrix4x4 viewProjection = QSSGCameraHelpers::getViewProjectionMatrix(camera);
        Q_UNUSED(viewProjection);

        if (extensionModel) {
            const QSSGNodeId model = QQuick3DExtensionHelpers::getNodeId(*extensionModel);
            if (!QQuick3DExtensionHelpers::isNull(model)) {
                const QMatrix4x4 local = QSSGModelHelpers::getLocalTransform(data, model);
                const float opacity = QSSGModelHelpers::getLocalOpacity(data, model);
                Q_UNUSED(local);
                Q_UNUSED(opacity);

                const QSSGPrepContextId prep = QSSGRenderHelpers::prepareForRender(
                            data, *this, camera);
                const QSSGRenderablesId renderables = QSSGRenderHelpers::createRenderables(
                            data, prep, { model });
                const QSSGPrepResultId result = QSSGRenderHelpers::commit(
                            data, prep, renderables);
                if (result != QSSGPrepResultId::Invalid)
                    ++extensionHelpersReached;
            }
        }
        return true;
    }

    void prepareRender(QSSGFrameData &data) override
    {
        if (data.contextInterface() && data.contextInterface()->rhiContext())
            ++extensionPrepareRender;
    }

    void render(QSSGFrameData &data) override
    {
        const QSSGExtensionId id = QQuick3DExtensionHelpers::getExtensionId(*front);
        const QSSGFrameData::Result depth = data.getRenderResult(
                    QSSGFrameData::RenderResult::DepthTexture);
        if (!QQuick3DExtensionHelpers::isNull(id) && depth.texture)
            QSSGRenderExtensionHelpers::registerRenderResult(data, id, depth.texture);
        ++extensionRender;
    }

    void resetForFrame() override {}
    RenderMode mode() const override { return RenderMode::Standalone; }
    RenderStage stage() const override { return RenderStage::PostColor; }

    QQuick3DObject *front = nullptr;
};

class SmokeRenderExtension : public QQuick3DRenderExtension
{
public:
    using QQuick3DRenderExtension::QQuick3DRenderExtension;

    QSSGRenderGraphObject *updateSpatialNode(QSSGRenderGraphObject *node) override
    {
        SmokeRenderBackend *backend = static_cast<SmokeRenderBackend *>(node);
        if (!backend)
            backend = new SmokeRenderBackend;
        backend->front = this;
        return backend;
    }
};
#endif
}

int runQuick3DExtensionProbe()
{
#ifdef SMOKE_HAVE_QUICK3D_EXTENSIONS
    static const int registration = qmlRegisterType<SmokeRenderExtension>(
                "SmokeCoverage", 1, 0, "SmokeRenderExtension");
    Q_UNUSED(registration);

    extensionPrepareData = 0;
    extensionPrepareRender = 0;
    extensionRender = 0;
    extensionHelpersReached = 0;
    extensionModel.clear();

    QQuickView view;
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    // As in the native texture probe: a graphics API that cannot be
    // initialized is a skip, not Qt Quick's qFatal.
    QObject::connect(&view, &QQuickWindow::sceneGraphError, &view,
                     [](QQuickWindow::SceneGraphError, const QString &message) {
        std::fprintf(stderr, "%s\n", qPrintable(message));
        std::fflush(stderr);
        std::_Exit(77);
    }, Qt::DirectConnection);
    view.resize(96, 96);
    QQmlComponent component(view.engine());
    component.setData(R"QML(
        import QtQuick
        import QtQuick3D
        import SmokeCoverage 1.0
        View3D {
            width: 96; height: 96
            environment: SceneEnvironment { backgroundMode: SceneEnvironment.Color; clearColor: "black" }
            PerspectiveCamera { z: 200 }
            Model {
                objectName: "coverageModel"
                source: "#Cube"
                materials: DefaultMaterial { diffuseColor: "green" }
            }
            extensions: [ SmokeRenderExtension {} ]
        }
    )QML", QUrl(QStringLiteral("qrc:/coverage-quick3d.qml")));
    if (component.isError())
        return 2;
    QObject *root = component.create();
    if (!root)
        return 3;
    extensionModel = root->findChild<QQuick3DObject *>(QStringLiteral("coverageModel"));
    view.setContent(QUrl(QStringLiteral("qrc:/coverage-quick3d.qml")), &component, root);
    view.show();

    QElapsedTimer timer;
    timer.start();
    QImage frame;
    while (timer.elapsed() < 5000 && extensionRender.load() == 0) {
        frame = view.grabWindow();
        QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
        QThread::msleep(10);
    }
    const bool ok = !frame.isNull() && extensionPrepareData.load() > 0
        && extensionPrepareRender.load() > 0 && extensionRender.load() > 0
        && extensionHelpersReached.load() > 0;
    extensionModel.clear();
    return ok ? 0 : 4;
#else
    return 77;
#endif
}

void checkQuick3D(SmokeReporter &r)
{
    r.check("quick3d/geometry-and-object-base", [&](QString &d) {
        QQuick3DGeometry geometry;
        QByteArray vertices(3 * 3 * sizeof(float), char(0));
        geometry.setVertexData(vertices);
        geometry.setStride(3 * sizeof(float));
        geometry.addAttribute(QQuick3DGeometry::Attribute::PositionSemantic, 0,
                              QQuick3DGeometry::Attribute::F32Type);
        geometry.setPrimitiveType(QQuick3DGeometry::PrimitiveType::Triangles);

        MinimalQuick3DObject object;
        // Reached through the real base every Quick3D scene item derives from.
        QQuick3DObject *asObject = &geometry;

#if QT_VERSION_MAJOR < 6
        return geometry.vertexBuffer() == vertices
#else
        return geometry.vertexData() == vertices   // renamed to match the setter
#endif
            && geometry.primitiveType() == QQuick3DGeometry::PrimitiveType::Triangles
            && asObject != nullptr && object.updateSpatialNode(nullptr) == nullptr;
    });

    r.check("quick3d/instancing-table", [&r](QString &d) {
#if QT_VERSION >= QT_VERSION_CHECK(6, 2, 0)
        // The instance table is pull-based: Qt calls getInstanceBuffer() when it
        // needs one, so a table that is never rendered is never asked, and
        // calling it by hand is exactly what the renderer would do.
        TwoInstanceTable table;
        int count = -1;
        const QByteArray buffer = table.getInstanceBuffer(&count);
        QQuick3DObject *asObject = &table;

        // Set and read back rather than assert a default: the header documents
        // none, and a check that guessed one would be testing this Qt build
        // rather than the class. The defaults are printed instead, so a change
        // to them is visible without being a failure.
        const int defaultOverride = table.instanceCountOverride();
        const bool defaultTransparency = table.hasTransparency();
        table.setInstanceCountOverride(1);
        table.setHasTransparency(true);
        table.setDepthSortingEnabled(true);

        d = QStringLiteral("%1 instances, %2 bytes; defaults override=%3 transparency=%4")
                .arg(count).arg(buffer.size()).arg(defaultOverride).arg(int(defaultTransparency));
        return count == 2 && buffer.size() == 2 * 96 && asObject == &table
            && table.instanceCountOverride() == 1 && table.hasTransparency()
            && table.depthSortingEnabled();
#else
        r.skip(d, QStringLiteral("QQuick3DInstancing is Qt 6.2 and later"));
        return false;
#endif
    });

    r.check("quick3d/texture-data", [&r](QString &d) {
#if QT_VERSION >= QT_VERSION_CHECK(6, 2, 0)
        // Pixels handed to the renderer from C++ rather than loaded from a file.
        // Pure data until something draws with it.
        QQuick3DTextureData texture;
        QByteArray pixels(4 * 2 * 2, char(0));   // 2x2 RGBA8
        texture.setSize(QSize(2, 2));
        texture.setFormat(QQuick3DTextureData::RGBA8);
        texture.setTextureData(pixels);
        texture.setHasTransparency(true);
        d = QStringLiteral("%1x%2, format %3, %4 bytes")
                .arg(texture.size().width()).arg(texture.size().height())
                .arg(int(texture.format())).arg(texture.textureData().size());
        return texture.size() == QSize(2, 2)
            && texture.format() == QQuick3DTextureData::RGBA8
            && texture.textureData().size() == pixels.size()
            && texture.hasTransparency();
#else
        r.skip(d, QStringLiteral("QQuick3DTextureData is Qt 6.2 and later"));
        return false;
#endif
    });

    r.check("quick3d/render-extension", [&r](QString &d) {
#if QT_VERSION >= QT_VERSION_CHECK(6, 6, 0)
        // The seam for injecting custom rendering into a Quick3D view. QML calls
        // it uncreatable; from C++ it is an ordinary QQuick3DObject subclass,
        // and its updateSpatialNode() answers without a renderer.
        MinimalRenderExtension extension;
        QQuick3DObject *asObject = &extension;
        d = QStringLiteral("%1 constructed as a QQuick3DObject")
                .arg(QString::fromLatin1(extension.metaObject()->className()));
        return asObject == &extension
            && extension.updateSpatialNode(nullptr) == nullptr
            && extension.metaObject()->inherits(&QQuick3DObject::staticMetaObject);
#else
        r.skip(d, QStringLiteral("QQuick3DRenderExtension is Qt 6.6 and later"));
        return false;
#endif
    });

    r.check("quick3d/runtime-render-extension-frame", [&](QString &d) {
#ifdef SMOKE_HAVE_QUICK3D_EXTENSIONS
        QProcess child;
        QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
#if defined(Q_OS_UNIX) && !defined(Q_OS_DARWIN) && !defined(Q_OS_ANDROID)
        // The parent may run offscreen; the render probe needs a real X11
        // window. Elsewhere the child keeps the native platform: forcing xcb on
        // Windows or macOS makes Qt stop on a "platform plugin" error dialog.
        environment.insert(QStringLiteral("QT_QPA_PLATFORM"), QStringLiteral("xcb"));
#endif
        child.setProcessEnvironment(environment);
        child.start(QCoreApplication::applicationFilePath(),
                    QStringList() << QStringLiteral("--quick3d-extension-probe"));
        if (!child.waitForStarted(3000) || !child.waitForFinished(10000)) {
            d = QStringLiteral("probe did not finish: %1").arg(child.errorString());
            return false;
        }
        d = QString::fromLocal8Bit(child.readAllStandardError()).trimmed();
        if (child.exitStatus() == QProcess::NormalExit && child.exitCode() == 77) {
            r.skip(d, QStringLiteral("graphics API is unavailable at runtime: ")
                          + d.section(QLatin1Char('\n'), -1));
            return false;
        }
        return child.exitStatus() == QProcess::NormalExit && child.exitCode() == 0;
#else
        r.skip(d, QStringLiteral("Qt Quick 3D runtime render extensions need Qt 6.7+"));
        return false;
#endif
    });
}
