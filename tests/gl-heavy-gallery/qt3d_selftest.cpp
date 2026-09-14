// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Headless Qt3D checks. Qt3D's public API is a declarative QNode graph (entity
// / component / material / geometry / framegraph / animation-clip nodes) that
// can be constructed and wired together - parented, given properties, attached
// to entities - without a running QAspectEngine or GPU context. These checks
// build real object graphs and assert on the wiring, the same way the
// widgets-gallery self-test builds real QWidgets without showing a window.
#include "../common/smokecheck.h"
#include "gl-heavy.h"

#include <Qt3DCore/QEntity>
#include <Qt3DCore/QTransform>
#include <Qt3DCore/QAspectEngine>

#if QT_VERSION_MAJOR < 6
#include <Qt3DRender/QGeometry>
#else
#include <Qt3DCore/QGeometry>   // moved out of Qt3DRender in Qt 6
#endif
#include <Qt3DRender/QGeometryRenderer>
#if QT_VERSION_MAJOR < 6
#include <Qt3DRender/QAttribute>
#if QT_VERSION_MAJOR < 6
#include <Qt3DRender/QBuffer>
#else
#include <Qt3DCore/QBuffer>   // promoted to Qt3DCore in Qt 6
#endif
#else
#include <Qt3DCore/QAttribute>   // both moved out of Qt3DRender in Qt 6
#include <Qt3DCore/QBuffer>
#endif
#include <Qt3DRender/QCamera>
#include <Qt3DRender/QCameraLens>
#include <Qt3DRender/QCameraSelector>
#include <Qt3DRender/QViewport>
#include <Qt3DRender/QClearBuffers>
#include <Qt3DRender/QRenderSurfaceSelector>
#include <Qt3DRender/QLayer>
#include <Qt3DRender/QLayerFilter>
#include <Qt3DRender/QTechnique>
#include <Qt3DRender/QEffect>
#include <Qt3DRender/QRenderPass>
#include <Qt3DRender/QShaderProgram>
#include <Qt3DRender/QParameter>
#include <Qt3DRender/QTexture>
#include <Qt3DRender/QTextureImage>
#include <Qt3DRender/QPointLight>
#include <Qt3DRender/QObjectPicker>
#include <Qt3DRender/QMaterial>

#include <Qt3DExtras/QCuboidMesh>
#include <Qt3DExtras/QSphereMesh>
#include <Qt3DExtras/QPhongMaterial>
#include <Qt3DExtras/QPerVertexColorMaterial>
#include <Qt3DExtras/QOrbitCameraController>
#include <Qt3DExtras/QFirstPersonCameraController>

#include <Qt3DInput/QInputAspect>
#include <Qt3DInput/QInputSettings>
#include <Qt3DInput/QMouseDevice>
#include <Qt3DInput/QMouseHandler>
#include <Qt3DInput/QKeyboardDevice>
#include <Qt3DInput/QKeyboardHandler>
#include <Qt3DInput/QAction>
#include <Qt3DInput/QActionInput>
#include <Qt3DInput/QAxis>
#include <Qt3DInput/QAnalogAxisInput>
#include <Qt3DInput/QButtonAxisInput>
#include <Qt3DInput/QLogicalDevice>

#include <Qt3DLogic/QLogicAspect>
#include <Qt3DLogic/QFrameAction>

#include <Qt3DAnimation/QAnimationClip>
#include <Qt3DAnimation/QAnimationClipLoader>
#include <Qt3DAnimation/QChannelMapper>
#include <Qt3DAnimation/QChannelMapping>
#include <Qt3DAnimation/QClipAnimator>
#include <Qt3DAnimation/QAnimationController>
#include <Qt3DAnimation/QAnimationGroup>
#include <Qt3DAnimation/QKeyframeAnimation>

#include <QVector3D>

using namespace Qt3DCore;
using namespace Qt3DRender;
using namespace Qt3DExtras;
using namespace Qt3DInput;
using namespace Qt3DAnimation;

