// SPDX-License-Identifier: GPL-3.0-or-later

#include <android/log.h>
#include <jni.h>
#include <QtCore/QString>
#include <QtCore/QtPlugin>
#include <QtCore/QUrl>
#include <QtDeclarative/QDeclarativeError>
#include <QtDeclarative/QDeclarativeItem>
#include <QtDeclarative/QDeclarativeView>
#include <QtGui/QApplication>
#include <QtGui/QGraphicsScene>
#include <QtGui/QGraphicsSceneMouseEvent>
#include <QtGui/QGraphicsProxyWidget>
#include <QtGui/QCheckBox>
#include <QtGui/QTabBar>
#include <QtGui/QTabWidget>
#include "../widgets-gallery/gallery.h"
#include <QtGui/QImage>
#include <QtGui/QPainter>
#include "../quick-qml-gallery/qt4_static_imports.h"

Q_IMPORT_PLUGIN(minimal)
Q_IMPORT_PLUGIN(qsvg)

namespace {

QDeclarativeView *view = 0;
QSize frameSize;
QPointF lastPosition;
QPointF pressedPosition;
enum SceneMode { SwitchScene, QmlGallery, WidgetsGallery };
SceneMode sceneMode = SwitchScene;
QGraphicsScene *widgetScene = 0;
QTabWidget *tabs = 0;
QCheckBox *checkBox = 0;

QGraphicsScene *currentScene()
{
    return widgetScene ? widgetScene : view ? view->scene() : 0;
}

void openWidgets(const QSize &size)
{
    widgetScene = new QGraphicsScene(QRectF(QPointF(), size));
    tabs = new QTabWidget;
    QWidget *buttons = makeButtonsTab();
    checkBox = buttons->findChild<QCheckBox *>();
    tabs->addTab(buttons, "Buttons");
    tabs->addTab(makeInputsTab(), "Inputs");
    tabs->addTab(makeRangesTab(), "Ranges");
    tabs->addTab(makeItemViewsTab(), "Item Views");
    widgetScene->addWidget(tabs)->setGeometry(widgetScene->sceneRect());
}

void logQtMessage(QtMsgType type, const char *message)
{
    __android_log_write(type == QtFatalMsg ? ANDROID_LOG_ERROR : ANDROID_LOG_DEBUG,
                        "LongreachDonut", message);
}

}

extern "C" JNIEXPORT jboolean JNICALL
Java_org_longreachqt_donut_quick_QuickActivity_openScene(JNIEnv *, jobject, jint mode, jint width, jint height)
{
    if (mode < SwitchScene || mode > WidgetsGallery)
        return JNI_FALSE;
    if (currentScene() && sceneMode == mode && frameSize == QSize(width, height))
        return widgetScene ? checkBox != 0 : view->status() == QDeclarativeView::Ready;

    if (!qApp) {
        static int argc = 1;
        static char name[] = "longreach-quick";
        static char *argv[] = {name, 0};
        qInstallMsgHandler(logQtMessage);
        qputenv("QT_QPA_PLATFORM", QByteArray("minimal"));
        qputenv("QT_QPA_FONTDIR", QByteArray("/system/fonts"));
        new QApplication(argc, argv);
        registerQt4QmlPlugins();
    }
    delete view;
    view = 0;
    delete widgetScene;
    widgetScene = 0;
    tabs = 0;
    checkBox = 0;
    sceneMode = SceneMode(mode);
    frameSize = QSize(width, height);
    if (sceneMode == WidgetsGallery) {
        openWidgets(frameSize);
        QApplication::processEvents();
        return checkBox != 0;
    }
    view = new QDeclarativeView;
    const bool gallery = sceneMode == QmlGallery;
    const QSize sceneSize = gallery ? QSize(940, 640) : frameSize;
    view->resize(sceneSize);
    view->setSceneRect(QRectF(QPointF(), sceneSize));
    configureStaticQt4Imports(view->engine());
    const char *source = gallery ? "qrc:/qml_qt4/qml_qt4/main.qml" : "qrc:/qml_qt4/qml_qt4/MobileSmoke.qml";
    view->setSource(QUrl(QLatin1String(source)));
    QApplication::processEvents();
    if (view->status() == QDeclarativeView::Ready && view->rootObject()) {
        __android_log_write(ANDROID_LOG_INFO, "LongreachDonut",
                            gallery ? "Qt Quick Gallery loaded from qrc" : "Quick scene loaded from qrc");
        return JNI_TRUE;
    }
    foreach (const QDeclarativeError &error, view->errors())
        __android_log_write(ANDROID_LOG_ERROR, "LongreachDonut", error.toString().toUtf8().constData());
    return JNI_FALSE;
}

