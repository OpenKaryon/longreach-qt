// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Visual Qt3D tab: a Qt3DWindow embedded via createWindowContainer, showing a
// catalogue of mesh types and material types on a custom lit/framegraph scene,
// with an orbit camera controller, object picking, and a skybox-less text
// label. This is the GPU-heavy counterpart of the widgets/graphics galleries.
#include "gl-heavy.h"
#include "glcaps.h"

#include <QWidget>
#include <QVBoxLayout>
#include <QLabel>
#include <QEvent>
#include <QMouseEvent>
#include <QOpenGLContext>
#include <QOpenGLFunctions>
#include <QOpenGLWindow>
#include <QPointer>
#include <QImage>
#include <QPainter>
#include <QTimer>

#include <Qt3DExtras/Qt3DWindow>
#include <Qt3DExtras/QOrbitCameraController>
#include <Qt3DExtras/QForwardRenderer>
#include <Qt3DExtras/QPhongMaterial>
#include <Qt3DExtras/QPhongAlphaMaterial>
#include <Qt3DExtras/QGoochMaterial>
#include <Qt3DExtras/QDiffuseSpecularMaterial>
#include <Qt3DExtras/QMetalRoughMaterial>
#include <Qt3DExtras/QCuboidMesh>
#include <Qt3DExtras/QSphereMesh>
#include <Qt3DExtras/QPlaneMesh>
#include <Qt3DExtras/QCylinderMesh>
#include <Qt3DExtras/QConeMesh>
#include <Qt3DExtras/QTorusMesh>
#include <Qt3DExtras/QText2DEntity>

#include <Qt3DCore/QEntity>
#include <Qt3DCore/QTransform>
#include <Qt3DCore/QAspectEngine>

#include <Qt3DRender/QCamera>
#include <Qt3DRender/QCameraLens>
#include <Qt3DRender/QGeometryRenderer>
#include <Qt3DRender/QMaterial>
#include <Qt3DRender/QPointLight>
#include <Qt3DRender/QDirectionalLight>
#include <Qt3DRender/QSpotLight>
#include <Qt3DRender/QObjectPicker>
#include <Qt3DRender/QPickEvent>
#include <Qt3DRender/QLayer>

#include <Qt3DInput/QInputAspect>
#include <Qt3DInput/QInputSettings>

#include <Qt3DLogic/QLogicAspect>
#include <Qt3DLogic/QFrameAction>

#include <QFont>
#include <QColor>
#include <QQuaternion>

#ifdef Q_OS_WIN
# include <windows.h>
#endif
#ifdef Q_OS_MACOS
# include <OpenGL/gl.h>
#else
# include <GL/gl.h>
#endif
#include <math.h>

namespace {

static const float kPi = 3.14159265358979323846f;

// A single row of entities: one mesh type paired with one material type, so
// the whole mesh/material catalogue is visible at a glance.
Qt3DCore::QEntity *makeShowcaseEntity(Qt3DCore::QEntity *parent, Qt3DRender::QGeometryRenderer *mesh,
                                       Qt3DRender::QMaterial *material, const QVector3D &pos)
{
    auto *entity = new Qt3DCore::QEntity(parent);
    auto *transform = new Qt3DCore::QTransform;
    transform->setTranslation(pos);
    entity->addComponent(mesh);
    entity->addComponent(material);
    entity->addComponent(transform);
    return entity;
}


// Where the driver cannot run Qt3D's modern pipeline the lights do not reach
// the GL2 shaders and lit materials go black; raising the ambient term keeps
// the meshes visible (the Gooch material needs no light anyway).
static void makeVisibleWithoutLights(Qt3DExtras::QPhongMaterial *m, const QColor &c)
{
    if (glCaps().qt3dFullySupported())
        return;
    m->setAmbient(c.darker(150));
}

class Compat3DWindow : public QOpenGLWindow
{
public:
    Compat3DWindow()
    {
        connect(&m_timer, &QTimer::timeout, this, [this]() {
            m_spin = fmodf(m_spin + 1.0f, 360.0f);
            update();
        });
        m_timer.start(33);
    }

protected:
    void initializeGL() override
    {
        glClearColor(0.118f, 0.133f, 0.157f, 1.0f);
        glEnable(GL_DEPTH_TEST);
        glEnable(GL_LIGHTING);
        glEnable(GL_LIGHT0);
        glEnable(GL_LIGHT1);
        glEnable(GL_COLOR_MATERIAL);
        glColorMaterial(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE);
        glShadeModel(GL_SMOOTH);
        glEnable(GL_NORMALIZE);

        const GLfloat ambient[] = { 0.35f, 0.35f, 0.35f, 1.0f };
        glLightModelfv(GL_LIGHT_MODEL_AMBIENT, ambient);
        const GLfloat light0[] = { 8.0f, 10.0f, 10.0f, 1.0f };
        const GLfloat light1[] = { -0.5f, -1.0f, -0.5f, 0.0f };
        glLightfv(GL_LIGHT0, GL_POSITION, light0);
        glLightfv(GL_LIGHT1, GL_POSITION, light1);
        makeTitleTexture();
    }

