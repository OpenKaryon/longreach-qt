// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

#include "../common/smokecheck.h"
#include "gl-heavy.h"

#include <Qt3DCore/QAbstractAspect>
#include <Qt3DCore/QArmature>
#include <Qt3DCore/QAspectJob>
#include <Qt3DCore/QBackendNode>
#include <Qt3DCore/QComponent>
#if QT_VERSION_MAJOR < 6
#include <Qt3DCore/QComponentAddedChange>   // change system removed in Qt 6
#endif
#if QT_VERSION_MAJOR < 6
#include <Qt3DCore/QComponentRemovedChange>
#endif
#if QT_VERSION_MAJOR < 6
#include <Qt3DCore/QDynamicPropertyUpdatedChange>
#endif
#include <Qt3DCore/QEntity>
#include <Qt3DCore/QJoint>
#if QT_VERSION_MAJOR < 6
#include <Qt3DCore/QNodeCommand>
#endif
#if QT_VERSION_MAJOR < 6
#include <Qt3DCore/QNodeCreatedChange>
#endif
#if QT_VERSION_MAJOR < 6
#include <Qt3DCore/QNodeDestroyedChange>
#endif
#if QT_VERSION_MAJOR < 6
#include <Qt3DCore/QPropertyNodeAddedChange>
#endif
#if QT_VERSION_MAJOR < 6
#include <Qt3DCore/QPropertyNodeRemovedChange>
#endif
#if QT_VERSION_MAJOR < 6
#include <Qt3DCore/QPropertyUpdatedChange>
#endif
#if QT_VERSION_MAJOR < 6
#include <Qt3DCore/QPropertyUpdatedChangeBase>
#endif
#if QT_VERSION_MAJOR < 6
#include <Qt3DCore/QPropertyValueAddedChange>
#endif
#if QT_VERSION_MAJOR < 6
#include <Qt3DCore/QPropertyValueRemovedChange>
#endif
#if QT_VERSION_MAJOR < 6
#include <Qt3DCore/QSceneChange>
#endif
#include <Qt3DCore/QSkeleton>
#include <Qt3DCore/QSkeletonLoader>
#if QT_VERSION_MAJOR < 6
#include <Qt3DCore/QStaticPropertyUpdatedChangeBase>
#endif
#if QT_VERSION_MAJOR < 6
#include <Qt3DCore/QStaticPropertyValueAddedChangeBase>
#endif
#if QT_VERSION_MAJOR < 6
#include <Qt3DCore/QStaticPropertyValueRemovedChangeBase>
#endif
#include <Qt3DCore/QTransform>

#include <Qt3DRender/QAlphaCoverage>
#include <Qt3DRender/QAlphaTest>
#if QT_VERSION_MAJOR < 6
#include <Qt3DRender/QAbstractFunctor>
#else
#include <Qt3DCore/QAbstractFunctor>   // moved modules in Qt 6
#endif
#include <Qt3DRender/QAbstractLight>
#include <Qt3DRender/QAbstractRayCaster>
#include <Qt3DRender/QAbstractTexture>
#include <Qt3DRender/QAbstractTextureImage>
#include <Qt3DRender/QBlendEquation>
#include <Qt3DRender/QBlendEquationArguments>
#include <Qt3DRender/QBlitFramebuffer>
#if QT_VERSION_MAJOR < 6
#include <Qt3DRender/QBufferCapture>
#endif
#if QT_VERSION_MAJOR < 6
#include <Qt3DRender/QBufferDataGenerator>
#endif
#include <Qt3DRender/QClipPlane>
#include <Qt3DRender/QColorMask>
#include <Qt3DRender/QComputeCommand>
#include <Qt3DRender/QCullFace>
#include <Qt3DRender/QDebugOverlay>
#include <Qt3DRender/QDepthRange>
#include <Qt3DRender/QDepthTest>
#include <Qt3DRender/QDirectionalLight>
#include <Qt3DRender/QDispatchCompute>
#include <Qt3DRender/QDithering>
#include <Qt3DRender/QEnvironmentLight>
#include <Qt3DRender/QFilterKey>
#include <Qt3DRender/QFrameGraphNode>
#if QT_VERSION_MAJOR < 6
#include <Qt3DRender/QFrameGraphNodeCreatedChangeBase>
#endif
#include <Qt3DRender/QFrontFace>
#include <Qt3DRender/QFrustumCulling>
#if QT_VERSION_MAJOR < 6
#include <Qt3DRender/QGeometry>
#else
#include <Qt3DCore/QGeometry>   // moved out of Qt3DRender in Qt 6
#endif
#if QT_VERSION_MAJOR < 6
// QGeometry was promoted to Qt3DCore, but the factory interface beside it was
// dropped rather than moved.
#include <Qt3DRender/QGeometryFactory>
#endif
#include <Qt3DRender/QGraphicsApiFilter>
#include <Qt3DRender/QLevelOfDetail>
#include <Qt3DRender/QLevelOfDetailBoundingSphere>
#include <Qt3DRender/QLevelOfDetailSwitch>
#include <Qt3DRender/QLineWidth>
#include <Qt3DRender/QMemoryBarrier>
#include <Qt3DRender/QMesh>
#include <Qt3DRender/QMultiSampleAntiAliasing>
#include <Qt3DRender/QNoDepthMask>
#include <Qt3DRender/QNoDraw>
#include <Qt3DRender/QNoPicking>
#include <Qt3DRender/QPaintedTextureImage>
#include <Qt3DRender/QPickEvent>
#include <Qt3DRender/QPickingSettings>
#include <Qt3DRender/QPickLineEvent>
#include <Qt3DRender/QPickPointEvent>
#include <Qt3DRender/QPickTriangleEvent>
#include <Qt3DRender/QPointSize>
#include <Qt3DRender/QPolygonOffset>
#include <Qt3DRender/QProximityFilter>
#include <Qt3DRender/QRasterMode>
#include <Qt3DRender/QRayCaster>
#include <Qt3DRender/QRayCasterHit>
#include <Qt3DRender/QRenderAspect>
#include <Qt3DRender/QRenderCapabilities>
#include <Qt3DRender/QRenderCapture>
#include <Qt3DRender/QRenderPassFilter>
#include <Qt3DRender/QRenderSettings>
#include <Qt3DRender/QRenderState>
#include <Qt3DRender/QRenderStateSet>
#include <Qt3DRender/QRenderSurfaceSelector>
#include <Qt3DRender/QRenderTarget>
#include <Qt3DRender/QRenderTargetOutput>
#include <Qt3DRender/QRenderTargetSelector>
#include <Qt3DRender/QSceneLoader>
#include <Qt3DRender/QScissorTest>
#include <Qt3DRender/QScreenRayCaster>
#include <Qt3DRender/QSeamlessCubemap>
#include <Qt3DRender/QSetFence>
#include <Qt3DRender/QShaderData>
#include <Qt3DRender/QShaderImage>
#include <Qt3DRender/QShaderProgram>
#include <Qt3DRender/QShaderProgramBuilder>
#include <Qt3DRender/QSortPolicy>
#include <Qt3DRender/QStencilMask>
#include <Qt3DRender/QStencilOperation>
#include <Qt3DRender/QStencilOperationArguments>
#include <Qt3DRender/QStencilTest>
#include <Qt3DRender/QStencilTestArguments>
#if QT_VERSION_MAJOR < 6
#include <Qt3DRender/QSubtreeEnabler>
#endif
#include <Qt3DRender/QTechniqueFilter>
#include <Qt3DRender/QTextureData>
#include <Qt3DRender/QTextureDataUpdate>
#if QT_VERSION_MAJOR < 6
#include <Qt3DRender/QTextureGenerator>
#endif
#include <Qt3DRender/QTextureImageData>
#include <Qt3DRender/QTextureImageDataGenerator>
#include <Qt3DRender/QTexture>
#include <Qt3DRender/QTextureWrapMode>
#include <Qt3DRender/QWaitFence>

