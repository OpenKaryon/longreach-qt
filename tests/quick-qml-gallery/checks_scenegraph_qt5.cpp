// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// The three public Qt 5 scene-graph APIs removed in Qt 6. QSGEngine is tested
// with a real current OpenGL context and renderer; the RHI shader class is an
// application extension point, so a concrete subclass exercises its flags and
// virtual update surface without inventing renderer-owned RenderState data.
#include "../common/smokecheck.h"

#include <QOffscreenSurface>
#include <QOpenGLContext>
#include <QScopedPointer>
#include <QSGAbstractRenderer>
#include <QSGEngine>
#include <QSGMaterialRhiShader>
#include <QSGRectangleNode>
#include <QSGRootNode>

namespace {

class SmokeRhiShader final : public QSGMaterialRhiShader
{
public:
    SmokeRhiShader() { setFlag(UpdatesGraphicsPipelineState); }

    bool updateUniformData(RenderState &, QSGMaterial *, QSGMaterial *) override
    {
        ++uniformUpdates;
        return true;
    }

    bool updateGraphicsPipelineState(RenderState &, GraphicsPipelineState *state,
                                     QSGMaterial *, QSGMaterial *) override
    {
        ++pipelineUpdates;
        if (state)
            state->cullMode = GraphicsPipelineState::CullBack;
        return state != nullptr;
    }

    char const *const *attributeNames() const override
    {
        static const char *const attributes[] = { "vertex", nullptr };
        return attributes;
    }

    int uniformUpdates = 0;
    int pipelineUpdates = 0;
};

} // namespace

void checkQt5SceneGraphEngine(SmokeReporter &r)
{
    r.check("scenegraph/qt5-engine-renderer", [&](QString &d) {
        QOpenGLContext context;
        if (!context.create()) {
            r.skip(d, QStringLiteral("no OpenGL context"));
            return false;
        }

        QOffscreenSurface surface;
        surface.setFormat(context.format());
        surface.create();
        if (!surface.isValid() || !context.makeCurrent(&surface)) {
            r.skip(d, QStringLiteral("no usable offscreen OpenGL surface"));
            return false;
        }

        QSGEngine engine;
        engine.initialize(&context);
        QScopedPointer<QSGAbstractRenderer> renderer(engine.createRenderer());
        if (renderer.isNull()) {
            d = QStringLiteral("QSGEngine::createRenderer returned null");
            engine.invalidate();
            context.doneCurrent();
            return false;
        }

        QSGRootNode root;
        QSGRectangleNode *rectangle = engine.createRectangleNode();
        if (!rectangle) {
            d = QStringLiteral("QSGEngine::createRectangleNode returned null");
            engine.invalidate();
            context.doneCurrent();
            return false;
        }
        rectangle->setRect(QRectF(0, 0, 16, 16));
        rectangle->setColor(Qt::green);
        root.appendChildNode(rectangle);

        renderer->setRootNode(&root);
        renderer->setDeviceRect(QSize(32, 32));
        renderer->setViewportRect(QSize(32, 32));
        renderer->setProjectionMatrixToRect(QRectF(0, 0, 32, 32));
        renderer->setClearColor(Qt::black);
        renderer->setClearMode(QSGAbstractRenderer::ClearColorBuffer);
        renderer->renderScene();

        const bool ok = renderer->rootNode() == &root
            && renderer->deviceRect().size() == QSize(32, 32)
            && renderer->clearColor() == QColor(Qt::black);
        renderer.reset();
        engine.invalidate();
        context.doneCurrent();
        if (!ok)
            d = QStringLiteral("renderer did not retain its configured scene");
        return ok;
    });

    r.check("scenegraph/qt5-rhi-material-shader", [&](QString &d) {
        SmokeRhiShader shader;
        if (!shader.flags().testFlag(QSGMaterialRhiShader::UpdatesGraphicsPipelineState)) {
            d = QStringLiteral("RHI shader did not retain its pipeline-state flag");
            return false;
        }
        return shader.attributeNames() != nullptr;
    });
}