void checkQt3DNodes(SmokeReporter &r)
{
    r.check("qt3d/entity-component-transform", [&](QString &d) {
        QEntity root;
        auto *e = new QEntity(&root);
        auto *t = new Qt3DCore::QTransform;
        t->setTranslation(QVector3D(1, 2, 3));
        t->setScale(2.0f);
        e->addComponent(t);
        if (e->components().size() != 1) { d = "component not attached"; return false; }
        return t->translation() == QVector3D(1, 2, 3) && qFuzzyCompare(t->scale(), 2.0f);
    });
    r.check("qt3d/aspectengine-construct", [&](QString &d) {
        QAspectEngine engine;
        auto *root = new QEntity;
        engine.setRootEntity(Qt3DCore::QEntityPtr(root));
        return engine.rootEntity().data() == root;
    });
    r.check("qt3d/geometry-attribute-buffer", [&](QString &d) {
        // QGeometryRenderer::setGeometry() (and QGeometry::addAttribute(),
        // QAttribute::setBuffer()) take ownership by reparenting - every node
        // here must be heap-allocated, or the eventual delete of the owning
        // node tries to delete a non-heap child and crashes.
        auto *geom = new QGeometry;
        auto *buf = new QBuffer(geom);
        QByteArray data;
        data.resize(3 * 3 * sizeof(float));
        buf->setData(data);
        auto *posAttr = new QAttribute(geom);
        posAttr->setName(QAttribute::defaultPositionAttributeName());
        posAttr->setVertexBaseType(QAttribute::Float);
        posAttr->setVertexSize(3);
        posAttr->setBuffer(buf);
        posAttr->setCount(3);
        geom->addAttribute(posAttr);
        auto *renderer = new QGeometryRenderer;
        renderer->setGeometry(geom);
        renderer->setPrimitiveType(QGeometryRenderer::Triangles);
        bool ok = geom->attributes().size() == 1 && renderer->geometry() == geom
               && posAttr->buffer() == buf && buf->data().size() == (int)(3 * 3 * sizeof(float));
        delete renderer;   // cascades: geom -> buf, posAttr
        return ok;
    });
}

void checkQt3DMaterialsAndMeshes(SmokeReporter &r)
{
    r.check("qt3d/mesh-catalogue", [&](QString &d) {
        QCuboidMesh cuboid; cuboid.setXExtent(2); cuboid.setYExtent(3); cuboid.setZExtent(4);
        QSphereMesh sphere; sphere.setRadius(1.5f); sphere.setRings(16); sphere.setSlices(16);
        return qFuzzyCompare(cuboid.xExtent(), 2.0f) && qFuzzyCompare(sphere.radius(), 1.5f)
            && sphere.rings() == 16;
    });
    r.check("qt3d/material-phong-pervertex", [&](QString &d) {
        QPhongMaterial phong;
        phong.setDiffuse(QColor(200, 60, 60));
        phong.setShininess(50.0);
        QPerVertexColorMaterial perVertex;
        // shininess() is float: a bare 50.0 is double, and clang then finds
        // qFuzzyCompare(float,float) and (double,double) equally good.
        return phong.diffuse() == QColor(200, 60, 60) && qFuzzyCompare(phong.shininess(), 50.0f)
            && perVertex.effect() != nullptr;
    });
    r.check("qt3d/material-effect-technique-pass", [&](QString &d) {
        QMaterial material;
        auto *effect = new QEffect;
        auto *technique = new QTechnique;
        auto *pass = new QRenderPass;
        auto *shader = new QShaderProgram;
        shader->setVertexShaderCode(QByteArrayLiteral("void main() { gl_Position = vec4(0); }"));
        pass->setShaderProgram(shader);
        technique->addRenderPass(pass);
        effect->addTechnique(technique);
        material.setEffect(effect);
        auto *param = new QParameter(QStringLiteral("tint"), QColor(Qt::red));
        material.addParameter(param);
        bool ok = material.effect() == effect && technique->renderPasses().contains(pass)
               && material.parameters().contains(param);
        return ok;
    });
    r.check("qt3d/texture-image", [&](QString &d) {
        auto *tex = new QTexture2D;
        auto *img = new QTextureImage;
        img->setMirrored(false);
        tex->addTextureImage(img);
        tex->setGenerateMipMaps(true);
        bool ok = tex->textureImages().contains(img) && tex->generateMipMaps();
        delete tex;
        return ok;
    });
    r.check("qt3d/camera-lens-controllers", [&](QString &d) {
        QEntity root;
        auto *camera = new QCamera(&root);
        camera->lens()->setPerspectiveProjection(60.0f, 1.777f, 0.1f, 500.0f);
        camera->setPosition(QVector3D(0, 0, 20));
        auto *orbit = new QOrbitCameraController(&root);
        orbit->setCamera(camera);
        auto *fps = new QFirstPersonCameraController(&root);
        fps->setCamera(camera);
        return orbit->camera() == camera && fps->camera() == camera
            && camera->lens()->projectionType() == QCameraLens::PerspectiveProjection;
    });
    r.check("qt3d/light-and-picker", [&](QString &d) {
        QEntity root;
        auto *light = new QPointLight(&root);
        light->setIntensity(0.5f);
        auto *picker = new QObjectPicker(&root);
        picker->setHoverEnabled(true);
        return qFuzzyCompare(light->intensity(), 0.5f) && picker->isHoverEnabled();
    });
}