#include <Qt3DExtras/QConeGeometry>
#include <Qt3DExtras/QAbstractCameraController>
#include <Qt3DExtras/QConeMesh>
#include <Qt3DExtras/QCuboidGeometry>
#include <Qt3DExtras/QCylinderGeometry>
#include <Qt3DExtras/QDiffuseMapMaterial>
#include <Qt3DExtras/QDiffuseSpecularMapMaterial>
#include <Qt3DExtras/QDiffuseSpecularMaterial>
#include <Qt3DExtras/QExtrudedTextGeometry>
#include <Qt3DExtras/QExtrudedTextMesh>
#include <Qt3DExtras/QForwardRenderer>
#include <Qt3DExtras/QGoochMaterial>
#include <Qt3DExtras/QMetalRoughMaterial>
#include <Qt3DExtras/QMorphPhongMaterial>
#include <Qt3DExtras/QNormalDiffuseMapAlphaMaterial>
#include <Qt3DExtras/QNormalDiffuseMapMaterial>
#include <Qt3DExtras/QNormalDiffuseSpecularMapMaterial>
#include <Qt3DExtras/QOrbitCameraController>
#include <Qt3DExtras/QPlaneGeometry>
#include <Qt3DExtras/QPlaneMesh>
#include <Qt3DExtras/QSkyboxEntity>
#include <Qt3DExtras/QSphereGeometry>
#include <Qt3DExtras/QSpriteGrid>
#include <Qt3DExtras/QSpriteSheet>
#include <Qt3DExtras/QSpriteSheetItem>
#include <Qt3DExtras/QTextureMaterial>
#include <Qt3DExtras/QTorusGeometry>
#include <Qt3DExtras/QTorusMesh>

#include <Qt3DInput/QAbstractActionInput>
#include <Qt3DInput/QAbstractAxisInput>
#include <Qt3DInput/QAbstractPhysicalDevice>
#include <Qt3DInput/QAction>
#include <Qt3DInput/QActionInput>
#include <Qt3DInput/QAnalogAxisInput>
#include <Qt3DInput/QAxis>
#include <Qt3DInput/QAxisAccumulator>
#include <Qt3DInput/QAxisSetting>
#include <Qt3DInput/QButtonAxisInput>
#include <Qt3DInput/QInputChord>
#include <Qt3DInput/QInputSequence>
#include <Qt3DInput/QKeyEvent>
#include <Qt3DInput/QMouseEvent>
#include <Qt3DInput/QMouseDevice>
#if QT_VERSION_MAJOR < 6
#include <Qt3DInput/QPhysicalDeviceCreatedChangeBase>
#endif
#include <Qt3DInput/QWheelEvent>

#include <Qt3DAnimation/QAbstractAnimation>
#include <Qt3DAnimation/QAbstractAnimationClip>
#include <Qt3DAnimation/QAbstractChannelMapping>
#include <Qt3DAnimation/QAbstractClipAnimator>
#include <Qt3DAnimation/QAbstractClipBlendNode>
#include <Qt3DAnimation/QAdditiveClipBlend>
#include <Qt3DAnimation/QAnimationAspect>
#include <Qt3DAnimation/QAnimationCallback>
#include <Qt3DAnimation/QAnimationClip>
#include <Qt3DAnimation/QAnimationClipLoader>
#include <Qt3DAnimation/QBlendedClipAnimator>
#include <Qt3DAnimation/QCallbackMapping>
#include <Qt3DAnimation/QChannelMapper>
#include <Qt3DAnimation/QChannelMapping>
#if QT_VERSION_MAJOR < 6
#include <Qt3DAnimation/QClipBlendNodeCreatedChangeBase>
#endif
#include <Qt3DAnimation/QClipAnimator>
#include <Qt3DAnimation/QClipBlendValue>
#include <Qt3DAnimation/QClock>
#include <Qt3DAnimation/QLerpClipBlend>
#include <Qt3DAnimation/QMorphingAnimation>
#include <Qt3DAnimation/QMorphTarget>
#include <Qt3DAnimation/QSkeletonMapping>
#include <Qt3DAnimation/QVertexBlendAnimation>

#include <Qt3DQuick/QQmlAspectEngine>
#include <Qt3DQuickScene2D/QScene2D>

#include <QImage>
#include <QPainter>
#include <QQuickItem>
#include <QScopedPointer>
#include <QSharedPointer>
#include <QUrl>
#include <QVariant>
#include <QVector2D>
#include <QVector3D>

using namespace Qt3DAnimation;
using namespace Qt3DCore;
using namespace Qt3DExtras;
using namespace Qt3DInput;
using namespace Qt3DRender;

