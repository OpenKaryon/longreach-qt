// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Platform texture interfaces need an initialized scene graph and a real
// backend. Each probe therefore runs in a fresh child process, selects its API
// before QApplication exists, renders an image-backed texture, and reads the
// native handle on the render thread after Qt committed the upload.

#include "../common/smokecheck.h"

#if QT_VERSION_MAJOR >= 6

#include <QCoreApplication>
#include <QImage>
#include <QProcess>
#include <QProcessEnvironment>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSGRendererInterface>
#include <QSGSimpleTextureNode>
#include <QSGTexture>
#include <QTimer>
#include <QtQuick/qsgtexture_platform.h>

#include <atomic>
#include <cstdio>
#include <cstdlib>

namespace {

class SmokeNativeTextureItem : public QQuickItem
{
public:
    explicit SmokeNativeTextureItem(const QByteArray &backend)
        : m_backend(backend)
    {
        setFlag(ItemHasContents);
        setWidth(32);
        setHeight(32);
    }

    bool complete() const { return m_complete.load(); }
    bool succeeded() const { return m_succeeded.load(); }
    bool supported() const { return m_supported.load(); }

protected:
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) override
    {
        QSGSimpleTextureNode *node = static_cast<QSGSimpleTextureNode *>(oldNode);
        if (!node) {
            QImage image(32, 32, QImage::Format_RGBA8888);
            image.fill(Qt::magenta);
            QSGTexture *texture = window()->createTextureFromImage(
                image, QQuickWindow::TextureHasAlphaChannel);
            if (!texture) {
                m_complete = true;
                return nullptr;
            }
            node = new QSGSimpleTextureNode;
            node->setOwnsTexture(true);
            node->setTexture(texture);
            node->setRect(boundingRect());
            m_texture = texture;
            return node;
        }

        bool ok = false;
        if (m_backend == "opengl") {
#if QT_CONFIG(opengl)
            const auto *native =
                m_texture->nativeInterface<QNativeInterface::QSGOpenGLTexture>();
            m_supported = native != nullptr;
            ok = native && native->nativeTexture() != 0;
#endif
        } else if (m_backend == "vulkan") {
#if QT_CONFIG(vulkan)
            const auto *native =
                m_texture->nativeInterface<QNativeInterface::QSGVulkanTexture>();
            m_supported = native != nullptr;
            ok = native && native->nativeImage() != VK_NULL_HANDLE
                 && native->nativeImageLayout() != VK_IMAGE_LAYOUT_UNDEFINED;
#endif
        } else if (m_backend == "metal") {
#if QT_CONFIG(metal)
            const auto *native =
                m_texture->nativeInterface<QNativeInterface::QSGMetalTexture>();
            m_supported = native != nullptr;
            ok = native && native->nativeTexture();
#endif
        } else if (m_backend == "d3d11") {
#ifdef Q_OS_WIN
            const auto *native =
                m_texture->nativeInterface<QNativeInterface::QSGD3D11Texture>();
            m_supported = native != nullptr;
            ok = native && native->nativeTexture();
#endif
        } else if (m_backend == "d3d12") {
#ifdef Q_OS_WIN
            const auto *native =
                m_texture->nativeInterface<QNativeInterface::QSGD3D12Texture>();
            m_supported = native != nullptr;
            ok = native && native->nativeTexture();
            if (native)
                Q_UNUSED(native->nativeResourceState());
#endif
        }
        m_succeeded = ok;
        m_complete = true;
        return node;
    }

private:
    QByteArray m_backend;
    QSGTexture *m_texture = nullptr;
    std::atomic_bool m_complete { false };
    std::atomic_bool m_succeeded { false };
    std::atomic_bool m_supported { false };
};

static QSGRendererInterface::GraphicsApi graphicsApiFor(const QByteArray &backend)
{
    if (backend == "opengl") return QSGRendererInterface::OpenGL;
    if (backend == "vulkan") return QSGRendererInterface::Vulkan;
    if (backend == "metal") return QSGRendererInterface::Metal;
    if (backend == "d3d11") return QSGRendererInterface::Direct3D11;
    if (backend == "d3d12") return QSGRendererInterface::Direct3D12;
    return QSGRendererInterface::Unknown;
}

