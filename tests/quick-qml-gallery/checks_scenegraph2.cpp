// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// The half of the scene graph that checks_scenegraph.cpp next door left alone:
// the renderer-interface, texture, render-node and shader family, plus the
// render-target and graphics-device value types Qt 6 added when Qt Quick moved
// onto QRhi.
//
// That file's note said these "need a real GPU/render-thread context to be
// meaningful or aren't directly constructible outside one". That is true of the
// node types a live QQuickWindow hands out from its factory methods, and for a
// long time it was the reason they went unchecked entirely. Measuring settled
// it: before the scene graph is initialised those factories return null rather
// than crashing, and that null *is* the contract worth checking - it is what
// makes every headless QQuickWindow in this suite safe to construct. See
// scenegraph/factory-nodes-before-init at the end of this file. The rest of the
// group here needs no such care, and the difference is worth stating because it
// is what makes these checks safe:
//
//   * QSGRenderNode, QSGMaterialShader, QSGDynamicTexture and QSGTextureProvider
//     are *interfaces to implement*, not objects the renderer hands back. Qt
//     calls into them; a subclass that is never handed to a renderer is never
//     called, so constructing one costs nothing and touches no GPU state. This
//     is the same shape as the QSGNodeVisitor subclass next door.
//   * QQuickRenderTarget, QQuickGraphicsDevice and QQuickGraphicsConfiguration
//     are value types describing what a renderer *should* use. A null one is a
//     legal, meaningful value - it is what a QQuickWindow has before anyone
//     configures it - and fromPaintDevice() builds a real non-null one out of a
//     QImage with no graphics API involved at all.
//   * QSGRendererInterface is documented to be available from a QQuickWindow at
//     any time, including before the scene graph is initialised. Which API it
//     names is then a property of the build, so the check reads it rather than
//     asserting one.
//
// No window is shown and no scene graph is initialised anywhere in this file.
#include "../common/smokecheck.h"

#include <QImage>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSGImageNode>
#include <QSGNinePatchNode>
#include <QSGRectangleNode>
#include <QSharedPointer>

#if QT_VERSION >= QT_VERSION_CHECK(6, 7, 0)
#  include <QSGTextNode>
#endif
#include <QQuickItemGrabResult>
#include <QMatrix4x4>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRectF>
#include <QSize>
#include <QStringList>
#include <QUrl>

#include <memory>

#if QT_VERSION_MAJOR >= 6
#include <QQuickAttachedPropertyPropagator>
#include <QQuickGraphicsConfiguration>
#include <QQuickGraphicsDevice>
#include <QQuickRenderTarget>
#include <QQuickRhiItem>
#include <QQuickTextDocument>
#include <QSGDynamicTexture>
#include <QSGMaterialShader>
#include <QSGRenderNode>
#include <QSGRendererInterface>
#include <QSGRootNode>
#include <QSGTextureProvider>
#include <QTextDocument>
#endif

#if QT_VERSION_MAJOR >= 6
namespace {

// A render node is how an application draws with the graphics API directly
// inside a Qt Quick scene. Only render() is pure virtual; the rest describe
// what the node disturbs so the renderer can restore it.
class SmokeRenderNode : public QSGRenderNode
{
public:
    StateFlags changedStates() const override { return DepthState | BlendState; }
    RenderingFlags flags() const override { return BoundedRectRendering | OpaqueRendering; }
    QRectF rect() const override { return QRectF(0, 0, 32, 16); }

    // Never called: the node is not given to a renderer.
    void render(const RenderState *) override { ++renders; }

    int renders = 0;
};

// The shader half of a custom material. Qt calls these when it builds a
// pipeline; a standalone instance only carries the shader file names and the
// pipeline-state opt-in flag.
class SmokeMaterialShader : public QSGMaterialShader
{
public:
    SmokeMaterialShader()
    {
        setShaderFileName(VertexStage, QStringLiteral(":/shaders/smoke.vert.qsb"));
        setShaderFileName(FragmentStage, QStringLiteral(":/shaders/smoke.frag.qsb"));
    }
};

// A texture whose content changes between frames; updateTexture() is called
// before each use, and plain data answers the QSGTexture half safely.
class SmokeDynamicTexture : public QSGDynamicTexture
{
public:
    bool updateTexture() override { ++updates; return true; }

    // The identity the renderer batches on. A real one hashes the underlying
    // native texture; a constant is right for a texture that is never rendered.
    qint64 comparisonKey() const override { return 0x5107; }
    QSize textureSize() const override { return QSize(16, 8); }
    bool hasAlphaChannel() const override { return true; }
    bool hasMipmaps() const override { return false; }

    int updates = 0;
};

// What an item implements to hand its texture to another item - the mechanism
// behind ShaderEffectSource and layer.enabled.
class SmokeTextureProvider : public QSGTextureProvider
{
public:
    explicit SmokeTextureProvider(QSGTexture *texture) : m_texture(texture) {}