namespace {

class SmokeAspectJob : public QAspectJob
{
public:
    void run() override { ran = true; }
    bool ran = false;
};

class SmokeBackendMapper : public QBackendNodeMapper
{
public:
    // Qt 6 hands the mapper a node id; Qt 5 handed it the creation change.
#if QT_VERSION_MAJOR < 6
    QBackendNode *create(const QNodeCreatedChangeBasePtr &) const override { return new QBackendNode(QBackendNode::ReadWrite); }
#else
    QBackendNode *create(QNodeId) const override { return new QBackendNode(QBackendNode::ReadWrite); }
#endif
    QBackendNode *get(QNodeId) const override { return nullptr; }
    void destroy(QNodeId) const override {}
};

// The data-generator functors below have no Qt 6 counterpart: buffers,
// geometry and texture data are set directly on the frontend node there.
#if QT_VERSION_MAJOR < 6
class SmokeBufferGenerator : public QBufferDataGenerator
{
public:
    QT3D_FUNCTOR(SmokeBufferGenerator)
    QByteArray operator()() override { return QByteArrayLiteral("qt3d"); }
    bool operator ==(const QBufferDataGenerator &other) const override { return this == &other; }
};

class SmokeGeometryFactory : public QGeometryFactory
{
public:
    QT3D_FUNCTOR(SmokeGeometryFactory)
    QGeometry *operator()() override { return new QGeometry; }
    bool equals(const QGeometryFactory &other) const override { return this == &other; }
};

class SmokeTextureGenerator : public QTextureGenerator
{
public:
    QT3D_FUNCTOR(SmokeTextureGenerator)
    QTextureDataPtr operator()() override
    {
        QTextureDataPtr data(new QTextureData);
        data->setTarget(QAbstractTexture::Target2D);
        data->setWidth(4);
        data->setHeight(4);
        return data;
    }
    bool operator ==(const QTextureGenerator &other) const override { return this == &other; }
};
#endif

class SmokeTextureImageGenerator : public QTextureImageDataGenerator
{
public:
    QT3D_FUNCTOR(SmokeTextureImageGenerator)
    QTextureImageDataPtr operator()() override
    {
        QTextureImageDataPtr data(new QTextureImageData);
        data->setImage(QImage(2, 2, QImage::Format_RGBA8888));
        return data;
    }
    bool operator ==(const QTextureImageDataGenerator &other) const override { return this == &other; }
};

class SmokePaintedTextureImage : public QPaintedTextureImage
{
public:
    using QPaintedTextureImage::QPaintedTextureImage;
protected:
    void paint(QPainter *painter) override { painter->fillRect(QRect(0, 0, width(), height()), Qt::red); }
};

class SmokeAnimationCallback : public QAnimationCallback
{
public:
    void valueChanged(const QVariant &value) override { lastValue = value; }
    QVariant lastValue;
};

bool ownsAll(const QList<QNode *> &children, std::initializer_list<QNode *> expected)
{
    for (QNode *node : expected) {
        if (!children.contains(node))
            return false;
    }
    return true;
}

} // namespace

void checkQt3DCoreAndChanges(SmokeReporter &r)
{
#if QT_VERSION_MAJOR < 6
    r.check("qt3d/core-change-objects", [&](QString &d) {
        QEntity root;
        Qt3DCore::QTransform transform;
        root.addComponent(&transform);
        const QNodeId rootId = root.id();

        QComponent *componentBase = &transform;
        QComponentAddedChange added(&root, componentBase);
        QComponentRemovedChange removed(&root, componentBase);
        QPropertyUpdatedChange updated(rootId);
        updated.setPropertyName("smoke");
        updated.setValue(42);
        QDynamicPropertyUpdatedChange dynamic(rootId);
        dynamic.setPropertyName("dynamicSmoke");
        dynamic.setValue(QStringLiteral("ok"));

        QPropertyValueAddedChange valueAdded(rootId);
        valueAdded.setPropertyName("items");
        valueAdded.setAddedValue(QStringLiteral("one"));
        QPropertyValueRemovedChange valueRemoved(rootId);
        valueRemoved.setPropertyName("items");
        valueRemoved.setRemovedValue(QStringLiteral("one"));

        QJoint joint;
        QPropertyNodeAddedChange nodeAdded(rootId, &joint);
        QPropertyNodeRemovedChange nodeRemoved(rootId, &joint);
        QNodeDestroyedChange destroyed(&root, QVector<QNodeIdTypePair>());
        QNodeCommand command(rootId);
        command.setName(QStringLiteral("probe"));
        command.setData(QVariant(7));

        QSceneChange *sceneBase = &updated;
        QPropertyUpdatedChangeBase *updatedBase = &updated;
        QStaticPropertyUpdatedChangeBase *staticUpdatedBase = &updated;
        QPropertyValueAddedChangeBase *valueAddedBase = &valueAdded;
        QStaticPropertyValueAddedChangeBase *staticAddedBase = &valueAdded;
        QPropertyValueRemovedChangeBase *valueRemovedBase = &valueRemoved;
        QStaticPropertyValueRemovedChangeBase *staticRemovedBase = &valueRemoved;
        QNodeCreatedChange<QVariant> nodeCreated(&root);
        QNodeCreatedChangeBase *nodeCreatedBase = &nodeCreated;

        bool ok = added.componentId() == transform.id()
               && removed.componentId() == transform.id()
               && updated.value().toInt() == 42
               && dynamic.value().toString() == QStringLiteral("ok")
               && valueAdded.addedValue().toString() == QStringLiteral("one")
               && valueRemoved.removedValue().toString() == QStringLiteral("one")
               && nodeAdded.addedNodeId() == joint.id()
               && nodeRemoved.removedNodeId() == joint.id()
               && destroyed.subjectId() == rootId
               && command.name() == QStringLiteral("probe")
               && command.data().toInt() == 7
               && sceneBase->subjectId() == rootId
               && updatedBase->subjectId() == rootId
               && staticUpdatedBase->propertyName() == QByteArrayLiteral("smoke")
               && valueAddedBase->subjectId() == rootId
               && staticAddedBase->propertyName() == QByteArrayLiteral("items")
               && valueRemovedBase->subjectId() == rootId
               && staticRemovedBase->propertyName() == QByteArrayLiteral("items")
               && nodeCreatedBase->subjectId() == rootId
               && nodeCreatedBase->metaObject() == root.metaObject();
        if (!ok)
            d = QStringLiteral("change payload mismatch");
        return ok;
    });
#else
    // Qt 6's Qt3D dropped the backend change-notification system outright -
    // the frontend writes to the backend directly - so there is nothing here
    // to port these onto. Reported rather than dropped so the difference is
    // visible in the run.
    r.check("qt3d/core-change-objects", [&](QString &d) {
        r.skip(d, QStringLiteral("Qt 6's Qt3D has no scene-change API"));
        return false;
    });
#endif

    r.check("qt3d/core-aspect-backend-skeleton", [&](QString &d) {
        QAbstractAspect aspect;
#if QT_VERSION_MAJOR < 6
        QRenderAspect renderAspect(QRenderAspect::Synchronous);
#else
        // RenderType (Synchronous/Threaded) became SubmissionType in Qt 6;
        // Manual is the one that does not spin up a render thread.
        QRenderAspect renderAspect(QRenderAspect::Manual);
#endif
        QAnimationAspect animationAspect;

        QSharedPointer<SmokeAspectJob> job(new SmokeAspectJob);
        QAspectJobPtr baseJob = job;
        SmokeAspectJob dependency;
        QAspectJobPtr dependencyPtr(new SmokeAspectJob);
        job->addDependency(dependencyPtr.toWeakRef());
        job->run();

        SmokeBackendMapper mapper;
        QBackendNodeMapper *mapperBase = &mapper;
#if QT_VERSION_MAJOR < 6
        QBackendNode *backend = mapperBase->create(QNodeCreatedChangeBasePtr());
#else
        QBackendNode *backend = mapperBase->create(QNodeId());
#endif
        backend->setEnabled(false);

        QArmature armature;
        QSkeleton skeleton;
        QSkeletonLoader loader;
        loader.setSource(QUrl(QStringLiteral("file:///skeleton.json")));
        armature.setSkeleton(&skeleton);

        QJoint rootJoint;
        rootJoint.setName(QStringLiteral("root"));
        rootJoint.setTranslation(QVector3D(1, 2, 3));
        skeleton.setRootJoint(&rootJoint);

        QAbstractSkeleton *abstractSkeleton = &skeleton;
        bool ok = job->ran
               && baseJob->dependencies().size() == 1
               && backend->mode() == QBackendNode::ReadWrite
               && !backend->isEnabled()
               && armature.skeleton() == &skeleton
               && loader.source().isValid()
               && skeleton.rootJoint() == &rootJoint
               && abstractSkeleton != nullptr
               && renderAspect.parent() == nullptr
               && animationAspect.parent() == nullptr
               && aspect.parent() == nullptr;
        delete backend;
        Q_UNUSED(dependency);
        if (!ok)
            d = QStringLiteral("core object state mismatch");
        return ok;
    });
}

