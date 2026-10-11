// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// QtOpenGL coverage for Qt 4.8.7. The modern gl-heavy sources test the layers
// built on top of OpenGL; this file tests the API applications actually used in
// the Qt 4 era: QGLWidget, contexts, textures, VBOs, FBOs, GLSL and pbuffers.
#include "../common/smokecheck.h"
#include "qt4_opengl.h"

#include <QGLBuffer>
#include <QGLColormap>
#include <QGLContext>
#include <QGLFormat>
#include <QGLFramebufferObject>
#include <QGLFramebufferObjectFormat>
#include <QGLFunctions>
#include <QGLPixelBuffer>
#include <QGLShaderProgram>
#include <QGLWidget>

#include <QColor>
#include <QImage>
#include <QLabel>
#include <QPixmap>
#include <QSizePolicy>
#include <QStringList>
#include <QTime>
#include <QTimer>
#include <QVBoxLayout>
#include <QWidget>
#include <QApplication>
#include <QDir>
#include <QEventLoop>
#include <memory>

namespace {

class LegacyGlView : public QGLWidget
{
public:
    explicit LegacyGlView(QWidget *parent = 0)
        : QGLWidget(parent)
    {
        setMinimumSize(480, 340);
        setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Expanding);
        QTimer *timer = new QTimer(this);
        connect(timer, SIGNAL(timeout()), this, SLOT(updateGL()));
        timer->start(16);
    }

protected:
    void initializeGL() override
    {
        qglClearColor(QColor(18, 24, 38));
        glDisable(GL_DEPTH_TEST);
    }

    void resizeGL(int width, int height) override
    {
        glViewport(0, 0, width, height > 0 ? height : 1);
        glMatrixMode(GL_PROJECTION);
        glLoadIdentity();
        glOrtho(-1.25, 1.25, -1.0, 1.0, -1.0, 1.0);
        glMatrixMode(GL_MODELVIEW);
    }

    void paintGL() override
    {
        glClear(GL_COLOR_BUFFER_BIT);
        glMatrixMode(GL_MODELVIEW);
        glLoadIdentity();
        const int elapsed = QTime(0, 0).msecsTo(QTime::currentTime());
        glRotatef(float(elapsed % 10000) * 0.036f, 0.0f, 0.0f, 1.0f);

        glBegin(GL_TRIANGLES);
        glColor3f(0.20f, 0.75f, 1.00f); glVertex2f( 0.0f,  0.72f);
        glColor3f(1.00f, 0.35f, 0.35f); glVertex2f(-0.75f, -0.55f);
        glColor3f(0.45f, 1.00f, 0.45f); glVertex2f( 0.75f, -0.55f);
        glEnd();

        glColor3f(1.0f, 1.0f, 1.0f);
        glBegin(GL_LINE_LOOP);
        glVertex2f( 0.0f,  0.78f);
        glVertex2f(-0.82f, -0.60f);
        glVertex2f( 0.82f, -0.60f);
        glEnd();
    }
};

static QString glString(GLenum name)
{
    const GLubyte *value = glGetString(name);
    return value ? QString::fromLatin1(reinterpret_cast<const char *>(value))
                 : QStringLiteral("unavailable");
}

static bool requireContext(SmokeReporter &r, LegacyGlView &view, QString &detail)
{
    if (!view.isValid()) {
        r.skip(detail, QStringLiteral("the OpenGL driver could not create a QGLWidget context"));
        return false;
    }
    view.makeCurrent();
    return true;
}

} // namespace

QWidget *buildQt4OpenGLGallery()
{
    QWidget *page = new QWidget;
    QVBoxLayout *layout = new QVBoxLayout(page);
    LegacyGlView *view = new LegacyGlView(page);
    view->makeCurrent();

    QStringList details;
    details << QStringLiteral("QtOpenGL compatibility renderer")
            << QStringLiteral("OpenGL: %1").arg(glString(GL_VERSION))
            << QStringLiteral("Vendor: %1").arg(glString(GL_VENDOR))
            << QStringLiteral("Renderer: %1").arg(glString(GL_RENDERER));
    QLabel *label = new QLabel(details.join(QStringLiteral("\n")), page);
    label->setTextInteractionFlags(Qt::TextSelectableByMouse);
    layout->addWidget(label);
    layout->addWidget(view, 1);
    return page;
}