    QSGTexture *texture() const override { return m_texture; }

private:
    QSGTexture *m_texture;
};

// QQuickRhiItem (6.7) renders with QRhi into a texture; its renderer lives on
// the render thread, so constructing one touches no GPU.
class SmokeRhiRenderer : public QQuickRhiItemRenderer
{
public:
    void initialize(QRhiCommandBuffer *) override { ++initializes; }
    void synchronize(QQuickRhiItem *) override { ++synchronizes; }
    void render(QRhiCommandBuffer *) override { ++renders; }

    int initializes = 0;
    int synchronizes = 0;
    int renders = 0;
};

class SmokeRhiItem : public QQuickRhiItem
{
public:
    QQuickRhiItemRenderer *createRenderer() override { return new SmokeRhiRenderer; }
};

// The base behind QtQuick.Controls' attached style properties: a chain of
// objects that inherit a value from whichever ancestor last set one.
class SmokeStyleAttached : public QQuickAttachedPropertyPropagator
{
public:
    explicit SmokeStyleAttached(QObject *parent = nullptr)
        : QQuickAttachedPropertyPropagator(parent)
    {
        initialize();
    }

    void attachedParentChange(QQuickAttachedPropertyPropagator *newParent,
                              QQuickAttachedPropertyPropagator *oldParent) override
    {
        Q_UNUSED(oldParent);
        lastParent = newParent;
        ++parentChanges;
    }

    QQuickAttachedPropertyPropagator *lastParent = nullptr;
    int parentChanges = 0;
};

} // namespace
#endif

void checkSceneGraphRenderPath(SmokeReporter &r)
{
    r.check("scenegraph/renderer-interface", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        // Never shown, so no scene graph is initialised - which is exactly the
        // state the interface is documented to survive.
        QQuickWindow window;
        QSGRendererInterface *rendererInterface = window.rendererInterface();
        if (!rendererInterface) {
            r.skip(d, QStringLiteral("no renderer interface before scene graph init"));
            return false;
        }

        const QSGRendererInterface::GraphicsApi api = rendererInterface->graphicsApi();
        // shaderType() is one of the getters that only answers once the scene
        // graph is up - before that it is UnknownShadingLanguage, which is a
        // correct answer rather than a failure. It is called for that reason
        // and its result deliberately not asserted on.
        const QSGRendererInterface::ShaderType shaderType = rendererInterface->shaderType();
        Q_UNUSED(shaderType);

        // Which API a build defaults to is a property of the platform and the
        // configuration, so the check asks only that it is one Qt knows about.
        static const QSGRendererInterface::GraphicsApi known[] = {
            QSGRendererInterface::Software,  QSGRendererInterface::OpenVG,
            QSGRendererInterface::OpenGL,    QSGRendererInterface::Direct3D11,
            QSGRendererInterface::Vulkan,    QSGRendererInterface::Metal,
            QSGRendererInterface::Null,      QSGRendererInterface::Direct3D12
        };
        bool recognised = false;
        for (QSGRendererInterface::GraphicsApi candidate : known)
            recognised = recognised || api == candidate;

        QStringList misses;
        if (!recognised) misses << QStringLiteral("graphicsapi");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QSGRendererInterface is reached on Qt 6 here"));
        return false;
#endif
    });

    r.check("scenegraph/render-target-device-and-configuration", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        // A default-constructed one of each is the state a QQuickWindow starts
        // in: null means "you decide".
        const QQuickRenderTarget noTarget;
        const QQuickGraphicsDevice noDevice;

        // fromPaintDevice() is the software path - it takes a QImage and needs
        // no graphics API at all, which is what makes a non-null render target
        // reachable from a check that never touches a GPU.
        QImage surface(64, 32, QImage::Format_RGBA8888);
        surface.fill(Qt::transparent);
        QQuickRenderTarget target = QQuickRenderTarget::fromPaintDevice(&surface);
        target.setDevicePixelRatio(2.0);
        target.setMirrorVertically(true);

        QQuickGraphicsConfiguration configuration;
        configuration.setDepthBufferFor2D(false);
        configuration.setPreferSoftwareDevice(true);
        configuration.setPipelineCacheSaveFile(QStringLiteral("qt-smoke-pipeline.cache"));
        const QByteArrayList instanceExtensions =
            QQuickGraphicsConfiguration::preferredInstanceExtensions();

        QStringList misses;
        if (!noTarget.isNull()) misses << QStringLiteral("null-target");
        if (!noDevice.isNull()) misses << QStringLiteral("null-device");
        if (target.isNull()) misses << QStringLiteral("paintdevice-target");
        if (!qFuzzyCompare(target.devicePixelRatio(), 2.0)) misses << QStringLiteral("dpr");
        if (!target.mirrorVertically()) misses << QStringLiteral("mirror");
        if (configuration.isDepthBufferEnabledFor2D()) misses << QStringLiteral("depthbuffer");
        if (!configuration.prefersSoftwareDevice()) misses << QStringLiteral("softwaredevice");
        if (configuration.pipelineCacheSaveFile()
            != QStringLiteral("qt-smoke-pipeline.cache"))
            misses << QStringLiteral("pipelinecache");
        // Empty is a legal answer on every non-Vulkan build; this only asks
        // that the static call works.
        Q_UNUSED(instanceExtensions);
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("these Qt Quick graphics value types are Qt 6 only"));
        return false;
