// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// QQuickItem and the Quick-side extension points that don't need a live,
// shown window to construct - QQuickItem itself never creates a native
// surface until it's placed under a QQuickWindow that's actually shown, the
// same "construct without showing" pattern used throughout this suite.
#include "../common/smokecheck.h"

#include <QQuickItem>
#include <QQuickPaintedItem>
// QQuickFramebufferObject's header ships unconditionally, but qtdeclarative
// only compiles its implementation when Qt has OpenGL - so without this guard
// the failure is an undefined-reference at link time, not a missing include.
#if QT_CONFIG(opengl)
#include <QQuickFramebufferObject>
#endif
#include <QQuickTransform>
#include <QQuickView>
#include <QQuickWidget>
#include <QQuickImageProvider>
#include <QQuickTextureFactory>
#include <QQuickImageResponse>
#include <QQmlEngine>
#include <QQmlExtensionInterface>
#include <QQmlInfo>
#include <QQmlListProperty>
#include <QQuickRenderControl>
#include <QMatrix4x4>
#include <QPainter>

namespace {

class MinimalPaintedItem : public QQuickPaintedItem
{
public:
    int paintCalls = 0;
    void paint(QPainter *) override { ++paintCalls; }
};

#if QT_CONFIG(opengl)
class MinimalFboRenderer : public QQuickFramebufferObject::Renderer
{
public:
    void render() override {}
};

class MinimalFbo : public QQuickFramebufferObject
{
public:
    Renderer *createRenderer() const override { return new MinimalFboRenderer; }
};
#endif

class MinimalTransform : public QQuickTransform
{
public:
    void applyTo(QMatrix4x4 *matrix) const override { matrix->translate(1, 0, 0); }
};

class MinimalTextureFactory : public QQuickTextureFactory
{
public:
    QSGTexture *createTexture(QQuickWindow *) const override { return nullptr; }
    QSize textureSize() const override { return QSize(4, 4); }
    int textureByteCount() const override { return 4 * 4 * 4; }
};

class MinimalImageResponse : public QQuickImageResponse
{
public:
    QQuickTextureFactory *textureFactory() const override { return new MinimalTextureFactory; }
};

class MinimalAsyncImageProvider : public QQuickAsyncImageProvider
{
public:
    QQuickImageResponse *requestImageResponse(const QString &, const QSize &) override {
        return new MinimalImageResponse;
    }
};

class MinimalEngineExtension : public QQmlEngineExtensionInterface
{
public:
    int initCalls = 0;
    void initializeEngine(QQmlEngine *, const char *) override { ++initCalls; }
};

} // namespace

void checkQuickItems(SmokeReporter &r)
{
    r.check("quick/item-transform-catalogue", [&](QString &d) {
        QQuickItem parent;
        auto *child = new QQuickItem(&parent);
        child->setWidth(10);
        child->setHeight(20);

        MinimalTransform transform;
        QQmlListProperty<QQuickTransform> transforms = child->transform();
        transforms.append(&transforms, &transform);

        return child->parentItem() == &parent && qFuzzyCompare(child->width(), 10.0)
            && transforms.count(&transforms) == 1;
    });
    r.check("quick/painted-item-and-fbo", [&](QString &d) {
#if !QT_CONFIG(opengl)
        r.skip(d, QStringLiteral("QQuickFramebufferObject needs Qt built with OpenGL"));
        return false;
#else
        MinimalPaintedItem paintedItem;
        paintedItem.setWidth(10);
        paintedItem.setHeight(10);
        QImage img(10, 10, QImage::Format_ARGB32);
        QPainter painter(&img);
        paintedItem.paint(&painter);
        painter.end();

        MinimalFbo fbo;
        // createRenderer() normally runs on the render thread with a GL context;
        // constructing a renderer is what is checked. Its destructor is protected (the
        // scene graph owns it).
        QQuickFramebufferObject::Renderer *renderer = fbo.createRenderer();
        return paintedItem.paintCalls == 1 && renderer != nullptr;
#endif
    });
    r.check("quick/view-and-widget-construct", [&](QString &d) {
        QQuickView view;
        view.resize(100, 100);
        QQuickWidget widget;
        widget.resize(100, 100);
        return view.size() == QSize(100, 100) && widget.size() == QSize(100, 100);
    });
    r.check("quick/image-provider-and-async-response", [&](QString &d) {
        QQmlEngine engine;
        auto *provider = new QQuickImageProvider(QQuickImageProvider::Pixmap);
        engine.addImageProvider(QStringLiteral("qt-smoke"), provider);
        // Reached through the real base every image provider derives from.
        QQmlImageProviderBase *base = engine.imageProvider(QStringLiteral("qt-smoke"));

        MinimalAsyncImageProvider asyncProvider;
        QQuickImageResponse *response = asyncProvider.requestImageResponse(
            QStringLiteral("id"), QSize(4, 4));
        QQuickTextureFactory *factory = response->textureFactory();

        bool ok = base == provider && factory != nullptr && factory->textureSize() == QSize(4, 4);
        delete response;
        return ok;
    });
    r.check("quick/engine-extension-and-qmlinfo", [&](QString &d) {
        MinimalEngineExtension extension;
        QQmlEngine engine;
        extension.initializeEngine(&engine, "QtSmokeTest");

        QObject source;
        qmlInfo(&source) << "qt-smoke info message";
        qmlWarning(&source) << "qt-smoke warning message";

        return extension.initCalls == 1;
    });
    r.check("quick/rendercontrol", [&](QString &d) {
        // Not attempted: the grab result type (private constructor, friended to
        // QQuickItem) and the TextEdit document wrapper (it casts its parent to a
        // private type and crashes on a plain QQuickItem).
        QQuickRenderControl renderControl;
        return renderControl.parent() == nullptr;
    });
}