    void resizeGL(int w, int h) override
    {
        glViewport(0, 0, w, h);
        glMatrixMode(GL_PROJECTION);
        glLoadIdentity();
        const double aspect = h > 0 ? double(w) / double(h) : 1.0;
        const double nearPlane = 1.0;
        const double farPlane = 100.0;
        const double top = tan(45.0 * 0.5 * kPi / 180.0) * nearPlane;
        glFrustum(-top * aspect, top * aspect, -top, top, nearPlane, farPlane);
        glMatrixMode(GL_MODELVIEW);
    }

    void paintGL() override
    {
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        glLoadIdentity();
        applyLookAt(0.0f, 6.0f, 24.0f,
                    0.0f, 0.0f, 0.0f,
                    0.0f, 1.0f, 0.0f);
        glRotatef(m_pitchOffset, 1.0f, 0.0f, 0.0f);
        glRotatef(m_yaw, 0.0f, 1.0f, 0.0f);

        drawFloor();
        drawGroundShadow();
        drawCube(-10.0f, 0.0f, 0.0f);
        drawSphere(-6.0f, 0.0f, 0.0f);
        drawCylinder(-2.0f, 0.0f, 0.0f);
        drawCone(2.0f, 0.0f, 0.0f);
        drawTorus(6.0f, 0.0f, 0.0f);
        ensureTitleTexture();
        drawTitle();
    }

    void mousePressEvent(QMouseEvent *event) override
    {
        m_lastPos = event->pos();
    }

    void mouseMoveEvent(QMouseEvent *event) override
    {
        const QPoint delta = event->pos() - m_lastPos;
        m_lastPos = event->pos();
        if (event->buttons() & Qt::LeftButton) {
            m_yaw += delta.x() * 0.5f;
            m_pitchOffset += delta.y() * 0.5f;
            update();
        }
    }

    bool event(QEvent *event) override
    {
        // No GL here: the context is current only in initializeGL, resizeGL and
        // paintGL, so just ask for a repaint; paintGL checks the texture.
        if (event->type() == QEvent::Show || event->type() == QEvent::Expose) {
            update();
            QTimer::singleShot(100, this, [this]() { requestUpdate(); });
        }
        return QOpenGLWindow::event(event);
    }

private:
    static void setColor(const QColor &c)
    {
        const GLfloat specular[] = { 0.12f, 0.12f, 0.12f, 1.0f };
        const GLfloat shininess[] = { 24.0f };
        glMaterialfv(GL_FRONT_AND_BACK, GL_SPECULAR, specular);
        glMaterialfv(GL_FRONT_AND_BACK, GL_SHININESS, shininess);
        glColor4f(c.redF(), c.greenF(), c.blueF(), c.alphaF());
    }

    static void normal3f(float x, float y, float z)
    {
        const float len = sqrtf(x * x + y * y + z * z);
        if (len > 0.0f)
            glNormal3f(x / len, y / len, z / len);
    }