void checkQt3DFrameGraphAndInput(SmokeReporter &r)
{
    r.check("qt3d/framegraph-tree", [&](QString &d) {
        auto *surfaceSelector = new QRenderSurfaceSelector;
        auto *viewport = new QViewport(surfaceSelector);
        viewport->setNormalizedRect(QRectF(0, 0, 1, 1));
        auto *camSelector = new QCameraSelector(viewport);
        auto *clear = new QClearBuffers(camSelector);
        clear->setBuffers(QClearBuffers::ColorDepthBuffer);
        clear->setClearColor(Qt::black);
        auto *layerFilter = new QLayerFilter(camSelector);
        auto *layer = new QLayer;
        layerFilter->addLayer(layer);
        bool ok = viewport->parent() == surfaceSelector && clear->parent() == camSelector
               && layerFilter->layers().contains(layer);
        delete surfaceSelector;
        return ok;
    });
    r.check("qt3d/input-devices-handlers", [&](QString &d) {
        QEntity root;
        auto *mouseDev = new QMouseDevice(&root);
        auto *mouseHandler = new QMouseHandler(&root);
        mouseHandler->setSourceDevice(mouseDev);
        auto *kbDev = new QKeyboardDevice(&root);
        auto *kbHandler = new QKeyboardHandler(&root);
        kbHandler->setSourceDevice(kbDev);
        return mouseHandler->sourceDevice() == mouseDev && kbHandler->sourceDevice() == kbDev;
    });
    r.check("qt3d/logical-device-axis-action", [&](QString &d) {
        auto *logicalDevice = new QLogicalDevice;
        auto *axis = new QAxis;
        axis->setObjectName(QStringLiteral("moveX"));
        auto *analogInput = new QAnalogAxisInput;
        analogInput->setAxis(0);
        axis->addInput(analogInput);
        logicalDevice->addAxis(axis);

        auto *action = new Qt3DInput::QAction;
        action->setObjectName(QStringLiteral("fire"));
        auto *actionInput = new QActionInput;
        actionInput->setButtons(QVector<int>{Qt::Key_Space});
        action->addInput(actionInput);
        logicalDevice->addAction(action);

        bool ok = logicalDevice->axes().contains(axis) && logicalDevice->actions().contains(action)
               && axis->inputs().contains(analogInput) && action->inputs().contains(actionInput);
        delete logicalDevice;
        return ok;
    });
    r.check("qt3d/inputsettings-frameaction", [&](QString &d) {
        QEntity root;
        auto *settings = new QInputSettings(&root);
        root.addComponent(settings);
        int triggers = 0;
        auto *frameAction = new Qt3DLogic::QFrameAction(&root);
        QObject::connect(frameAction, &Qt3DLogic::QFrameAction::triggered, &root,
                          [&](float){ ++triggers; });
        emit frameAction->triggered(0.016f);
        return settings->entities().contains(&root) && triggers == 1;
    });
}

void checkQt3DAnimation(SmokeReporter &r)
{
    r.check("qt3d/animation-clip-data", [&](QString &d) {
        Qt3DAnimation::QAnimationClipData clipData;
        Qt3DAnimation::QChannel channel(QStringLiteral("rotation"));
        Qt3DAnimation::QChannelComponent comp(QStringLiteral("rotation.x"));
        comp.appendKeyFrame(Qt3DAnimation::QKeyFrame(QVector2D(0.0f, 0.0f)));
        comp.appendKeyFrame(Qt3DAnimation::QKeyFrame(QVector2D(1.0f, 1.0f)));
        channel.appendChannelComponent(comp);
        clipData.appendChannel(channel);
        if (clipData.channelCount() != 1) { d = QString("channels=%1").arg(clipData.channelCount()); return false; }
        return clipData.begin()->name() == QStringLiteral("rotation");
    });
    r.check("qt3d/animation-clip-loader-mapper", [&](QString &d) {
        auto *clip = new Qt3DAnimation::QAnimationClipLoader;
        auto *mapper = new Qt3DAnimation::QChannelMapper;
        auto *mapping = new Qt3DAnimation::QChannelMapping;
        mapping->setChannelName(QStringLiteral("rotation"));
        mapping->setProperty(QStringLiteral("rotation"));
        mapper->addMapping(mapping);
        auto *animator = new Qt3DAnimation::QClipAnimator;
        animator->setClip(clip);
        animator->setChannelMapper(mapper);
        bool ok = animator->clip() == clip && animator->channelMapper() == mapper
               && mapper->mappings().contains(mapping);
        // setClip()/setChannelMapper() take ownership (reparent clip/mapper
        // under animator), so deleting animator alone cascades through the
        // whole graph - deleting them again here would be a double free.
        delete animator;
        return ok;
    });
    r.check("qt3d/animation-controller-group", [&](QString &d) {
        auto *controller = new Qt3DAnimation::QAnimationController;
        auto *group = new Qt3DAnimation::QAnimationGroup(controller);
        group->setName(QStringLiteral("walk-cycle"));
        bool ok = group->parent() == controller && group->name() == QStringLiteral("walk-cycle");
        delete controller;
        return ok;
    });
}