void checkQt3DRenderStatesExtra(SmokeReporter &r)
{
    r.check("qt3d/render-state-catalogue", [&](QString &d) {
        QRenderStateSet stateSet;

        auto *alphaCoverage = new QAlphaCoverage;
        auto *alphaTest = new QAlphaTest;
        alphaTest->setAlphaFunction(QAlphaTest::Greater);
        alphaTest->setReferenceValue(0.25f);
        auto *blendEquation = new QBlendEquation;
        blendEquation->setBlendFunction(QBlendEquation::Add);
        auto *blendArgs = new QBlendEquationArguments;
        blendArgs->setSourceRgb(QBlendEquationArguments::SourceAlpha);
        blendArgs->setDestinationRgb(QBlendEquationArguments::OneMinusSourceAlpha);
        auto *clipPlane = new QClipPlane;
        clipPlane->setPlaneIndex(1);
        clipPlane->setNormal(QVector3D(0, 1, 0));
        auto *colorMask = new QColorMask;
        colorMask->setAlphaMasked(false);
        auto *cullFace = new QCullFace;
        cullFace->setMode(QCullFace::Back);
        auto *depthRange = new QDepthRange;
        // Both the setters and the getters are double here, so the literals must
        // not be float: 0.1f widens to 0.10000000149011612, which is 1.5e-9 away
        // from 0.1 - far outside the 1e-12 relative tolerance qFuzzyCompare uses
        // for doubles, and the check then fails for no reason at all.
        depthRange->setNearValue(0.1);
        depthRange->setFarValue(0.9);
        auto *depthTest = new QDepthTest;
        depthTest->setDepthFunction(QDepthTest::LessOrEqual);
        auto *dithering = new QDithering;
        auto *frontFace = new QFrontFace;
        frontFace->setDirection(QFrontFace::CounterClockWise);
        auto *lineWidth = new QLineWidth;
        lineWidth->setValue(2.0f);
        auto *msaa = new QMultiSampleAntiAliasing;
        auto *noDepthMask = new QNoDepthMask;
        auto *pointSize = new QPointSize;
        pointSize->setValue(5.0f);
        auto *polygonOffset = new QPolygonOffset;
        polygonOffset->setScaleFactor(1.0f);
        polygonOffset->setDepthSteps(2.0f);
        auto *rasterMode = new QRasterMode;
        rasterMode->setRasterMode(QRasterMode::Lines);
        auto *scissor = new QScissorTest;
        scissor->setLeft(1);
        scissor->setBottom(2);
        scissor->setWidth(10);
        scissor->setHeight(20);
        auto *seamless = new QSeamlessCubemap;
        auto *stencilMask = new QStencilMask;
        stencilMask->setFrontOutputMask(0xff);
        auto *stencilOperation = new QStencilOperation;
        stencilOperation->front()->setAllTestsPassOperation(QStencilOperationArguments::Replace);
        auto *stencilTest = new QStencilTest;
        stencilTest->front()->setComparisonMask(0x0f);

        const QList<QRenderState *> states{
            alphaCoverage, alphaTest, blendEquation, blendArgs, clipPlane, colorMask,
            cullFace, depthRange, depthTest, dithering, frontFace, lineWidth, msaa,
            noDepthMask, pointSize, polygonOffset, rasterMode, scissor, seamless,
            stencilMask, stencilOperation, stencilTest
        };
        for (QRenderState *state : states)
            stateSet.addRenderState(state);

        bool ok = stateSet.renderStates().size() == states.size()
               && alphaTest->alphaFunction() == QAlphaTest::Greater
               && qFuzzyCompare(alphaTest->referenceValue(), 0.25f)
               && blendEquation->blendFunction() == QBlendEquation::Add
               && blendArgs->destinationRgb() == QBlendEquationArguments::OneMinusSourceAlpha
               && clipPlane->planeIndex() == 1
               && !colorMask->isAlphaMasked()
               && cullFace->mode() == QCullFace::Back
               && qFuzzyCompare(depthRange->nearValue(), 0.1)
               && qFuzzyCompare(depthRange->farValue(), 0.9)
               && depthTest->depthFunction() == QDepthTest::LessOrEqual
               && frontFace->direction() == QFrontFace::CounterClockWise
               && qFuzzyCompare(lineWidth->value(), 2.0f)
               && qFuzzyCompare(pointSize->value(), 5.0f)
               && rasterMode->rasterMode() == QRasterMode::Lines
               && scissor->width() == 10
               && stencilOperation->front()->allTestsPassOperation() == QStencilOperationArguments::Replace
               && stencilTest->front()->comparisonMask() == 0x0f;
        if (!ok)
            d = QStringLiteral("render state mismatch");
        return ok;
    });
}

