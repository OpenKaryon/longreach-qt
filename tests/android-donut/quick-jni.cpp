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
#include <QtGui/QImage>
#include <QtGui/QPainter>

Q_IMPORT_PLUGIN(minimal)

namespace {

const int sceneWidth = 220;
const int sceneHeight = 260;
QDeclarativeView *view = 0;

void logQtMessage(QtMsgType type, const char *message)
{
    __android_log_write(type == QtFatalMsg ? ANDROID_LOG_ERROR : ANDROID_LOG_DEBUG,
                        "LongreachDonut", message);
}

}

extern "C" JNIEXPORT jboolean JNICALL
Java_org_longreachqt_donut_quick_QuickActivity_openScene(JNIEnv *, jobject)
{
    if (view)
        return view->status() == QDeclarativeView::Ready;

    static int argc = 1;
    static char name[] = "longreach-quick";
    static char *argv[] = {name, 0};
    qInstallMsgHandler(logQtMessage);
    qputenv("QT_QPA_PLATFORM", QByteArray("minimal"));
    qputenv("QT_QPA_FONTDIR", QByteArray("/system/fonts"));
    new QApplication(argc, argv);
    view = new QDeclarativeView;
    view->resize(sceneWidth, sceneHeight);
    view->setSceneRect(0, 0, sceneWidth, sceneHeight);
    view->setSource(QUrl(QLatin1String("qrc:/qml_qt4/qml_qt4/MobileSmoke.qml")));
    QApplication::processEvents();
    if (view->status() == QDeclarativeView::Ready && view->rootObject()) {
        __android_log_write(ANDROID_LOG_INFO, "LongreachDonut", "Quick scene loaded from qrc");
        return JNI_TRUE;
    }
    foreach (const QDeclarativeError &error, view->errors())
        __android_log_write(ANDROID_LOG_ERROR, "LongreachDonut", error.toString().toUtf8().constData());
    return JNI_FALSE;
}

extern "C" JNIEXPORT jint JNICALL
Java_org_longreachqt_donut_quick_QuickActivity_renderScene(JNIEnv *env, jobject, jintArray pixels)
{
    if (!view || !view->rootObject() || env->GetArrayLength(pixels) != sceneWidth * sceneHeight)
        return 0;
    QApplication::processEvents();
    QImage frame(sceneWidth, sceneHeight, QImage::Format_ARGB32);
    frame.fill(0);
    {
        QPainter painter(&frame);
        view->scene()->render(&painter, frame.rect(), view->sceneRect());
    }
    env->SetIntArrayRegion(pixels, 0, sceneWidth * sceneHeight,
                          reinterpret_cast<const jint *>(frame.constBits()));
    return frame.pixel(sceneWidth / 2 - 28, sceneHeight / 2 - 22);
}

extern "C" JNIEXPORT jboolean JNICALL
Java_org_longreachqt_donut_quick_QuickActivity_pointer(JNIEnv *, jobject, jint x, jint y, jboolean pressed)
{
    if (!view || !view->rootObject())
        return JNI_FALSE;
    const QPointF position(x, y);
    QGraphicsSceneMouseEvent event(pressed ? QEvent::GraphicsSceneMousePress
                                         : QEvent::GraphicsSceneMouseRelease);
    event.setScenePos(position);
    event.setLastScenePos(position);
    event.setScreenPos(position.toPoint());
    event.setLastScreenPos(position.toPoint());
    event.setButtonDownScenePos(Qt::LeftButton, position);
    event.setButtonDownScreenPos(Qt::LeftButton, position.toPoint());
    event.setButton(Qt::LeftButton);
    event.setButtons(pressed ? Qt::LeftButton : Qt::NoButton);
    QApplication::sendEvent(view->scene(), &event);
    return view->rootObject()->property("checked").toBool();
}