void checkQt4OpenGL(SmokeReporter &r)
{
    r.check("qgl/format-options", [](QString &d) {
        QGLFormat format;
        format.setDoubleBuffer(true);
        format.setDepth(true);
        format.setStencil(true);
        format.setSampleBuffers(true);
        format.setSamples(4);
        format.setVersion(2, 1);
        format.setProfile(QGLFormat::CompatibilityProfile);
        const QGLFormat copy(format);
        return copy.doubleBuffer() && copy.depth() && copy.stencil()
            && copy.sampleBuffers() && copy.samples() == 4
            && copy.majorVersion() == 2 && copy.minorVersion() == 1
            && copy.profile() == QGLFormat::CompatibilityProfile;
    });

    r.check("qgl/colormap-value-type", [](QString &d) {
        QGLColormap map;
        map.setEntry(0, QColor(Qt::red));
        map.setEntry(1, QColor(Qt::green));
        QGLColormap copy(map);
        copy.detach();
        copy.setEntry(1, QColor(Qt::blue));
        return map.size() >= 2 && map.entryColor(0) == QColor(Qt::red)
            && map.entryColor(1) == QColor(Qt::green)
            && copy.entryColor(1) == QColor(Qt::blue)
            && map.find(qRgb(255, 0, 0)) == 0;
    });

    std::unique_ptr<LegacyGlView> viewPointer;
    r.check("qgl/widget-create", [&](QString &) {
        viewPointer.reset(new LegacyGlView);
        return viewPointer.get() != nullptr;
    });
    LegacyGlView &view = *viewPointer;
    view.resize(96, 96);
    view.show();
    QApplication::processEvents();

    r.check("qgl/widget-context", [&](QString &d) {
        if (!QGLFormat::hasOpenGL()) {
            d = QStringLiteral("QGLFormat::hasOpenGL() is false");
            return false;
        }
        if (!view.isValid()) {
            d = QStringLiteral("QGLWidget did not create a valid context");
            return false;
        }
        view.makeCurrent();
        const QGLContext *context = view.context();
        return context && context->isValid()
            && QGLContext::currentContext() == context
            && !glString(GL_VERSION).isEmpty();
    });

    r.check("qgl/image-conversion", [](QString &d) {
        QImage source(3, 2, QImage::Format_ARGB32);
        source.fill(qRgba(12, 34, 56, 200));
        const QImage converted = QGLWidget::convertToGLFormat(source);
        return converted.size() == source.size() && converted.depth() == 32
            && !converted.isNull();
    });

    r.check("qgl/texture-upload", [&](QString &d) {
        if (!requireContext(r, view, d)) return false;
        QImage image(4, 4, QImage::Format_ARGB32);
        image.fill(qRgba(30, 120, 220, 255));
        const GLuint texture = view.bindTexture(image);
        const bool valid = texture != 0 && glIsTexture(texture) == GL_TRUE;
        if (texture) view.deleteTexture(texture);
        return valid;
    });

    r.check("qgl/vertex-buffer", [&](QString &d) {
        if (!requireContext(r, view, d)) return false;
        QGLBuffer buffer(QGLBuffer::VertexBuffer);
        if (!buffer.create()) {
            r.skip(d, QStringLiteral("the OpenGL driver has no vertex-buffer support"));
            return false;
        }
        const GLfloat vertices[] = { -1.0f, 0.0f, 1.0f, 0.0f };
        const bool bound = buffer.bind();
        if (bound) buffer.allocate(vertices, int(sizeof(vertices)));
        const bool ok = bound && buffer.isCreated() && buffer.bufferId() != 0
            && buffer.size() == int(sizeof(vertices));
        buffer.release();
        buffer.destroy();
        return ok;
    });

    r.check("qgl/framebuffer-render-readback", [&](QString &d) {
        if (!requireContext(r, view, d)) return false;
        if (!QGLFramebufferObject::hasOpenGLFramebufferObjects()) {
            r.skip(d, QStringLiteral("the OpenGL driver has no framebuffer objects"));
            return false;
        }
        QGLFramebufferObjectFormat format;
        format.setAttachment(QGLFramebufferObject::CombinedDepthStencil);
        QGLFramebufferObject fbo(QSize(16, 16), format);
        if (!fbo.isValid() || !fbo.bind()) {
            d = QStringLiteral("framebuffer object creation or binding failed");
            return false;
        }
        glViewport(0, 0, 16, 16);
        glClearColor(0.8f, 0.1f, 0.2f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        fbo.release();
        const QImage result = fbo.toImage();
        view.makeCurrent();
        return result.size() == QSize(16, 16) && !result.isNull()
            && qRed(result.pixel(8, 8)) > 150;
    });

    r.check("qgl/shader-program", [&](QString &d) {
        if (!requireContext(r, view, d)) return false;
        if (!QGLShaderProgram::hasOpenGLShaderPrograms(view.context())
                || !QGLShader::hasOpenGLShaders(QGLShader::Vertex, view.context())
                || !QGLShader::hasOpenGLShaders(QGLShader::Fragment, view.context())) {
            r.skip(d, QStringLiteral("the OpenGL driver has no GLSL shader programs"));
            return false;
        }
        QGLShaderProgram program(view.context());
        const bool vertex = program.addShaderFromSourceCode(QGLShader::Vertex,
            "attribute vec2 position; void main() { gl_Position = vec4(position, 0.0, 1.0); }");
        const bool fragment = program.addShaderFromSourceCode(QGLShader::Fragment,
            "void main() { gl_FragColor = vec4(0.2, 0.4, 0.6, 1.0); }");
        program.bindAttributeLocation("position", 0);
        const bool linked = vertex && fragment && program.link();
        const bool bound = linked && program.bind();
        const bool ok = bound && program.isLinked() && program.programId() != 0
            && program.attributeLocation("position") == 0;
        program.release();
        return ok;
    });

    r.check("qgl/pixel-buffer", [&](QString &d) {
        if (!requireContext(r, view, d)) return false;
        if (!QGLPixelBuffer::hasOpenGLPbuffers()) {
            r.skip(d, QStringLiteral("the OpenGL driver has no pixel buffers"));
            return false;
        }
        QGLPixelBuffer buffer(QSize(12, 10), view.format(), &view);
        if (!buffer.isValid() || !buffer.makeCurrent()) {
            r.skip(d, QStringLiteral("the driver advertised pbuffers but could not create one"));
            return false;
        }
        glViewport(0, 0, 12, 10);
        glClearColor(0.1f, 0.7f, 0.2f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        const QImage image = buffer.toImage();
        buffer.doneCurrent();
        view.makeCurrent();
        return buffer.size() == QSize(12, 10) && image.size() == buffer.size()
            && !image.isNull();
    });

    r.check("qgl/shared-contexts", [&](QString &d) {
        if (!requireContext(r, view, d)) return false;
        QGLWidget shared(view.format(), 0, &view);
        if (!shared.isValid()) {
            r.skip(d, QStringLiteral("the driver could not create a second shared context"));
            return false;
        }
        return shared.isSharing()
            && QGLContext::areSharing(view.context(), shared.context());
    });

    // QGLFunctions is the one class in the Qt 5/6 widgets sweep that Qt 4 has
    // and widgets-gallery cannot reach: it needs QtOpenGL, which that
    // application does not link. It belongs here for the same reason it exists -
    // it resolves the ES-subset entry points against the current context.
    r.check("qgl/functions-resolve", [&](QString &d) {
        if (!requireContext(r, view, d)) return false;
        QGLFunctions functions(view.context());
        functions.initializeGLFunctions(view.context());
        // openGLFeatures() answers per context rather than per build, so this is
        // a report rather than an assertion - a VM driver without framebuffer
        // objects is a valid answer here.
        const QGLFunctions::OpenGLFeatures features = functions.openGLFeatures();

        // GL1.1 does not guarantee glBlendColor. Exercise its resolved pointer
        // only when the current driver advertises it; framebuffer readback
        // remains useful on the Win95 software renderer too.
        if (features & QGLFunctions::BlendColor)
            functions.glBlendColor(0.0f, 0.0f, 1.0f, 1.0f);
        glClearColor(0.0f, 0.0f, 1.0f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        const QImage frame = view.grabFrameBuffer();
        if (frame.isNull()) {
            d = QStringLiteral("grabFrameBuffer() returned a null image");
            return false;
        }
        const QRgb pixel = frame.pixel(1, 1);
        d = QStringLiteral("features=0x%1 pixel=%2,%3,%4 current=%5")
                .arg(int(features), 0, 16).arg(qRed(pixel)).arg(qGreen(pixel)).arg(qBlue(pixel))
                .arg(QGLContext::currentContext() == view.context() ? QStringLiteral("view")
                                                                    : QStringLiteral("other"));
        return qBlue(pixel) > 200;
    });
}

void checkQt4OpenGLGallery(SmokeReporter &r)
{
    std::unique_ptr<QWidget> gallery;
    r.check("qgl/gallery-create", [&](QString &) {
        gallery.reset(buildQt4OpenGLGallery());
        gallery->resize(760, 500);
        gallery->show();
        QApplication::processEvents();
        QEventLoop loop;
        QTimer::singleShot(80, &loop, SLOT(quit()));
        loop.exec();
        return gallery->isVisible() && gallery->findChild<QGLWidget *>() != nullptr;
    });
    r.check("qgl/gallery-triangle-render", [&](QString &d) {
        QGLWidget *view = gallery->findChild<QGLWidget *>();
        if (!view || !view->isValid()) {
            r.skip(d, QStringLiteral("gallery has no valid GL context on this display"));
            return false;
        }
        view->makeCurrent();
        view->updateGL();
        const QImage frame = view->grabFrameBuffer();
        if (frame.isNull()) return false;
        const QRgb center = frame.pixel(frame.width() / 2, frame.height() / 2);
        // The fixed-function triangle covers the center and must differ from
        // the dark clear color; RGB interpolation also produces a bright pixel.
        const bool triangle = qRed(center) + qGreen(center) + qBlue(center) > 200;
        const QString path = QDir(QCoreApplication::applicationDirPath()).filePath("gl-gallery-frame.png");
        const bool saved = frame.save(path, "PNG");
        d = QStringLiteral("%1 center=%2,%3,%4 %5x%6").arg(path).arg(qRed(center)).arg(qGreen(center))
                .arg(qBlue(center)).arg(frame.width()).arg(frame.height());
        return triangle && saved;
    });
}