void checkQt3DFrameGraphExtra(SmokeReporter &r)
{
    r.check("qt3d/framegraph-render-targets", [&](QString &d) {
        auto *root = new QRenderSurfaceSelector;
        auto *blit = new QBlitFramebuffer(root);
        blit->setSourceRect(QRect(0, 0, 10, 10));
        blit->setDestinationRect(QRect(1, 1, 10, 10));
#if QT_VERSION_MAJOR < 6
        auto *captureBuffer = new QBufferCapture(blit);
        QFrameGraphNode *afterBlit = captureBuffer;
#else
        QFrameGraphNode *afterBlit = blit;   // QBufferCapture is gone in Qt 6
#endif
        auto *debug = new QDebugOverlay(afterBlit);
        auto *dispatch = new QDispatchCompute(debug);
        dispatch->setWorkGroupX(2);
        dispatch->setWorkGroupY(3);
        auto *frustum = new QFrustumCulling(dispatch);
        auto *barrier = new QMemoryBarrier(frustum);
        QMemoryBarrier::Operations barrierOps = QMemoryBarrier::VertexAttributeArray;
        barrierOps |= QMemoryBarrier::TextureFetch;
        barrier->setWaitOperations(barrierOps);
        auto *noDraw = new QNoDraw(barrier);
        auto *noPicking = new QNoPicking(noDraw);
        auto *proximity = new QProximityFilter(noPicking);
        proximity->setDistanceThreshold(12.0f);
        auto *renderCapture = new QRenderCapture(proximity);
        QRenderCaptureReply *captureReply = renderCapture->requestCapture(QRect(0, 0, 1, 1));
        auto *renderPassFilter = new QRenderPassFilter(renderCapture);
        auto *filterKey = new QFilterKey(renderPassFilter);
        filterKey->setName(QStringLiteral("pass"));
        filterKey->setValue(QStringLiteral("opaque"));
        renderPassFilter->addMatch(filterKey);
        auto *targetSelector = new QRenderTargetSelector(renderPassFilter);
        auto *target = new QRenderTarget(targetSelector);
        auto *output = new QRenderTargetOutput(target);
        auto *texture = new QTexture2D(output);
        output->setTexture(texture);
        output->setAttachmentPoint(QRenderTargetOutput::Color0);
        target->addOutput(output);
        targetSelector->setTarget(target);
        auto *setFence = new QSetFence(targetSelector);
        auto *sortPolicy = new QSortPolicy(setFence);
        sortPolicy->setSortTypes(QVector<QSortPolicy::SortType>{QSortPolicy::Material, QSortPolicy::BackToFront});
#if QT_VERSION_MAJOR < 6
        auto *subtree = new QSubtreeEnabler(sortPolicy);
        subtree->setEnablement(QSubtreeEnabler::SingleShot);
        QFrameGraphNode *afterSort = subtree;
#else
        QFrameGraphNode *afterSort = sortPolicy;   // QSubtreeEnabler is gone in Qt 6
#endif
        auto *techniqueFilter = new QTechniqueFilter(afterSort);
        techniqueFilter->addMatch(new QFilterKey(techniqueFilter));
        auto *waitFence = new QWaitFence(techniqueFilter);
        waitFence->setHandle(QVariant::fromValue(456));
#if QT_VERSION_MAJOR < 6
        QFrameGraphNodeCreatedChange<QVariant> frameCreated(root);
        QFrameGraphNodeCreatedChangeBase *frameCreatedBase = &frameCreated;
#endif

        QFrameGraphNode *frameGraphBase = blit;
        QRenderStateSet stateSet;
        stateSet.addRenderState(new QDepthTest);

        QRenderSettings settings;
        settings.setActiveFrameGraph(root);
        settings.setRenderPolicy(QRenderSettings::Always);
        QPickingSettings *picking = settings.pickingSettings();
        picking->setPickMethod(QPickingSettings::TrianglePicking);
        QRenderCapabilities capabilities;

        QStringList misses;
        if (frameGraphBase->parentNode() != root) misses << QStringLiteral("parent");
        if (blit->sourceRect() != QRect(0, 0, 10, 10)) misses << QStringLiteral("blit");
        if (dispatch->workGroupX() != 2 || dispatch->workGroupY() != 3) misses << QStringLiteral("dispatch");
        if (!barrier->waitOperations().testFlag(QMemoryBarrier::TextureFetch)) misses << QStringLiteral("barrier");
        if (!qFuzzyCompare(proximity->distanceThreshold(), 12.0f)) misses << QStringLiteral("proximity");
        if (!renderPassFilter->matchAny().contains(filterKey)) misses << QStringLiteral("passfilter");
        if (captureReply == nullptr) misses << QStringLiteral("capture-reply");
        if (!target->outputs().contains(output)) misses << QStringLiteral("target");
        if (targetSelector->target() != target) misses << QStringLiteral("selector");
        if (!sortPolicy->sortTypes().contains(QSortPolicy::Material)) misses << QStringLiteral("sort");
#if QT_VERSION_MAJOR < 6
        if (subtree->enablement() != QSubtreeEnabler::SingleShot) misses << QStringLiteral("subtree");
#endif
        if (setFence->handleType() != QSetFence::NoHandle) misses << QStringLiteral("setfence");
        if (waitFence->handle().toInt() != 456) misses << QStringLiteral("waitfence");
        if (stateSet.renderStates().size() != 1) misses << QStringLiteral("stateset");
        if (settings.activeFrameGraph() != root) misses << QStringLiteral("settings-framegraph");
        if (settings.renderPolicy() != QRenderSettings::Always) misses << QStringLiteral("settings-policy");
        if (picking->pickMethod() != QPickingSettings::TrianglePicking) misses << QStringLiteral("picking");
#if QT_VERSION_MAJOR < 6
        if (frameCreatedBase->subjectId() != root->id()) misses << QStringLiteral("frame-created");
#endif
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
    });
}