    static void applyLookAt(float eyeX, float eyeY, float eyeZ,
                            float centerX, float centerY, float centerZ,
                            float upX, float upY, float upZ)
    {
        float fx = centerX - eyeX;
        float fy = centerY - eyeY;
        float fz = centerZ - eyeZ;
        float len = sqrtf(fx * fx + fy * fy + fz * fz);
        if (len == 0.0f)
            return;
        fx /= len;
        fy /= len;
        fz /= len;

        len = sqrtf(upX * upX + upY * upY + upZ * upZ);
        if (len == 0.0f)
            return;
        upX /= len;
        upY /= len;
        upZ /= len;

        float sx = fy * upZ - fz * upY;
        float sy = fz * upX - fx * upZ;
        float sz = fx * upY - fy * upX;
        len = sqrtf(sx * sx + sy * sy + sz * sz);
        if (len == 0.0f)
            return;
        sx /= len;
        sy /= len;
        sz /= len;

        const float ux = sy * fz - sz * fy;
        const float uy = sz * fx - sx * fz;
        const float uz = sx * fy - sy * fx;

        const GLfloat matrix[] = {
            sx, ux, -fx, 0.0f,
            sy, uy, -fy, 0.0f,
            sz, uz, -fz, 0.0f,
            0.0f, 0.0f, 0.0f, 1.0f
        };
        glMultMatrixf(matrix);
        glTranslatef(-eyeX, -eyeY, -eyeZ);
    }

    static void drawFloor()
    {
        setColor(QColor(70, 74, 80));
        glBegin(GL_QUADS);
        glNormal3f(0.0f, 1.0f, 0.0f);
        glVertex3f(-15.0f, -2.0f, -8.0f);
        glVertex3f( 15.0f, -2.0f, -8.0f);
        glVertex3f( 15.0f, -2.0f,  13.7f);
        glVertex3f(-15.0f, -2.0f,  13.7f);
        glEnd();
    }

    static void drawGroundShadow()
    {
        glPushAttrib(GL_ENABLE_BIT | GL_CURRENT_BIT | GL_DEPTH_BUFFER_BIT);
        glDisable(GL_LIGHTING);
        glDisable(GL_CULL_FACE);
        glDisable(GL_DEPTH_TEST);
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        glDepthMask(GL_FALSE);
        glColor4f(0.46f, 0.46f, 0.50f, 0.68f);

        glPushMatrix();
        glTranslatef(0.0f, -1.88f, 0.55f);
        glScalef(5.4f, 1.0f, 2.15f);
        glBegin(GL_TRIANGLE_FAN);
        glNormal3f(0.0f, 1.0f, 0.0f);
        glVertex3f(0.0f, 0.0f, 0.0f);
        for (int i = 0; i <= 48; ++i) {
            const float t = 2.0f * kPi * i / 48.0f;
            glVertex3f(cosf(t), 0.0f, sinf(t));
        }
        glEnd();
        glPopMatrix();

        glPopAttrib();
    }

    static void drawCube(float x, float y, float z)
    {
        glPushMatrix();
        glTranslatef(x, y, z);
        setColor(QColor(200, 80, 60));
        const float s = 1.0f;
        glBegin(GL_QUADS);
        glNormal3f(0, 0, 1); glVertex3f(-s,-s,s); glVertex3f(s,-s,s); glVertex3f(s,s,s); glVertex3f(-s,s,s);
        glNormal3f(0, 0,-1); glVertex3f(s,-s,-s); glVertex3f(-s,-s,-s); glVertex3f(-s,s,-s); glVertex3f(s,s,-s);
        glNormal3f(1, 0, 0); glVertex3f(s,-s,s); glVertex3f(s,-s,-s); glVertex3f(s,s,-s); glVertex3f(s,s,s);
        glNormal3f(-1,0, 0); glVertex3f(-s,-s,-s); glVertex3f(-s,-s,s); glVertex3f(-s,s,s); glVertex3f(-s,s,-s);
        glNormal3f(0, 1, 0); glVertex3f(-s,s,s); glVertex3f(s,s,s); glVertex3f(s,s,-s); glVertex3f(-s,s,-s);
        glNormal3f(0,-1, 0); glVertex3f(-s,-s,-s); glVertex3f(s,-s,-s); glVertex3f(s,-s,s); glVertex3f(-s,-s,s);
        glEnd();
        glPopMatrix();
    }

