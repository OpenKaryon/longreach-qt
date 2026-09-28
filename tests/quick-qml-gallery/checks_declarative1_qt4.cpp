// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// QtQuick 1 - Qt 4's QtDeclarative.
//
// QtQuick 1 draws through QGraphicsView and uses QDeclarative* APIs. These
// engine checks belong to the Qt4 branch of the shared gallery application.
//
// Engine checks are followed by an actual fourteen-page gallery render sweep.

#include "../common/smokecheck.h"
#include "qt4_static_imports.h"

// No availability guard: this file is compiled only on Qt 4, and the app's
// own gate in tests/CMakeLists.txt already requires Qml, which maps to
// QtDeclarative there. If the module were missing the app would not exist.

#include <QObject>
#include <QCoreApplication>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QStringList>
#include <QUrl>
#include <QVariant>
#include <QPainter>
#include <QTimer>
#include <QApplication>
#include <QMouseEvent>
#include <QGraphicsSceneMouseEvent>

#include <QDeclarativeComponent>
#include <QDeclarativeContext>
#include <QDeclarativeEngine>
#include <QDeclarativeError>
#include <QDeclarativeExpression>
#include <QDeclarativeExtensionPlugin>
#include <QDeclarativeImageProvider>
#include <QDeclarativeInfo>
#include <QDeclarativeItem>
#include <QDeclarativeListReference>
#include <QDeclarativeNetworkAccessManagerFactory>
#include <QDeclarativeParserStatus>
#include <QDeclarativeProperty>
#include <QDeclarativePropertyMap>
#include <QDeclarativePropertyValueSource>
#include <QDeclarativeScriptString>
#include <QDeclarativeView>

namespace {

// An image provider is something an application supplies to the engine, so
// subclassing is how the class is referenced at all.
class SmokeImageProvider : public QDeclarativeImageProvider
{
public:
    SmokeImageProvider() : QDeclarativeImageProvider(QDeclarativeImageProvider::Image) {}
    QImage requestImage(const QString &, QSize *size, const QSize &)
    {
        QImage image(8, 8, QImage::Format_ARGB32);
        image.fill(0);
        if (size)
            *size = image.size();
        return image;
    }
};

// QDeclarativeItem already implements QDeclarativeParserStatus; overriding
// componentComplete() is how an item learns its properties are set, which is
// the whole of what that interface is for.
class SmokeItem : public QDeclarativeItem
{
public:
    SmokeItem() : completed(false) {}
    void componentComplete() { completed = true; QDeclarativeItem::componentComplete(); }
    bool completed;
};

} // namespace