extern "C" JNIEXPORT jint JNICALL
Java_org_longreachqt_donut_quick_QuickActivity_renderScene(JNIEnv *env, jobject, jintArray pixels)
{
    const int pixelCount = frameSize.width() * frameSize.height();
    QGraphicsScene *scene = currentScene();
    if (!scene || (view && !view->rootObject()) || env->GetArrayLength(pixels) != pixelCount)
        return 0;
    QApplication::processEvents();
    QImage frame(frameSize, QImage::Format_ARGB32);
    frame.fill(0);
    {
        QPainter painter(&frame);
        scene->render(&painter, frame.rect(), scene->sceneRect(), Qt::IgnoreAspectRatio);
    }
    env->SetIntArrayRegion(pixels, 0, pixelCount,
                          reinterpret_cast<const jint *>(frame.constBits()));
    if (widgetScene)
        return tabs->currentIndex() * 4 + (checkBox ? checkBox->checkState() : 0);
    if (sceneMode == QmlGallery)
        return view->rootObject()->property("section").toInt();
    return frame.pixel(frame.width() / 2 - 28, frame.height() / 2 - 22);
}

extern "C" JNIEXPORT jboolean JNICALL
Java_org_longreachqt_donut_quick_QuickActivity_pointer(JNIEnv *, jobject, jint x, jint y, jint action)
{
    QGraphicsScene *graphics = currentScene();
    if (!graphics || (view && !view->rootObject()))
        return JNI_FALSE;
    // Mirrors Android MotionEvent.ACTION_DOWN, ACTION_UP and ACTION_MOVE.
    const bool press = action == 0;
    const bool release = action == 1;
    const QRectF scene = graphics->sceneRect();
    const QPointF position(x * scene.width() / frameSize.width(),
                           y * scene.height() / frameSize.height());
    if (press)
        lastPosition = pressedPosition = position;
    QGraphicsSceneMouseEvent event(press ? QEvent::GraphicsSceneMousePress
                                        : release ? QEvent::GraphicsSceneMouseRelease
                                                  : QEvent::GraphicsSceneMouseMove);
    event.setScenePos(position);
    event.setLastScenePos(lastPosition);
    event.setScreenPos(position.toPoint());
    event.setLastScreenPos(lastPosition.toPoint());
    event.setButtonDownScenePos(Qt::LeftButton, pressedPosition);
    event.setButtonDownScreenPos(Qt::LeftButton, pressedPosition.toPoint());
    event.setButton(press || release ? Qt::LeftButton : Qt::NoButton);
    event.setButtons(release ? Qt::NoButton : Qt::LeftButton);
    lastPosition = position;
    QApplication::sendEvent(graphics, &event);
    return view && view->rootObject()->property("checked").toBool();
}

extern "C" JNIEXPORT jintArray JNICALL
Java_org_longreachqt_donut_quick_QuickActivity_controlCenter(JNIEnv *env, jobject, jint index)
{
    QPoint center;
    if (sceneMode == QmlGallery && view) {
        const QString name = QLatin1String("navigationRow") + QString::number(index);
        QGraphicsItem *row = 0;
        foreach (QGraphicsItem *item, view->scene()->items()) {
            QGraphicsObject *object = item->toGraphicsObject();
            if (object && object->objectName() == name) {
                row = item;
                break;
            }
        }
        if (!row)
            return 0;
        const QPointF position = row->mapToScene(row->boundingRect().center());
        const QRectF bounds = view->scene()->sceneRect();
        center = QPoint(qRound(position.x() * frameSize.width() / bounds.width()),
                        qRound(position.y() * frameSize.height() / bounds.height()));
    } else if (tabs && checkBox && index == 0) {
        center = checkBox->mapTo(tabs, QPoint(8, checkBox->height() / 2));
    } else if (tabs && index == 1) {
        QTabBar *bar = tabs->findChild<QTabBar *>();
        if (!bar || bar->count() < 2)
            return 0;
        center = bar->mapTo(tabs, bar->tabRect(1).center());
    } else {
        return 0;
    }
    const jint coords[] = {center.x(), center.y()};
    jintArray point = env->NewIntArray(2);
    if (point)
        env->SetIntArrayRegion(point, 0, 2, coords);
    return point;
}