    void makeTitleTexture()
    {
        QOpenGLContext *ctx = QOpenGLContext::currentContext();
        if (!ctx)
            return;

        // Only the context that generated the name may delete it. Deleting from
        // anywhere else either silently does nothing (the name is unknown there)
        // or destroys somebody else's texture.
        if (m_titleTexture && m_titleContext == ctx)
            glDeleteTextures(1, &m_titleTexture);
        m_titleTexture = 0;

        QImage image(2048, 512, QImage::Format_ARGB32);
        image.fill(Qt::transparent);
        QPainter painter(&image);
        painter.setRenderHint(QPainter::TextAntialiasing, true);
        QFont font(QStringLiteral("Segoe UI Light"), 270);
        font.setStyleStrategy(QFont::PreferAntialias);
        painter.setFont(font);
        painter.setPen(Qt::white);
        painter.drawText(image.rect().adjusted(96, 24, -96, -24),
                         Qt::AlignCenter, QStringLiteral("Qt3D mesh"));
        painter.end();

        const QImage glImage = image.mirrored().convertToFormat(QImage::Format_RGBA8888);
        glGenTextures(1, &m_titleTexture);
        glBindTexture(GL_TEXTURE_2D, m_titleTexture);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, glImage.width(), glImage.height(), 0,
                     GL_RGBA, GL_UNSIGNED_BYTE, glImage.constBits());
        glBindTexture(GL_TEXTURE_2D, 0);
        m_titleContext = ctx;
    }

    // Known issue: on Mesa 10.0 / SVGA3D the title quad turns black after
    // switching tabs away and back, while everything else in the window redraws.
    // The texture is tracked per context and rebuilt in a new one, so it is not
    // a stale name; the shutdown log's "SetPixelFormat() failed" points at the
    // native window being recreated under QWindowContainer.
    void ensureTitleTexture()
    {
        if (!m_titleTexture || m_titleContext != QOpenGLContext::currentContext())
            makeTitleTexture();
    }

    void drawTitle() const
    {
        if (!m_titleTexture)
            return;

        glPushAttrib(GL_ENABLE_BIT | GL_CURRENT_BIT | GL_TEXTURE_BIT | GL_DEPTH_BUFFER_BIT);
        if (QOpenGLContext::currentContext()) {
            QOpenGLContext::currentContext()->functions()->glUseProgram(0);
            QOpenGLContext::currentContext()->functions()->glActiveTexture(GL_TEXTURE0);
        }
        glMatrixMode(GL_TEXTURE);
        glPushMatrix();
        glLoadIdentity();
        glMatrixMode(GL_MODELVIEW);
        glDisable(GL_LIGHTING);
        glDisable(GL_CULL_FACE);
        glDisable(GL_DEPTH_TEST);
        glDisable(GL_ALPHA_TEST);
        glDisable(GL_FOG);
        glDisable(GL_TEXTURE_GEN_S);
        glDisable(GL_TEXTURE_GEN_T);
        glDisable(GL_TEXTURE_GEN_R);
        glDisable(GL_TEXTURE_GEN_Q);
        glDepthMask(GL_FALSE);
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        glEnable(GL_TEXTURE_2D);
        glBindTexture(GL_TEXTURE_2D, m_titleTexture);
        glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);
        glColor4f(1.0f, 1.0f, 1.0f, 1.0f);

        glPushMatrix();
        glTranslatef(-0.55f, 5.85f, -4.3f);
        glBegin(GL_QUADS);
        glNormal3f(0.0f, 0.0f, 1.0f);
        glTexCoord2f(0.0f, 0.0f); glVertex3f(-10.2f, -2.55f, 0.0f);
        glTexCoord2f(1.0f, 0.0f); glVertex3f( 10.2f, -2.55f, 0.0f);
        glTexCoord2f(1.0f, 1.0f); glVertex3f( 10.2f,  2.55f, 0.0f);
        glTexCoord2f(0.0f, 1.0f); glVertex3f(-10.2f,  2.55f, 0.0f);
        glEnd();
        glPopMatrix();