#endif
    });

    r.check("scenegraph/render-node-and-material-shader", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        auto *root = new QSGRootNode;
        auto *renderNode = new SmokeRenderNode;
        root->appendChildNode(renderNode);

        // Reached through the base, which is how the renderer sees it.
        QSGNode *asNode = renderNode;

        SmokeMaterialShader shader;
        shader.setFlag(QSGMaterialShader::UpdatesGraphicsPipelineState, true);

        QStringList misses;
        if (asNode->type() != QSGNode::RenderNodeType) misses << QStringLiteral("nodetype");
        if (renderNode->rect() != QRectF(0, 0, 32, 16)) misses << QStringLiteral("rect");
        if (!(renderNode->changedStates() & QSGRenderNode::BlendState))
            misses << QStringLiteral("changedstates");
        if (!(renderNode->flags() & QSGRenderNode::OpaqueRendering))
            misses << QStringLiteral("renderingflags");
        if (renderNode->renders != 0) misses << QStringLiteral("unexpected-render");
        if (!(shader.flags() & QSGMaterialShader::UpdatesGraphicsPipelineState))
            misses << QStringLiteral("shaderflags");

        delete root; // takes the render node with it
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QSGRenderNode/QSGMaterialShader are reached on Qt 6 here"));
        return false;
#endif
    });

    r.check("scenegraph/dynamic-texture-and-texture-provider", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        SmokeDynamicTexture texture;
        SmokeTextureProvider provider(&texture);

        // Both are reached through the bases Qt itself holds them by.
        QSGTexture *asTexture = &texture;
        QSGTextureProvider *asProvider = &provider;

        const bool updated = texture.updateTexture();

        int textureChangedSignals = 0;
        QObject::connect(asProvider, &QSGTextureProvider::textureChanged,
                         asProvider, [&textureChangedSignals]() { ++textureChangedSignals; });
        Q_EMIT asProvider->textureChanged();

        QStringList misses;
        if (!updated) misses << QStringLiteral("updatetexture");
        if (texture.updates != 1) misses << QStringLiteral("updatecount");
        if (asTexture->textureSize() != QSize(16, 8)) misses << QStringLiteral("texturesize");
        if (!asTexture->hasAlphaChannel()) misses << QStringLiteral("alpha");
        if (asTexture->hasMipmaps()) misses << QStringLiteral("mipmaps");
        // The QSGTexture defaults the subclass did not override.
        if (asTexture->isAtlasTexture()) misses << QStringLiteral("atlas");
        if (asTexture->normalizedTextureSubRect() != QRectF(0, 0, 1, 1))
            misses << QStringLiteral("subrect");
        if (asProvider->texture() != asTexture) misses << QStringLiteral("provider-texture");
        if (textureChangedSignals != 1) misses << QStringLiteral("texturechanged");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QSGDynamicTexture/QSGTextureProvider are reached on Qt 6 here"));
        return false;
#endif
    });

    r.check("quick/rhi-item-and-renderer", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        SmokeRhiItem item;
        item.setSampleCount(4);
        item.setColorBufferFormat(QQuickRhiItem::TextureFormat::RGBA16F);
        item.setAlphaBlending(true);
        item.setMirrorVertically(true);
        item.setFixedColorBufferWidth(128);
        item.setFixedColorBufferHeight(64);

        QQuickItem *asItem = &item;

        // Normally the scene graph calls this on the render thread and owns the
        // result. Nothing has, so the item is still the owner of nothing and
        // this check has to delete what it asked for.
        QQuickRhiItemRenderer *renderer = item.createRenderer();

        QStringList misses;
        if (item.sampleCount() != 4) misses << QStringLiteral("samplecount");
        if (item.colorBufferFormat() != QQuickRhiItem::TextureFormat::RGBA16F)
            misses << QStringLiteral("colorformat");
        if (!item.alphaBlending()) misses << QStringLiteral("alphablending");
        if (!item.isMirrorVerticallyEnabled()) misses << QStringLiteral("mirror");
        if (item.fixedColorBufferWidth() != 128) misses << QStringLiteral("fixedwidth");
        if (item.fixedColorBufferHeight() != 64) misses << QStringLiteral("fixedheight");
        if (!asItem->flags().testFlag(QQuickItem::ItemHasContents))
            misses << QStringLiteral("hascontents");
        if (!renderer) misses << QStringLiteral("renderer");
        delete renderer;
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QQuickRhiItem arrived in Qt 6.7"));
        return false;
#endif
    });

    r.check("quick/text-document-from-textedit", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        // QQuickTextDocument is documented as reachable only as a TextEdit
        // property, so the honest way to get one is to build a TextEdit - which
        // needs a QML engine but no window, the same as the component checks.
        QQmlEngine engine;
        QQmlComponent component(&engine);
        component.setData("import QtQuick\nTextEdit { text: 'qt-smoke' }", QUrl());
        if (component.isError()) {
            d = component.errorString();
            return false;
        }

        std::unique_ptr<QObject> edit(component.create());
        if (!edit) {
            d = component.errorString();
            return false;
        }

        auto *document = edit->property("textDocument").value<QQuickTextDocument *>();
        if (!document) {
            d = QStringLiteral("TextEdit has no textDocument");
            return false;
        }

        QTextDocument *backing = document->textDocument();

        QStringList misses;
        if (!backing) {
            misses << QStringLiteral("backing");
        } else {
            if (backing->toPlainText() != QStringLiteral("qt-smoke"))
                misses << QStringLiteral("text");
            if (document->isModified()) misses << QStringLiteral("modified");
        }
        if (document->status() != QQuickTextDocument::Status::Null)
            misses << QStringLiteral("status"); // nothing was loaded from a URL
        if (!document->source().isEmpty()) misses << QStringLiteral("source");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QQuickTextDocument is reached on Qt 6 here"));
        return false;
#endif
    });

    r.check("quick/attached-property-propagator", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        // Parenting propagators does not chain them: initialize() finds the parent
        // through QML's attached-property machinery, which an unregistered subclass
        // does not reach. Standalone, both accessors answer empty.
        QObject root;
        SmokeStyleAttached parentStyle(&root);
        SmokeStyleAttached childStyle(&parentStyle);

        QStringList misses;
        if (childStyle.attachedParent()) misses << QStringLiteral("unregistered-child-parent");
        if (parentStyle.attachedParent()) misses << QStringLiteral("root-has-parent");
        if (!parentStyle.attachedChildren().isEmpty())
            misses << QStringLiteral("unregistered-children");
        if (childStyle.parentChanges != 0) misses << QStringLiteral("unexpected-parentchange");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QQuickAttachedPropertyPropagator is Qt 6 only"));
        return false;
#endif
    });
}