void checkQt3DGeometryMaterialsExtra(SmokeReporter &r)
{
    r.check("qt3d/geometry-and-material-extras", [&](QString &d) {
        QConeGeometry coneGeometry;
        coneGeometry.setLength(3.0f);
        QConeMesh coneMesh;
        coneMesh.setTopRadius(0.25f);
        QCuboidGeometry cuboidGeometry;
        cuboidGeometry.setXExtent(2.0f);
        QCylinderGeometry cylinderGeometry;
        cylinderGeometry.setRadius(1.5f);
        QPlaneGeometry planeGeometry;
        planeGeometry.setWidth(4.0f);
        QPlaneMesh planeMesh;
        planeMesh.setHeight(5.0f);
        QSphereGeometry sphereGeometry;
        sphereGeometry.setRadius(2.5f);
        QTorusGeometry torusGeometry;
        torusGeometry.setRadius(3.0f);
        QTorusMesh torusMesh;
        torusMesh.setMinorRadius(0.5f);

        QMesh mesh;
        mesh.setSource(QUrl(QStringLiteral("file:///mesh.obj")));
        QExtrudedTextGeometry textGeometry;
        textGeometry.setText(QStringLiteral("XP"));
        QExtrudedTextMesh textMesh;
        textMesh.setDepth(0.3f);

        QDiffuseMapMaterial diffuseMap;
        QDiffuseSpecularMapMaterial diffuseSpecularMap;
        QDiffuseSpecularMaterial diffuseSpecular;
        QGoochMaterial gooch;
        QMetalRoughMaterial metalRough;
        QMorphPhongMaterial morphPhong;
        QNormalDiffuseMapAlphaMaterial normalAlpha;
        QNormalDiffuseMapMaterial normalMap;
        QNormalDiffuseSpecularMapMaterial normalSpecular;
        QTextureMaterial textureMaterial;

        diffuseSpecular.setShininess(12.0f);
        gooch.setAlpha(0.75f);
        metalRough.setMetalness(0.8f);

        QEnvironmentLight environmentLight;
        auto *irradiance = new QTextureCubeMap(&environmentLight);
        environmentLight.setIrradiance(irradiance);
        QDirectionalLight directional;
        directional.setWorldDirection(QVector3D(0, -1, 0));
        QAbstractLight *lightBase = &directional;
        QOrbitCameraController orbitController;
        QAbstractCameraController *cameraControllerBase = &orbitController;
        cameraControllerBase->setLinearSpeed(9.0f);

        QSkyboxEntity skybox;
        skybox.setBaseName(QStringLiteral("sky"));
        QSpriteGrid spriteGrid;
        spriteGrid.setRows(2);
        spriteGrid.setColumns(3);
        QSpriteSheet spriteSheet;
        QSpriteSheetItem item;
        item.setX(1);
        item.setWidth(16);
        spriteSheet.addSprite(&item);
        QAbstractSpriteSheet *spriteBase = &spriteSheet;

        bool ok = qFuzzyCompare(coneGeometry.length(), 3.0f)
               && qFuzzyCompare(coneMesh.topRadius(), 0.25f)
               && qFuzzyCompare(cuboidGeometry.xExtent(), 2.0f)
               && qFuzzyCompare(cylinderGeometry.radius(), 1.5f)
               && qFuzzyCompare(planeGeometry.width(), 4.0f)
               && qFuzzyCompare(planeMesh.height(), 5.0f)
               && qFuzzyCompare(sphereGeometry.radius(), 2.5f)
               && qFuzzyCompare(torusGeometry.radius(), 3.0f)
               && qFuzzyCompare(torusMesh.minorRadius(), 0.5f)
               && mesh.source().isValid()
               && textGeometry.text() == QStringLiteral("XP")
               && qFuzzyCompare(textMesh.depth(), 0.3f)
               && diffuseMap.effect() != nullptr
               && diffuseSpecularMap.effect() != nullptr
               && qFuzzyCompare(diffuseSpecular.shininess(), 12.0f)
               && qFuzzyCompare(gooch.alpha(), 0.75f)
               && qFuzzyCompare(metalRough.metalness().toFloat(), 0.8f)
               && morphPhong.effect() != nullptr
               && normalAlpha.effect() != nullptr
               && normalMap.effect() != nullptr
               && normalSpecular.effect() != nullptr
               && textureMaterial.effect() != nullptr
               && environmentLight.irradiance() == irradiance
               && lightBase->type() == QAbstractLight::DirectionalLight
               && qFuzzyCompare(cameraControllerBase->linearSpeed(), 9.0f)
               && skybox.baseName() == QStringLiteral("sky")
               && spriteGrid.rows() == 2
               && spriteGrid.columns() == 3
               && spriteSheet.sprites().contains(&item)
               && item.width() == 16
               && spriteBase != nullptr;
        if (!ok)
            d = QStringLiteral("geometry/material state mismatch");
        return ok;
    });
}

void checkQt3DTexturesAndShadersExtra(SmokeReporter &r)
{
    r.check("qt3d/textures-shaders-functors", [&](QString &d) {
        QTexture1D tex1d;
        QTexture1DArray tex1dArray;
        QTexture2DArray tex2dArray;
        QTexture2DMultisample tex2dMs;
        QTexture2DMultisampleArray tex2dMsArray;
        QTexture3D tex3d;
        QTextureBuffer texBuffer;
        QTextureCubeMap texCube;
        QTextureCubeMapArray texCubeArray;
        QTextureRectangle texRectangle;
        QSharedGLTexture sharedTexture;
        sharedTexture.setTextureId(99);
        QTextureLoader loader;
        loader.setSource(QUrl(QStringLiteral("file:///texture.png")));
        loader.setMirrored(false);

        QAbstractTexture *abstractTexture = &tex3d;
        abstractTexture->setWidth(16);
        abstractTexture->setHeight(8);
        QTextureWrapMode wrap(QTextureWrapMode::Repeat, QTextureWrapMode::ClampToEdge,
                              QTextureWrapMode::MirroredRepeat);
        abstractTexture->wrapMode()->setX(wrap.x());

        QTextureImage image;
        image.setMirrored(false);
        QAbstractTextureImage *abstractTextureImage = &image;
        SmokePaintedTextureImage painted;
        painted.setSize(QSize(4, 5));

        QTextureImageDataPtr imageData(new QTextureImageData);
        imageData->setImage(QImage(4, 4, QImage::Format_RGBA8888));
        imageData->setFaces(1);
        QTextureData textureData;
        textureData.setTarget(QAbstractTexture::Target2D);
        textureData.setWidth(4);
        textureData.setHeight(4);
        textureData.addImageData(imageData);
        QTextureDataUpdate update;
        update.setX(1);
        update.setY(2);
        update.setData(imageData);

        SmokeTextureImageGenerator textureImageGen;
#if QT_VERSION_MAJOR < 6
        SmokeBufferGenerator bufferGen;
        SmokeGeometryFactory geometryFactory;
        SmokeTextureGenerator textureGen;
        QAbstractFunctor *abstractFunctor = &bufferGen;
        QByteArray generatedBuffer = bufferGen();
        QScopedPointer<QGeometry> generatedGeometry(geometryFactory());
        QTextureDataPtr generatedTexture = textureGen();
#else
        // Only the texture-image generator survived into Qt 6, and it is still
        // a QAbstractFunctor - so the functor leg of this check keeps running.
        QAbstractFunctor *abstractFunctor = &textureImageGen;
#endif
        QTextureImageDataPtr generatedImage = textureImageGen();

        auto *shader = new QShaderProgram;
        QShaderProgramBuilder builder;
        builder.setShaderProgram(shader);
        builder.setEnabledLayers(QStringList() << QStringLiteral("diffuse"));
        builder.setVertexShaderGraph(QUrl(QStringLiteral("qrc:/shader.vert.json")));
        QShaderData shaderData;
        QShaderImage shaderImage;
        auto *shaderTexture = new QTextureCubeMap(&shaderImage);
        shaderImage.setTexture(shaderTexture);
        shaderImage.setLayered(true);
        shaderImage.setAccess(QShaderImage::ReadWrite);
        shaderImage.setFormat(QShaderImage::RGBA8_UNorm);

        QStringList misses;
        if (tex1d.target() != QAbstractTexture::Target1D) misses << QStringLiteral("tex1d");
        if (tex1dArray.target() != QAbstractTexture::Target1DArray) misses << QStringLiteral("tex1darray");
        if (tex2dArray.target() != QAbstractTexture::Target2DArray) misses << QStringLiteral("tex2darray");
        if (tex2dMs.target() != QAbstractTexture::Target2DMultisample) misses << QStringLiteral("tex2dms");
        if (tex2dMsArray.target() != QAbstractTexture::Target2DMultisampleArray) misses << QStringLiteral("tex2dmsarray");
        if (tex3d.target() != QAbstractTexture::Target3D) misses << QStringLiteral("tex3d");
        if (texBuffer.target() != QAbstractTexture::TargetBuffer) misses << QStringLiteral("texbuffer");
        if (texCube.target() != QAbstractTexture::TargetCubeMap) misses << QStringLiteral("texcube");
        if (texCubeArray.target() != QAbstractTexture::TargetCubeMapArray) misses << QStringLiteral("texcubearray");
        if (texRectangle.target() != QAbstractTexture::TargetRectangle) misses << QStringLiteral("texrect");
        if (sharedTexture.textureId() != 99) misses << QStringLiteral("shared");
        if (!loader.source().isValid() || loader.isMirrored()) misses << QStringLiteral("loader");
        if (abstractTexture->width() != 16) misses << QStringLiteral("abstract-size");
        if (abstractTexture->wrapMode()->x() != QTextureWrapMode::Repeat) misses << QStringLiteral("wrap");
        if (abstractTextureImage == nullptr || image.isMirrored()) misses << QStringLiteral("image");
        if (painted.size() != QSize(4, 5)) misses << QStringLiteral("painted");
        if (textureData.imageData().size() != 1) misses << QStringLiteral("texturedata");
        if (update.x() != 1 || update.data() != imageData) misses << QStringLiteral("update");
#if QT_VERSION_MAJOR < 6
        if (generatedBuffer != QByteArrayLiteral("qt3d")) misses << QStringLiteral("buffer-gen");
        if (generatedGeometry.data() == nullptr) misses << QStringLiteral("geometry-gen");
        if (generatedTexture->width() != 4) misses << QStringLiteral("texture-gen");
#endif
        if (generatedImage->width() != 2) misses << QStringLiteral("image-gen");
        if (abstractFunctor == nullptr) misses << QStringLiteral("functor");
        if (builder.shaderProgram() != shader) misses << QStringLiteral("builder-program");
        if (!builder.enabledLayers().contains(QStringLiteral("diffuse"))) misses << QStringLiteral("builder-layers");
        if (!builder.vertexShaderGraph().isValid()) misses << QStringLiteral("builder-graph");
        if (shaderData.propertyReader().isNull()) misses << QStringLiteral("shaderdata");
        if (shaderImage.texture() != shaderTexture) misses << QStringLiteral("shaderimage-texture");
        if (shaderImage.access() != QShaderImage::ReadWrite) misses << QStringLiteral("shaderimage-access");
        if (shaderImage.format() != QShaderImage::RGBA8_UNorm) misses << QStringLiteral("shaderimage-format");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
    });
}