        glBindTexture(GL_TEXTURE_2D, 0);
        glMatrixMode(GL_TEXTURE);
        glPopMatrix();
        glMatrixMode(GL_MODELVIEW);
        glPopAttrib();
    }

    static void drawSphere(float x, float y, float z)
    {
        glPushMatrix();
        glTranslatef(x, y, z);
        setColor(QColor(120, 190, 80));
        const int stacks = 18;
        const int slices = 28;
        const float r = 1.5f;
        for (int i = 0; i < stacks; ++i) {
            const float p0 = -kPi / 2.0f + kPi * i / stacks;
            const float p1 = -kPi / 2.0f + kPi * (i + 1) / stacks;
            glBegin(GL_QUAD_STRIP);
            for (int j = 0; j <= slices; ++j) {
                const float t = 2.0f * kPi * j / slices;
                const float x0 = cosf(p0) * cosf(t), y0 = sinf(p0), z0 = cosf(p0) * sinf(t);
                const float x1 = cosf(p1) * cosf(t), y1 = sinf(p1), z1 = cosf(p1) * sinf(t);
                glNormal3f(x0, y0, z0); glVertex3f(r * x0, r * y0, r * z0);
                glNormal3f(x1, y1, z1); glVertex3f(r * x1, r * y1, r * z1);
            }
            glEnd();
        }
        glPopMatrix();
    }

    static void drawCylinder(float x, float y, float z)
    {
        glPushMatrix();
        glTranslatef(x, y, z);
        setColor(QColor(80, 100, 220));
        const int slices = 32;
        const float r = 1.0f, h = 2.5f;
        glBegin(GL_QUAD_STRIP);
        for (int i = 0; i <= slices; ++i) {
            const float t = 2.0f * kPi * i / slices;
            const float cx = cosf(t), cz = sinf(t);
            glNormal3f(cx, 0.0f, cz);
            glVertex3f(r * cx, -h / 2.0f, r * cz);
            glVertex3f(r * cx,  h / 2.0f, r * cz);
        }
        glEnd();
        glBegin(GL_TRIANGLE_FAN);
        glNormal3f(0.0f, 1.0f, 0.0f);
        glVertex3f(0.0f, h / 2.0f, 0.0f);
        for (int i = 0; i <= slices; ++i) {
            const float t = 2.0f * kPi * i / slices;
            glVertex3f(r * cosf(t), h / 2.0f, r * sinf(t));
        }
        glEnd();
        glBegin(GL_TRIANGLE_FAN);
        glNormal3f(0.0f, -1.0f, 0.0f);
        glVertex3f(0.0f, -h / 2.0f, 0.0f);
        for (int i = slices; i >= 0; --i) {
            const float t = 2.0f * kPi * i / slices;
            glVertex3f(r * cosf(t), -h / 2.0f, r * sinf(t));
        }
        glEnd();
        glPopMatrix();
    }

    static void drawCone(float x, float y, float z)
    {
        glPushMatrix();
        glTranslatef(x, y, z);
        setColor(QColor(220, 190, 60));
        const int slices = 32;
        const float r = 1.2f, h = 2.5f;
        glBegin(GL_TRIANGLE_FAN);
        glNormal3f(0.0f, 1.0f, 0.0f);
        glVertex3f(0.0f, h / 2.0f, 0.0f);
        for (int i = 0; i <= slices; ++i) {
            const float t = 2.0f * kPi * i / slices;
            normal3f(cosf(t), r / h, sinf(t));
            glVertex3f(r * cosf(t), -h / 2.0f, r * sinf(t));
        }
        glEnd();
        glPopMatrix();
    }

    void drawTorus(float x, float y, float z) const
    {
        glPushMatrix();
        glTranslatef(x, y, z);
        glRotatef(90.0f, 1.0f, 0.0f, 0.0f);
        glRotatef(m_spin, 0.0f, 1.0f, 0.0f);
        setColor(QColor(105, 108, 116));
        const int majorSteps = 32;
        const int minorSteps = 16;
        const float major = 1.2f, minor = 0.4f;
        for (int i = 0; i < majorSteps; ++i) {
            const float a0 = 2.0f * kPi * i / majorSteps;
            const float a1 = 2.0f * kPi * (i + 1) / majorSteps;
            glBegin(GL_QUAD_STRIP);
            for (int j = 0; j <= minorSteps; ++j) {
                const float b = 2.0f * kPi * j / minorSteps;
                torusVertex(a0, b, major, minor);
                torusVertex(a1, b, major, minor);
            }
            glEnd();
        }
        glPopMatrix();
    }

    static void torusVertex(float a, float b, float major, float minor)
    {
        const float ca = cosf(a), sa = sinf(a), cb = cosf(b), sb = sinf(b);
        glNormal3f(ca * cb, sb, sa * cb);
        glVertex3f((major + minor * cb) * ca, minor * sb, (major + minor * cb) * sa);
    }

    QTimer m_timer;
    QPoint m_lastPos;
    GLuint m_titleTexture = 0;
    QPointer<QOpenGLContext> m_titleContext;
    float m_yaw = 0.0f;
    float m_pitchOffset = 0.0f;
    float m_spin = 0.0f;
};