// Nodes from a live QQuickWindow's factories, and the grab result: neither is
// constructible directly, so what they do before rendering is checked.
void checkSceneGraphFactories(SmokeReporter &r)
{
    r.check("scenegraph/factory-nodes-before-init", [&r](QString &d) {
        // The factories must be callable on a window never shown, without a graphics
        // context. Whether they return nodes varies (null on Windows, real nodes under
        // offscreen), so the check asserts that the four agree.
        QQuickWindow window;
        QSGRectangleNode *rectangle = window.createRectangleNode();
        QSGImageNode *image = window.createImageNode();
        QSGNinePatchNode *ninePatch = window.createNinePatchNode();
        int handed = int(rectangle != nullptr) + int(image != nullptr)
                   + int(ninePatch != nullptr);
        int asked = 3;
        // QSGTextNode became public API in Qt 6.7, so on anything older the
        // type does not exist to name - which is why the whole variable lives
        // inside the guard rather than being declared null outside it.
#if QT_VERSION >= QT_VERSION_CHECK(6, 7, 0)
        QSGTextNode *text = window.createTextNode();
        handed += int(text != nullptr);
        asked = 4;
        delete text;
#endif
        // The caller owns a node until it is put in the scene graph, and these
        // never are.
        delete rectangle;
        delete image;
        delete ninePatch;

        d = QStringLiteral("%1 of %2 factories answered without a scene graph")
                .arg(handed).arg(asked);
        return handed == 0 || handed == asked;
    });

    r.check("scenegraph/grab-without-window", [&r](QString &d) {
        // grabToImage() on an item with no window has nothing to grab. It
        // answers with a null QQuickItemGrabResult rather than a broken one -
        // the class itself cannot be constructed from here, its constructor
        // being private and friended to QQuickItem for exactly this path.
        QQuickItem item;
        const QSharedPointer<QQuickItemGrabResult> grab = item.grabToImage();
        d = QStringLiteral("grabToImage() without a window returned %1")
                .arg(grab.isNull() ? QLatin1String("null") : QLatin1String("a result"));
        return item.window() == nullptr && grab.isNull();
    });
}