void checkQt3DInputAndAnimationExtra(SmokeReporter &r)
{
    r.check("qt3d/input-extra-events", [&](QString &d) {
        QAxisAccumulator accumulator;
        auto *axis = new QAxis(&accumulator);
        auto *axisSetting = new QAxisSetting(axis);
        axisSetting->setAxes(QVector<int>{0, 1});
        axisSetting->setDeadZoneRadius(0.1f);
        axisSetting->setSmoothEnabled(true);
        accumulator.setSourceAxis(axis);
        accumulator.setScale(2.0f);

        Qt3DInput::QAction action;
        auto *actionInput = new QActionInput;
        actionInput->setButtons(QVector<int>{Qt::Key_A});
        action.addInput(actionInput);
        QInputChord chord;
        chord.setTimeout(100);
        auto *chordInput = new QActionInput;
        chordInput->setButtons(QVector<int>{Qt::Key_B});
        chord.addChord(chordInput);
        QInputSequence sequence;
        sequence.setTimeout(200);
        auto *sequenceInput = new QActionInput;
        sequenceInput->setButtons(QVector<int>{Qt::Key_C});
        sequence.addSequence(sequenceInput);
        QAnalogAxisInput analog;
        QButtonAxisInput buttonAxis;
        buttonAxis.setButtons(QVector<int>{Qt::Key_Left});
        QAbstractActionInput *actionBase = actionInput;
        QAbstractAxisInput *axisBase = &analog;
        QMouseDevice physicalMouse;
        QAbstractPhysicalDevice *physicalBase = &physicalMouse;
#if QT_VERSION_MAJOR < 6
        QPhysicalDeviceCreatedChange<QVariant> physicalCreated(&physicalMouse);
        QPhysicalDeviceCreatedChangeBase *physicalCreatedBase = &physicalCreated;
#endif

        Qt3DInput::QKeyEvent keyEvent(QEvent::KeyPress, Qt::Key_A, Qt::ControlModifier, QStringLiteral("a"));
        QT_PREPEND_NAMESPACE(QMouseEvent) qtMouse(QEvent::MouseButtonPress, QPointF(3, 4),
                                                  Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        Qt3DInput::QMouseEvent mouseEvent(qtMouse);
        QT_PREPEND_NAMESPACE(QWheelEvent) qtWheel(QPointF(5, 6), QPointF(5, 6), QPoint(0, 120), QPoint(0, 120),
                                                  Qt::NoButton, Qt::ShiftModifier, Qt::NoScrollPhase, false);
        Qt3DInput::QWheelEvent wheelEvent(qtWheel);

        bool ok = axisSetting->axes().size() == 2
               && qFuzzyCompare(axisSetting->deadZoneRadius(), 0.1f)
               && axisSetting->isSmoothEnabled()
               && accumulator.sourceAxis() == axis
               && qFuzzyCompare(accumulator.scale(), 2.0f)
               && action.inputs().contains(actionInput)
               && chord.chords().contains(chordInput)
               && sequence.sequences().contains(sequenceInput)
               && buttonAxis.buttons().contains(Qt::Key_Left)
               && actionBase != nullptr
               && actionInput->buttons().contains(Qt::Key_A)
               && axisBase != nullptr
               && physicalBase->axisCount() >= 2
#if QT_VERSION_MAJOR < 6
               && physicalCreatedBase->subjectId() == physicalMouse.id()
#endif
               && keyEvent.key() == Qt::Key_A
               && keyEvent.text() == QStringLiteral("a")
               && mouseEvent.x() == 3
               && mouseEvent.button() == Qt3DInput::QMouseEvent::LeftButton
               && wheelEvent.angleDelta().y() == 120;
        if (!ok)
            d = QStringLiteral("input state mismatch");
        return ok;
    });

    r.check("qt3d/animation-extra-nodes", [&](QString &d) {
        QClock clock;
        clock.setPlaybackRate(1.5);
        auto *clip = new QAnimationClip;
        QAnimationClipLoader loader;
        loader.setSource(QUrl(QStringLiteral("file:///walk.json")));
        QAbstractAnimationClip *clipBase = clip;
        QClipAnimator clipAnimator;
        clipAnimator.setClip(clip);
        QAbstractClipAnimator *clipAnimatorBase = &clipAnimator;
        QBlendedClipAnimator blendedAnimator;
        QChannelMapper mapper;
        auto *channelMapping = new QChannelMapping;
        channelMapping->setChannelName(QStringLiteral("scale"));
        mapper.addMapping(channelMapping);
        QAbstractChannelMapping *mappingBase = channelMapping;
        auto *blendValue = new QClipBlendValue;
        blendValue->setClip(new QAnimationClip);
        auto *baseBlendValue = new QClipBlendValue;
        baseBlendValue->setClip(new QAnimationClip);
        auto *endBlendValue = new QClipBlendValue;
        endBlendValue->setClip(new QAnimationClip);
        QAdditiveClipBlend additiveBlend;
        additiveBlend.setBaseClip(baseBlendValue);
        QLerpClipBlend lerpBlend;
        lerpBlend.setStartClip(blendValue);
        lerpBlend.setEndClip(endBlendValue);
        QAbstractClipBlendNode *blendBase = &lerpBlend;
#if QT_VERSION_MAJOR < 6
        QClipBlendNodeCreatedChange<QVariant> clipBlendCreated(&lerpBlend);
        QClipBlendNodeCreatedChangeBase *clipBlendCreatedBase = &clipBlendCreated;
#endif
        auto *morphTarget = new QMorphTarget;
        auto *attribute = new QAttribute;
        attribute->setName(QAttribute::defaultPositionAttributeName());
        morphTarget->addAttribute(attribute);
        auto *vertexMorphTarget = new QMorphTarget;
        auto *vertexAttribute = new QAttribute;
        vertexAttribute->setName(QAttribute::defaultPositionAttributeName());
        vertexMorphTarget->addAttribute(vertexAttribute);
        auto *renderer = new QGeometryRenderer;
        QMorphingAnimation morphing;
        morphing.addMorphTarget(morphTarget);
        morphing.setTarget(renderer);
        morphing.setAnimationName(QStringLiteral("morph"));
        QVertexBlendAnimation vertexBlend;
        vertexBlend.addMorphTarget(vertexMorphTarget);
        auto *skeleton = new QSkeleton;
        QSkeletonMapping skeletonMapping;
        skeletonMapping.setSkeleton(skeleton);
        QCallbackMapping callbackMapping;
        callbackMapping.setChannelName(QStringLiteral("weight"));
        SmokeAnimationCallback callback;
        callbackMapping.setCallback(qMetaTypeId<float>(), &callback);
        callback.valueChanged(QVariant(0.5));
        QAbstractAnimation *animationBase = &morphing;

        bool ok = qFuzzyCompare(clock.playbackRate(), 1.5)
               && clipBase != nullptr
               && loader.source().isValid()
               && loader.status() == QAnimationClipLoader::NotReady
               && clipAnimator.clip() == clip
               && clipAnimatorBase != nullptr
               && blendedAnimator.blendTree() == nullptr
               && mapper.mappings().contains(channelMapping)
               && mappingBase != nullptr
               && blendValue->clip() != nullptr
               && additiveBlend.baseClip() == baseBlendValue
               && lerpBlend.startClip() == blendValue
               && lerpBlend.endClip() == endBlendValue
               && blendBase != nullptr
#if QT_VERSION_MAJOR < 6
               && clipBlendCreatedBase->subjectId() == lerpBlend.id()
#endif
               && morphTarget->attributeNames().contains(QAttribute::defaultPositionAttributeName())
               && morphing.morphTargetList().contains(morphTarget)
               && morphing.target() == renderer
               && vertexBlend.morphTargetList().contains(vertexMorphTarget)
               && skeletonMapping.skeleton() == skeleton
               && callbackMapping.channelName() == QStringLiteral("weight")
               && callback.lastValue.toDouble() == 0.5
               && animationBase->animationName() == QStringLiteral("morph");
        if (!ok)
            d = QStringLiteral("animation state mismatch");
        return ok;
    });

    r.check("qt3d/raycaster-pick-events", [&](QString &d) {
        QRayCaster rayCaster;
        rayCaster.setOrigin(QVector3D(1, 2, 3));
        rayCaster.setDirection(QVector3D(0, 0, -1));
        QScreenRayCaster screenRayCaster;
        screenRayCaster.setPosition(QPoint(10, 20));
        QAbstractRayCaster *rayBase = &rayCaster;
        QRayCasterHit hit(QRayCasterHit::TriangleHit, QNodeId::createId(), 4.0f,
                          QVector3D(1, 0, 0), QVector3D(0, 1, 0), 2, 3, 4, 5);
        QPickLineEvent lineEvent(QPointF(1, 2), QVector3D(0, 1, 0), QVector3D(1, 0, 0),
                                 3.0f, 7, 8, 9, QPickEvent::LeftButton,
                                 Qt::LeftButton, Qt::NoModifier);
        QPickPointEvent pointEvent(QPointF(2, 3), QVector3D(0, 0, 1), QVector3D(1, 1, 0),
                                   2.0f, 11, QPickEvent::RightButton,
                                   Qt::RightButton, Qt::ShiftModifier);
        QPickTriangleEvent triangleEvent(QPointF(3, 4), QVector3D(1, 1, 1), QVector3D(2, 2, 2),
                                         1.0f, 13, 14, 15, 16, QPickEvent::MiddleButton,
                                         Qt::MiddleButton, Qt::ControlModifier, QVector3D(0.2f, 0.3f, 0.5f));
        QPickEvent *pickBase = &triangleEvent;

        bool ok = rayCaster.origin() == QVector3D(1, 2, 3)
               && rayCaster.direction() == QVector3D(0, 0, -1)
               && screenRayCaster.position() == QPoint(10, 20)
               && rayBase != nullptr
               && hit.type() == QRayCasterHit::TriangleHit
               && hit.vertex3Index() == 5
               && lineEvent.edgeIndex() == 7
               && pointEvent.pointIndex() == 11
               && triangleEvent.triangleIndex() == 13
               && pickBase->button() == QPickEvent::MiddleButton;
        if (!ok)
            d = QStringLiteral("ray/pick state mismatch");
        return ok;
    });
}

void checkQt3DQuickBridgeExtra(SmokeReporter &r)
{
    r.check("qt3d/quick-aspect-scene2d", [&](QString &d) {
        Qt3DCore::Quick::QQmlAspectEngine aspectEngine;
        Qt3DRender::Quick::QScene2D scene2d;
        scene2d.setRenderPolicy(Qt3DRender::Quick::QScene2D::SingleShot);
        scene2d.setMouseEnabled(false);

        auto *output = new QRenderTargetOutput(&scene2d);
        scene2d.setOutput(output);
        auto *entity = new QEntity(&scene2d);
        scene2d.addEntity(entity);
        auto *item = new QQuickItem;
        scene2d.setItem(item);

        bool ok = aspectEngine.status() == Qt3DCore::Quick::QQmlAspectEngine::Null
               && aspectEngine.qmlEngine() != nullptr
               && aspectEngine.aspectEngine() != nullptr
               && scene2d.renderPolicy() == Qt3DRender::Quick::QScene2D::SingleShot
               && !scene2d.isMouseEnabled()
               && scene2d.output() == output
               && scene2d.item() == item
               && scene2d.entities().contains(entity);
        if (!ok)
            d = QStringLiteral("quick bridge state mismatch");
        return ok;
    });
}