static QWidget *buildCompatQt3DTab()
{
    auto *page = new QWidget;
    auto *lay = new QVBoxLayout(page);
    lay->setContentsMargins(0, 0, 0, 0);
    auto *container = QWidget::createWindowContainer(new Compat3DWindow, page);
    container->setMinimumSize(400, 300);
    lay->addWidget(container, 1);
    lay->addWidget(new QLabel("Qt3D: mesh/material catalogue, fixed-function XP visual fallback, "
                              "orbit drag, spinning torus."));

    auto *warning = new QLabel(
        QStringLiteral("This driver reports OpenGL %1.%2; Qt3D's OpenGL renderer targets 3.2 core. "
                       "The real Qt3D node/material APIs are still covered by --selftest, while this "
                       "visual tab uses a GL 2.1-compatible renderer so XP does not show a black scene.")
            .arg(glCaps().major).arg(glCaps().minor));
    warning->setWordWrap(true);
    warning->setEnabled(false);
    lay->addWidget(warning);
    return page;
}

} // namespace

QWidget *buildQt3DTab()
{
    if (!glCaps().qt3dFullySupported())
        return buildCompatQt3DTab();

    auto *page = new QWidget;
    auto *lay = new QVBoxLayout(page);
    lay->setContentsMargins(0, 0, 0, 0);

    auto *view = new Qt3DExtras::Qt3DWindow;
    view->defaultFrameGraph()->setClearColor(QColor(30, 34, 40));

    auto *root = new Qt3DCore::QEntity;

    // ---- Camera ----
    Qt3DRender::QCamera *camera = view->camera();
    camera->lens()->setPerspectiveProjection(45.0f, 16.0f / 9.0f, 0.1f, 1000.0f);
    camera->setPosition(QVector3D(0, 6, 24));
    camera->setViewCenter(QVector3D(0, 0, 0));

    auto *camController = new Qt3DExtras::QOrbitCameraController(root);
    camController->setCamera(camera);
    camController->setLinearSpeed(50.0f);
    camController->setLookSpeed(180.0f);

    // ---- Lights: point, directional, spot ----
    auto *lightEntity1 = new Qt3DCore::QEntity(root);
    auto *pointLight = new Qt3DRender::QPointLight(lightEntity1);
    pointLight->setColor(Qt::white);
    pointLight->setIntensity(0.8f);
    auto *lightTransform1 = new Qt3DCore::QTransform;
    lightTransform1->setTranslation(QVector3D(10, 10, 10));
    lightEntity1->addComponent(pointLight);
    lightEntity1->addComponent(lightTransform1);

    auto *lightEntity2 = new Qt3DCore::QEntity(root);
    auto *dirLight = new Qt3DRender::QDirectionalLight(lightEntity2);
    dirLight->setColor(QColor(180, 200, 255));
    dirLight->setWorldDirection(QVector3D(-1, -1, -1));
    lightEntity2->addComponent(dirLight);

    // QSpotLight points straight down by default (localDirection (0,-1,0)),
    // so it lands its cone on the floor directly beneath its position - centre
    // it over the showcase row instead of off at the left edge, where the
    // cone was spilling half outside the viewport.
    auto *lightEntity3 = new Qt3DCore::QEntity(root);
    auto *spotLight = new Qt3DRender::QSpotLight(lightEntity3);
    spotLight->setColor(QColor(255, 200, 150));
    spotLight->setCutOffAngle(20.0f);
    auto *lightTransform3 = new Qt3DCore::QTransform;
    lightTransform3->setTranslation(QVector3D(0, 10, 0));
    lightEntity3->addComponent(spotLight);
    lightEntity3->addComponent(lightTransform3);

    // ---- Floor, drawn first (opaque, depth-writing) so it never fights with
    // the alpha-blended cylinder below it in draw order ----
    auto *plane = new Qt3DExtras::QPlaneMesh;
    plane->setWidth(30); plane->setHeight(30);
    // QPerVertexColorMaterial needs a per-vertex colour attribute the built-in
    // Extras meshes don't provide, which would render the floor solid black;
    // a plain grey QPhongMaterial actually looks like a floor. Coverage of
    // QPerVertexColorMaterial itself still comes from the headless self-test.
    auto *floorMaterial = new Qt3DExtras::QPhongMaterial;
    floorMaterial->setDiffuse(QColor(70, 74, 80));
    makeVisibleWithoutLights(floorMaterial, QColor(70, 74, 80));
    makeShowcaseEntity(root, plane, floorMaterial, QVector3D(0, -2, 0));

    // ---- Mesh x material showcase row ----
    auto *cuboid = new Qt3DExtras::QCuboidMesh;
    cuboid->setXExtent(2.0f);
    cuboid->setYExtent(2.0f);
    cuboid->setZExtent(2.0f);
    auto *phong = new Qt3DExtras::QPhongMaterial;
    phong->setDiffuse(QColor(200, 80, 60));
    makeVisibleWithoutLights(phong, QColor(200, 80, 60));
    makeShowcaseEntity(root, cuboid, phong, QVector3D(-10, 0, 0));

    auto *sphere = new Qt3DExtras::QSphereMesh;
    sphere->setRadius(1.5f);
    auto *gooch = new Qt3DExtras::QGoochMaterial;
    gooch->setDiffuse(QColor(80, 160, 90));
    makeShowcaseEntity(root, sphere, gooch, QVector3D(-6, 0, 0));

    auto *cylinder = new Qt3DExtras::QCylinderMesh;
    cylinder->setRadius(1.0f);
    cylinder->setLength(2.5f);
    auto *phongAlpha = new Qt3DExtras::QPhongAlphaMaterial;
    phongAlpha->setDiffuse(QColor(80, 100, 220));
    phongAlpha->setAlpha(0.7f);
    phongAlpha->setAmbient(glCaps().qt3dFullySupported() ? phongAlpha->ambient()
                                                         : QColor(80, 100, 220).darker(150));
    makeShowcaseEntity(root, cylinder, phongAlpha, QVector3D(-2, 0, 0));

    auto *cone = new Qt3DExtras::QConeMesh;
    cone->setBottomRadius(1.2f);
    cone->setLength(2.5f);
    auto *diffSpec = new Qt3DExtras::QDiffuseSpecularMaterial;
    diffSpec->setDiffuse(QColor(220, 190, 60));
    if (!glCaps().qt3dFullySupported())
        diffSpec->setAmbient(QColor(220, 190, 60).darker(150));
    makeShowcaseEntity(root, cone, diffSpec, QVector3D(2, 0, 0));

    auto *torus = new Qt3DExtras::QTorusMesh;
    torus->setRadius(1.2f); torus->setMinorRadius(0.4f);
    // QMetalRoughMaterial has no OpenGL 2 technique, so below GL 3.1 the torus
    // would not be drawn at all; it gets a material that can be.
    Qt3DRender::QMaterial *torusMaterial;
    if (glCaps().qt3dFullySupported()) {
        auto *metalRough = new Qt3DExtras::QMetalRoughMaterial;
        metalRough->setBaseColor(QColor(180, 180, 190));
        metalRough->setMetalness(0.8f);
        metalRough->setRoughness(0.3f);
        torusMaterial = metalRough;
    } else {
        auto *fallback = new Qt3DExtras::QPhongMaterial;
        fallback->setDiffuse(QColor(180, 180, 190));
        makeVisibleWithoutLights(fallback, QColor(180, 180, 190));
        torusMaterial = fallback;
    }
    makeShowcaseEntity(root, torus, torusMaterial, QVector3D(6, 0, 0));

    // ---- Object picking on the cuboid ----
    auto *cuboidEntity = qobject_cast<Qt3DCore::QEntity *>(cuboid->parent());
    if (cuboidEntity) {
        auto *picker = new Qt3DRender::QObjectPicker(cuboidEntity);
        picker->setHoverEnabled(true);
        cuboidEntity->addComponent(picker);
    }

    // ---- A layer, tagging the whole scene (not filtered on, just attached -
    // touches the class without needing a second framegraph branch) ----
    auto *sceneLayer = new Qt3DRender::QLayer(root);
    root->addComponent(sceneLayer);

    // ---- Label ----
    // QText2DEntity lays text out at 10pt and scales the glyphs by pointSize / 10,
    // but not its clip box, so a small point size keeps the text inside it.
    auto *label = new Qt3DExtras::QText2DEntity(root);
    label->setText("Qt3D mesh + material catalogue");
    label->setHeight(4.0f);
    label->setWidth(22.0f);
    label->setColor(Qt::white);
    label->setFont(QFont("Arial", 3));
    auto *labelTransform = new Qt3DCore::QTransform;
    labelTransform->setTranslation(QVector3D(-11, 5.0f, 0));
    label->addComponent(labelTransform);

    // ---- A logic aspect driving a per-frame spin, wired via QFrameAction ----
    auto *spinEntity = new Qt3DCore::QEntity(root);
    auto *spinTransform = new Qt3DCore::QTransform;
    spinEntity->addComponent(spinTransform);
    auto *frameAction = new Qt3DLogic::QFrameAction(root);
    root->addComponent(frameAction);
    QObject::connect(frameAction, &Qt3DLogic::QFrameAction::triggered, spinTransform,
                      [spinTransform](float dt) {
                          spinTransform->setRotation(spinTransform->rotation()
                              * QQuaternion::fromAxisAndAngle(QVector3D(0, 1, 0), dt * 40.0f));
                      });

    view->setRootEntity(root);
    view->registerAspect(new Qt3DInput::QInputAspect);
    view->registerAspect(new Qt3DLogic::QLogicAspect);

    auto *inputSettings = new Qt3DInput::QInputSettings(root);
    inputSettings->setEventSource(view);
    root->addComponent(inputSettings);

    auto *container = QWidget::createWindowContainer(view, page);
    container->setMinimumSize(400, 300);
    lay->addWidget(container, 1);
    lay->addWidget(new QLabel("Qt3D: mesh/material catalogue, 3 light types, "
                              "orbit camera, object picker, spinning entity."));

    // Qt3D wants a 3.2 core context and draws only part of the scene below it;
    // say so under the scene.
    if (!glCaps().qt3dFullySupported()) {
        auto *warning = new QLabel(
            QStringLiteral("This driver reports OpenGL %1.%2; Qt3D's renderer targets 3.2 core. "
                           "What you see above is whatever survives on the older pipeline - "
                           "expect missing meshes, missing textures and unlit materials. "
                           "The scene graph itself is built in full either way, and the "
                           "--selftest checks exercise it headlessly.")
                .arg(glCaps().major).arg(glCaps().minor));
        warning->setWordWrap(true);
        warning->setEnabled(false);
        lay->addWidget(warning);
    }
    return page;
}