static void addBackendCheck(SmokeReporter &r, const QByteArray &backend,
                            bool compiledIn)
{
    r.check(QStringLiteral("scenegraph/native-texture-%1")
                .arg(QString::fromLatin1(backend)),
            [&r, backend, compiledIn](QString &d) {
        if (!compiledIn) {
            r.skip(d, QStringLiteral("backend not compiled for this target"));
            return false;
        }
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
                    QStringList() << QStringLiteral("--native-texture-probe")
                                  << QString::fromLatin1(backend));
        if (!child.waitForStarted(3000) || !child.waitForFinished(10000)) {
            d = QStringLiteral("probe did not finish: %1").arg(child.errorString());
            return false;
        }
        if (child.exitStatus() == QProcess::NormalExit && child.exitCode() == 77) {
            const QString reason = QString::fromLocal8Bit(child.readAllStandardError()).trimmed();
            r.skip(d, QStringLiteral("selected graphics API is unavailable at runtime")
                          + (reason.isEmpty() ? QString()
                                              : QStringLiteral(": ") + reason.section(QLatin1Char('\n'), -1)));
            return false;
        }
        d = QString::fromLocal8Bit(child.readAllStandardError()).trimmed();
        return child.exitStatus() == QProcess::NormalExit && child.exitCode() == 0;
    });
}

} // namespace

bool configureNativeTextureProbe(const QByteArray &backend)
{
    const QSGRendererInterface::GraphicsApi api = graphicsApiFor(backend);
    if (api == QSGRendererInterface::Unknown)
        return false;
    QQuickWindow::setGraphicsApi(api);
    return true;
}

int runNativeTextureProbe(const QByteArray &backend)
{
    QQuickWindow window;
    window.resize(48, 48);
    // Without a handler Qt Quick stops on qFatal when the graphics API cannot
    // be initialized (no D3D12 on Windows 7, no D3D11 device in a VM without
    // 3D). That is an unavailable API, reported as a skip.
    QObject::connect(&window, &QQuickWindow::sceneGraphError, &window,
                     [](QQuickWindow::SceneGraphError, const QString &message) {
        std::fprintf(stderr, "%s\n", qPrintable(message));
        std::fflush(stderr);
        std::_Exit(77);
    }, Qt::DirectConnection);
    SmokeNativeTextureItem item(backend);
    item.setParentItem(window.contentItem());

    QTimer updates;
    QObject::connect(&updates, &QTimer::timeout, [&]() {
        item.update();
        if (item.complete())
            QCoreApplication::quit();
    });
    updates.start(25);
    QTimer::singleShot(7000, qApp, &QCoreApplication::quit);
    window.show();
    const int eventResult = qApp->exec();
    if (eventResult != 0 || !item.complete())
        return 77;
    if (!item.supported())
        return 77;
    return item.succeeded() ? 0 : 4;
}

void checkNativeTextures(SmokeReporter &r)
{
#if QT_CONFIG(opengl)
    const bool openGl = true;
#else
    const bool openGl = false;
#endif
#if QT_CONFIG(vulkan)
    const bool vulkan = true;
#else
    const bool vulkan = false;
#endif
#if QT_CONFIG(metal)
    const bool metal = true;
#else
    const bool metal = false;
#endif
#ifdef Q_OS_WIN
    const bool windows = true;
#else
    const bool windows = false;
#endif
    addBackendCheck(r, "opengl", openGl);
    addBackendCheck(r, "vulkan", vulkan);
    addBackendCheck(r, "metal", metal);
    addBackendCheck(r, "d3d11", windows);
    addBackendCheck(r, "d3d12", windows);
}

#else

void checkNativeTextures(SmokeReporter &r)
{
    r.check("scenegraph/native-textures", [&r](QString &d) {
        r.skip(d, QStringLiteral("native QSG texture interfaces are Qt 6 only"));
        return false;
    });
}

#endif