void addDeclarative1Checks(SmokeReporter &r)
{
    r.check("declarative1/floating-point-script", [](QString &d) {
        SmokeQt4QmlEngine engine;
        QDeclarativeExpression expression(engine.rootContext(), 0,
            "(function() { var total = 0; for (var i = 0; i < 500; ++i) "
            "total += 0.5 + 0.5 * Math.sin(i * Math.PI / 180); "
            "return total > 250 && total < 310 && Math.abs(Math.sqrt(2) * Math.sqrt(2) - 2) < 0.000001; })()");
        const QVariant value = expression.evaluate();
        if (expression.hasError()) d = expression.error().toString();
        return !expression.hasError() && value.toBool();
    });
    r.check("declarative1/binding-worker-timer-xml-loader", [](QString &d) {
        SmokeQt4QmlEngine engine;
        QDeclarativeComponent component(&engine,
            QUrl(QLatin1String("qrc:/qml_qt4/qml_qt4/CatalogProbe.qml")));
        QObject *object = component.create();
        if (!object) {
            d = component.errorString();
            return false;
        }
        QMetaObject::invokeMethod(object, "run");

        QElapsedTimer timeout;
        timeout.start();
        while (timeout.elapsed() < 10000
               && (!object->property("timerFired").toBool()
                   || object->property("workerValue").toInt() != 42
                   || object->property("xmlCount").toInt() != 2)) {
            // XmlListModel runs its query thread at IdlePriority. A busy
            // processEvents loop can starve it on a single-CPU Win95 guest.
            // Block between event deliveries so the worker gets CPU time.
            QEventLoop wait;
            QTimer::singleShot(10, &wait, SLOT(quit()));
            wait.exec();
        }

        const int bound = object->property("boundValue").toInt();
        const int connected = object->property("connectedValue").toInt();
        const int worker = object->property("workerValue").toInt();
        const int xml = object->property("xmlCount").toInt();
        const bool timer = object->property("timerFired").toBool();
        const bool loaded = object->property("loaded").toBool();
        d = QString::fromLatin1("binding=%1 connection=%2 worker=%3 xml=%4 timer=%5 loader=%6")
                .arg(bound).arg(connected).arg(worker).arg(xml)
                .arg(timer ? "yes" : "no").arg(loaded ? "yes" : "no");
        if (xml != 2)
            d += QString::fromLatin1(" xmlStatus=%1 xmlError=%2 elapsed=%3ms")
                    .arg(object->property("xmlStatus").toInt())
                    .arg(object->property("xmlError").toString()).arg(timeout.elapsed());
        delete object;
        return bound == 42 && connected == 17 && worker == 42 && xml == 2
            && timer && loaded;
    });

    r.check("declarative1/application-type-is-uncreatable", [](QString &d) {
        SmokeQt4QmlEngine engine;
        QDeclarativeComponent component(&engine);
        component.setData("import QtQuick 1.1\nApplication { }", QUrl());
        d = component.errorString();
        return component.isError()
            && d.contains(QLatin1String("abstract"), Qt::CaseInsensitive);
    });

    r.check("declarative1/visual-gallery-loads", [](QString &d) {
        // Loading only main.cpp's QDeclarativeView catches syntax errors, but
        // --selftest used to skip the visual file entirely. Compile and create
        // it here so every static Qt.labs plugin import and every page is
        // verified before the manual gallery can be shipped.
        SmokeQt4QmlEngine engine;
        QDeclarativeComponent component(&engine,
            QUrl(QLatin1String("qrc:/qml_qt4/qml_qt4/main.qml")));
        if (component.isError()) {
            const QList<QDeclarativeError> errors = component.errors();
            d = errors.isEmpty() ? component.errorString()
                                 : errors.first().toString();
            return false;
        }
        QObject *object = component.create();
        if (!object) {
            d = component.errorString();
            return false;
        }
        object->setProperty("section", 8);
        QObject *borderImage = object->findChild<QObject *>(QLatin1String("borderImageProbe"));
        QObject *animatedImage = object->findChild<QObject *>(QLatin1String("animatedImageProbe"));
        if (animatedImage)
            animatedImage->setProperty("playing", true);
        int previousX = animatedImage ? animatedImage->property("x").toInt() : -1;
        bool sawFarEdge = false;
        bool looped = false;
        QElapsedTimer imageTimeout;
        imageTimeout.start();
        while (imageTimeout.elapsed() < 4000 && !looped) {
            QCoreApplication::processEvents(QEventLoop::AllEvents, 25);
            if (!animatedImage)
                continue;
            const int x = animatedImage->property("x").toInt();
            sawFarEdge = sawFarEdge || x >= 40;
            looped = sawFarEdge && x < previousX;
            previousX = x;
        }
        const int borderStatus = borderImage ? borderImage->property("status").toInt() : -1;
        const int animatedStatus = animatedImage ? animatedImage->property("status").toInt() : -1;
        const int frames = animatedImage ? animatedImage->property("frameCount").toInt() : 0;
        const bool rightSize = object->property("width").toInt() == 940
                            && object->property("height").toInt() == 640;
        if (!rightSize || borderStatus != 1 || animatedStatus != 1 || !looped) {
            d = QString::fromLatin1("size=%1x%2 border-status=%3 animated-status=%4 frames=%5 looped=%6")
                    .arg(object->property("width").toInt())
                    .arg(object->property("height").toInt())
                    .arg(borderStatus).arg(animatedStatus).arg(frames)
                    .arg(looped ? "yes" : "no");
        }
        delete object;
        return rightSize && borderStatus == 1 && animatedStatus == 1 && looped;
    });

    r.check("declarative1/engine-and-component", [](QString &d) {
        SmokeQt4QmlEngine engine;
        QDeclarativeComponent component(&engine);
        component.setData("import QtQuick 1.0\nQtObject { property int answer: 6 * 7 }",
                          QUrl());
        if (component.isError()) {
            const QList<QDeclarativeError> errors = component.errors();
            d = errors.isEmpty() ? component.errorString()
                                 : errors.first().toString();
            return false;
        }
        QObject *object = component.create();
        const int answer = object ? object->property("answer").toInt() : -1;
        d = QString::fromLatin1("answer %1").arg(answer);
        delete object;
        return answer == 42;
    });

    r.check("declarative1/context-and-property", [](QString &d) {
        SmokeQt4QmlEngine engine;
        QDeclarativeContext context(&engine);
        context.setContextProperty(QLatin1String("injected"), QVariant(4887));
        QDeclarativeComponent component(&engine);
        component.setData("import QtQuick 1.0\nQtObject { property int taken: injected }",
                          QUrl());
        QObject *object = component.create(&context);
        const int taken = object ? object->property("taken").toInt() : -1;
        QDeclarativeProperty property(object, QLatin1String("taken"));
        d = QString::fromLatin1("taken %1, property valid %2")
                .arg(taken).arg(property.isValid() ? "yes" : "no");
        const bool ok = taken == 4887 && property.isValid();
        delete object;
        return ok;
    });

    r.check("declarative1/expression", [](QString &d) {
        SmokeQt4QmlEngine engine;
        QDeclarativeContext context(&engine);
        QDeclarativeExpression expression(&context, 0, QLatin1String("3 * 14"));
        const QVariant value = expression.evaluate();
        d = QString::fromLatin1("evaluated to %1").arg(value.toInt());
        return !expression.hasError() && value.toInt() == 42;
    });

    r.check("declarative1/property-map", [](QString &d) {
        QDeclarativePropertyMap map;
        map.insert(QLatin1String("name"), QVariant(QLatin1String("qt4")));
        d = QString::fromLatin1("keys %1, name '%2'")
                .arg(map.keys().count()).arg(map.value(QLatin1String("name")).toString());
        return map.contains(QLatin1String("name"))
            && map.value(QLatin1String("name")).toString() == QLatin1String("qt4");
    });

    r.check("declarative1/view-and-item", [](QString &d) {
        QDeclarativeView view;
        view.setSource(QUrl());
        SmokeItem item;
        item.componentComplete();
        d = QString::fromLatin1("view status %1, item completed %2")
                .arg(int(view.status())).arg(item.completed ? "yes" : "no");
        return item.completed && view.engine() != 0 && view.rootContext() != 0;
    });

    r.check("declarative1/image-provider", [](QString &d) {
        SmokeQt4QmlEngine engine;
        engine.addImageProvider(QLatin1String("smoke"), new SmokeImageProvider);
        QSize size;
        SmokeImageProvider provider;
        const QImage image = provider.requestImage(QLatin1String("x"), &size, QSize());
        d = QString::fromLatin1("%1x%2").arg(image.width()).arg(image.height());
        return image.width() == 8 && engine.imageProvider(QLatin1String("smoke")) != 0;
    });

    r.check("declarative1/list-reference-and-script-string", [](QString &d) {
        SmokeQt4QmlEngine engine;
        QDeclarativeComponent component(&engine);
        component.setData("import QtQuick 1.0\nItem { }", QUrl());
        QObject *object = component.create();
        QDeclarativeListReference children(object, "children");
        QDeclarativeScriptString script;
        script.setScript(QLatin1String("1 + 1"));
        d = QString::fromLatin1("list valid %1, script '%2'")
                .arg(children.isValid() ? "yes" : "no", script.script());
        const bool ok = script.script() == QLatin1String("1 + 1");
        delete object;
        return ok;
    });

    r.check("declarative1/interfaces-an-app-implements", [](QString &d) {
        // The remaining public surface is interfaces rather than objects: a
        // plugin, a network factory, a property value source and the debugging
        // hook. They are named here because an application that extends QML
        // implements them, which is the only way they can be referenced.
        d = QLatin1String("extension, network factory, value source, debugger hook");
        return sizeof(QDeclarativeExtensionPlugin) > 0
            && sizeof(QDeclarativeExtensionInterface) > 0
            && sizeof(QDeclarativeNetworkAccessManagerFactory) > 0
            && sizeof(QDeclarativeParserStatus) > 0
            && sizeof(QDeclarativePropertyValueSource) > 0
            && sizeof(QDeclarativePropertyValueInterceptor) > 0
            && sizeof(QDeclarativeDebuggingEnabler) > 0;
    });
}

