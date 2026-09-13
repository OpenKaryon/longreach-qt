// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

#include "glcaps.h"

#include <QFrame>
#include <QLabel>
#include <QOffscreenSurface>
#include <QOpenGLContext>
#include <QOpenGLFunctions>
#include <QVBoxLayout>

// GL_MAX_VERTEX_TEXTURE_IMAGE_UNITS. Spelled out rather than included, since
// QOpenGLFunctions only guarantees the ES2 subset of the enums and this file
// must build against both desktop GL and ANGLE.
static const unsigned int kMaxVertexTextureImageUnits = 0x8B4C;

QString GlCaps::describe() const
{
    if (!contextCreated)
        return QStringLiteral("no OpenGL context could be created on this machine");
    return QStringLiteral("%1 - %2 (%3), reporting OpenGL %4.%5")
            .arg(vendor, renderer, version)
            .arg(major).arg(minor);
}

const GlCaps &glCaps()
{
    static GlCaps caps = [] {
        GlCaps c;
        QOffscreenSurface surface;
        surface.create();
        QOpenGLContext ctx;
        if (!ctx.create() || !ctx.makeCurrent(&surface))
            return c;

        c.contextCreated = true;
        c.major = ctx.format().majorVersion();
        c.minor = ctx.format().minorVersion();
        c.gpuShader4 = ctx.hasExtension(QByteArrayLiteral("GL_EXT_gpu_shader4"));

        QOpenGLFunctions *f = ctx.functions();
        f->initializeOpenGLFunctions();
        auto str = [f](unsigned int name) {
            const GLubyte *s = f->glGetString(name);
            return s ? QString::fromLatin1(reinterpret_cast<const char *>(s)) : QString();
        };
        c.vendor = str(GL_VENDOR);
        c.renderer = str(GL_RENDERER);
        c.version = str(GL_VERSION);

        GLint units = 0;
        f->glGetIntegerv(kMaxVertexTextureImageUnits, &units);
        c.vertexTextureUnits = int(units);

        ctx.doneCurrent();
        return c;
    }();
    return caps;
}

QWidget *makeUnsupportedPlaceholder(const QString &title, const QString &why)
{
    auto *frame = new QFrame;
    frame->setFrameShape(QFrame::StyledPanel);
    frame->setMinimumSize(360, 300);

    auto *heading = new QLabel(QStringLiteral("<b>%1</b>").arg(title));
    heading->setTextFormat(Qt::RichText);

    auto *body = new QLabel(why);
    body->setWordWrap(true);
    body->setAlignment(Qt::AlignTop | Qt::AlignLeft);

    auto *driver = new QLabel(glCaps().describe());
    driver->setWordWrap(true);
    driver->setEnabled(false);   // greyed: it is context, not the message

    auto *layout = new QVBoxLayout(frame);
    layout->addWidget(heading);
    layout->addWidget(body);
    layout->addStretch(1);
    layout->addWidget(driver);
    return frame;
}