void checkDeclarative1Pages(SmokeReporter &r)
{
    QDeclarativeView view;
    const bool shaders = configureQt4QmlView(view);
    view.resize(940, 640);
    r.check("declarative1/gallery-view-load", [&](QString &d) {
        view.setSource(QUrl("qrc:/qml_qt4/qml_qt4/main.qml"));
        if (view.status() != QDeclarativeView::Ready || !view.rootObject()) {
            const QList<QDeclarativeError> errors = view.errors();
            d = errors.isEmpty() ? QStringLiteral("no root item") : errors.first().toString();
            return false;
        }
        view.show();
        QApplication::processEvents();
        QDeclarativeExpression count(view.rootContext(), view.rootObject(), "names.length");
        return count.evaluate().toInt() == 14;
    });
    if (!view.rootObject()) return;
    QImage sheet(320 * 4, 250 * 4, QImage::Format_RGB32);
    sheet.fill(0xffffffff);
    QImage effectsFrame;
    QPoint shaderSample;
    for (int index = 0; index < 14; ++index) {
        QDeclarativeExpression title(view.rootContext(), view.rootObject(),
                                    QString("names[%1]").arg(index));
        const QString label = title.evaluate().toString();
        r.check(QStringLiteral("declarative1/page-render-%1").arg(label),
                [&, index, label](QString &d) {
            if (!view.rootObject()->setProperty("section", index)) return false;
            QEventLoop loop;
            QTimer::singleShot(80, &loop, SLOT(quit()));
            loop.exec();
            view.viewport()->repaint();
            QApplication::processEvents();
            QImage frame;
            if (shaders) {
                QGLWidget *glViewport = static_cast<QGLWidget *>(view.viewport());
                glViewport->makeCurrent();
                frame = glViewport->grabFrameBuffer();
            } else {
                frame = QImage(view.viewport()->size(), QImage::Format_RGB32);
                frame.fill(0xffff00ff);
                QPainter painter(&frame);
                view.render(&painter);
            }
            if (frame.isNull()) return false;
            int varied = 0;
            const QRgb corner = frame.pixel(0, 0);
            for (int y = 100; y < frame.height(); y += 4)
                for (int x = 220; x < frame.width(); x += 4)
                    if (frame.pixel(x, y) != corner) ++varied;
            QPainter contact(&sheet);
            const int left = (index % 4) * 320, top = (index / 4) * 250;
            contact.drawText(left + 8, top + 18, label);
            contact.drawImage(QRect(left, top + 25, 320, 225), frame);
            if (index == 10) {
                effectsFrame = frame;
                QDeclarativeItem *effect = view.rootObject()->findChild<QDeclarativeItem *>("shaderEffectProbe");
                if (effect) shaderSample = view.mapFromScene(effect->mapToScene(
                    QPointF(effect->width() / 2, effect->height() / 4)));
            }
            if (index == 0 || index == 7 || index == 10) {
                d = QDir(QCoreApplication::applicationDirPath()).filePath(
                    QString("qml-page-%1.png").arg(index, 2, 10, QLatin1Char('0')));
                if (!frame.save(d, "PNG")) return false;
            }
            return varied > 100 && view.rootObject()->property("section").toInt() == index;
        });
    }
    r.check("declarative1/page-contact-sheet", [&](QString &d) {
        d = QDir(QCoreApplication::applicationDirPath()).filePath("qml-gallery-pages.png");
        return sheet.save(d, "PNG");
    });
    r.check("declarative1/shader-output", [&](QString &d) {
        if (!shaders) {
            r.skip(d, QStringLiteral("GLSL/FBO driver support unavailable; gallery uses raster rendering"));
            return false;
        }
        QDeclarativeItem *effect = view.rootObject()->findChild<QDeclarativeItem *>("shaderEffectProbe");
        if (!effect || effectsFrame.isNull()) return false;
        const QPoint position = shaderSample;
        if (!effectsFrame.rect().contains(position)) return false;
        const QRgb pixel = effectsFrame.pixel(position);
        d = QStringLiteral("shader sample RGB=%1,%2,%3").arg(qRed(pixel)).arg(qGreen(pixel)).arg(qBlue(pixel));
        return qRed(pixel) + qGreen(pixel) + qBlue(pixel) > 170;
    });
    r.check("declarative1/sidebar-mouse-navigation", [&](QString &d) {
        view.activateWindow();
        view.setFocus();
        QApplication::processEvents();
        QDeclarativeItem *row = nullptr;
        foreach (QGraphicsItem *item, view.scene()->items()) {
            QDeclarativeItem *candidate = dynamic_cast<QDeclarativeItem *>(item);
            if (candidate && candidate->objectName() == "navigationRow7") { row = candidate; break; }
        }
        if (!row) { d = QStringLiteral("navigation delegate not found"); return false; }
        const QPoint position = view.mapFromScene(row->mapToScene(row->boundingRect().center()));
        QGraphicsSceneMouseEvent press(QEvent::GraphicsSceneMousePress);
        QGraphicsSceneMouseEvent release(QEvent::GraphicsSceneMouseRelease);
        press.setScenePos(view.mapToScene(position));
        release.setScenePos(view.mapToScene(position));
        press.setButton(Qt::LeftButton);
        release.setButton(Qt::LeftButton);
        press.setButtons(Qt::LeftButton);
        release.setButtons(Qt::NoButton);
        QApplication::sendEvent(view.scene(), &press);
        QApplication::sendEvent(view.scene(), &release);
        QApplication::processEvents();
        d = QStringLiteral("click=%1,%2 section=%3 press-accepted=%4 release-accepted=%5")
            .arg(position.x()).arg(position.y()).arg(view.rootObject()->property("section").toInt())
            .arg(press.isAccepted()).arg(release.isAccepted());
        return view.rootObject()->property("section").toInt() == 7;
    });
}
