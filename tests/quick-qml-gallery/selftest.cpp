// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// QML engine/binding checks. Qt4 also shows and renders every gallery page;
// the Qt5/6 branch below exercises components without a QQuickWindow.
#include "../common/smokecheck.h"

#if !SMOKE_QT5

#include <QDir>
#include <QCoreApplication>

// Qt 4: every class below is QQml*/QJS*, which arrived with Qt 5. The QtQuick 1
// engine it does have is checked in checks_declarative1_qt4.cpp next door.
void addDeclarative1Checks(SmokeReporter &r);
void checkDeclarative1Pages(SmokeReporter &r);

int runSelfTest()
{
    SmokeReporter r("quick-qml");
    r.setTrace(true);
    if (!r.setLogFile(QDir(QCoreApplication::applicationDirPath()).filePath("qml-selftest.log")))
        return 2;
    addDeclarative1Checks(r);
    checkDeclarative1Pages(r);
    return r.summary();
}

#else

#include <QQmlEngine>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlProperty>
#include <QQmlPropertyMap>
#include <QJSEngine>
#include <QJSValue>
#include <QObject>
#include <QQuickStyle>
#include <QStringList>
#include <QVariant>

#include <memory>

void checkJsEngine(SmokeReporter &r)
{
    r.check("qml/jsengine-eval", [&](QString &d) {
        QJSEngine js;
        QJSValue result = js.evaluate("2 + 3 * 4");
        if (js.evaluate("1").isError()) { d = "engine broken"; return false; }
        return result.toInt() == 14;
    });
    r.check("qml/jsengine-function-call", [&](QString &d) {
        QJSEngine js;
        js.evaluate("function greet(name) { return 'hi ' + name; }");
        QJSValue fn = js.globalObject().property("greet");
        QJSValue res = fn.call(QJSValueList{ QJSValue("xp") });
        return res.toString() == "hi xp";
    });
    r.check("qml/jsvalue-object-props", [&](QString &d) {
        QJSEngine js;
        QJSValue obj = js.newObject();
        obj.setProperty("a", 5);
        obj.setProperty("b", QJSValue("hi"));
        return obj.property("a").toInt() == 5 && obj.property("b").toString() == "hi";
    });
}

void checkComponent(SmokeReporter &r)
{
    r.check("qml/component-instantiate", [&](QString &d) {
        QQmlEngine engine;
        QQmlComponent comp(&engine);
        comp.setData("import QtQuick 2.15\nQtObject { property int val: 42 }", QUrl());
        QObject *obj = comp.create();
        if (!obj) { d = comp.errorString(); return false; }
        int v = QQmlProperty::read(obj, "val").toInt();
        delete obj;
        return v == 42;
    });
    r.check("qml/context-property-binding", [&](QString &d) {
        QQmlEngine engine;
        QQmlContext ctx(engine.rootContext());
        ctx.setContextProperty("extern_", 7);
        QQmlComponent comp(&engine);
        comp.setData("import QtQuick 2.15\nQtObject { property int doubled: extern_ * 2 }", QUrl());
        QObject *obj = comp.create(&ctx);
        if (!obj) { d = comp.errorString(); return false; }
        int v = obj->property("doubled").toInt();
        delete obj;
        if (v != 14) { d = QString("doubled=%1").arg(v); return false; }
        return true;
    });
    r.check("qml/qmlproperty-write", [&](QString &d) {
        QQmlEngine engine;
        QQmlComponent comp(&engine);
        comp.setData("import QtQuick 2.15\nQtObject { property string label: 'x' }", QUrl());
        QObject *obj = comp.create();
        if (!obj) { d = comp.errorString(); return false; }
        QQmlProperty prop(obj, "label");
        bool wrote = prop.write("changed");
        QString back = obj->property("label").toString();
        delete obj;
        return wrote && back == "changed";
    });
    r.check("qml/component-error-detection", [&](QString &d) {
        QQmlEngine engine;
        QQmlComponent comp(&engine);
        comp.setData("import QtQuick 2.15\nQtObject { this is not valid qml", QUrl());
        // Synchronous compile happens on setData(); errors are available immediately.
        return comp.isError() && !comp.errors().isEmpty();
    });
}

void checkPropertyMap(SmokeReporter &r)
{
    r.check("qml/propertymap-insert-value", [&](QString &d) {
        QQmlPropertyMap map;
        map.insert("width", 100);
        map.insert("name", QString("gallery"));
        // valueChanged() is documented to fire only for writes coming from the
        // QML/UI side (a bound property changing), never for insert() calls
        // made from C++ - so there's nothing to connect to here; just verify
        // insert()/value()/operator[] agree on the stored value.
        map.insert("width", 200);
        return map["width"].toInt() == 200 && map.value("name").toString() == "gallery";
    });
}

void checkQuickStyle(SmokeReporter &r)
{
    r.check("qml/quickstyle-name", [&](QString &d) {
        // Must be set before any QQuickWindow/engine is created - fine here
        // since --selftest never loads the visual QML.
        QQuickStyle::setStyle(QStringLiteral("Fusion"));
        return QQuickStyle::name() == QStringLiteral("Fusion");
    });
}

void checkVisualQmlFiles(SmokeReporter &r)
{
    r.check("qml/visual-files-compile", [&](QString &d) {
        QQmlEngine engine;
        const QString mainFile = QStringLiteral("qrc:/qml/main.qml");
        const QStringList creatableFiles = {
            QStringLiteral("qrc:/qml/ControlsTab.qml"),
            QStringLiteral("qrc:/qml/Controls2CatalogTab.qml"),
            QStringLiteral("qrc:/qml/NavigationPopupTab.qml"),
            QStringLiteral("qrc:/qml/PlatformDialogTab.qml"),
            QStringLiteral("qrc:/qml/WindowLabTab.qml"),
            QStringLiteral("qrc:/qml/AccordionViewsTab.qml"),
            QStringLiteral("qrc:/qml/TableViewTab.qml"),
            QStringLiteral("qrc:/qml/InputTextTab.qml"),
            QStringLiteral("qrc:/qml/CanvasShaderTab.qml"),
            QStringLiteral("qrc:/qml/ParticlesTab.qml"),
            QStringLiteral("qrc:/qml/GraphicalEffectsTab.qml"),
            QStringLiteral("qrc:/qml/ShapesTab.qml"),
            QStringLiteral("qrc:/qml/AnimationTab.qml"),
            QStringLiteral("qrc:/qml/ListTab.qml")
        };

        QQmlComponent mainComp(&engine, QUrl(mainFile));
        if (mainComp.isError()) {
            d = mainFile + QStringLiteral(": ") + mainComp.errorString();
            return false;
        }

        for (const QString &file : creatableFiles) {
            QQmlComponent comp(&engine, QUrl(file));
            if (comp.isError()) {
                d = file + QStringLiteral(": ") + comp.errorString();
                return false;
            }
            std::unique_ptr<QObject> obj(comp.create());
            if (!obj) {
                d = file + QStringLiteral(": ") + comp.errorString();
                return false;
            }
        }
        return true;
    });
}

#ifdef SMOKE_HAVE_QUICK3D
void checkQuick3D(SmokeReporter &r);
#endif
void checkQuickItems(SmokeReporter &r);
void checkSceneGraphNodes(SmokeReporter &r);
void checkSceneGraphRenderPath(SmokeReporter &r);
void checkNativeTextures(SmokeReporter &r);
void checkSceneGraphFactories(SmokeReporter &r);
void checkWaylandQuick(SmokeReporter &r);
#if QT_VERSION_MAJOR == 5
void checkQt5SceneGraphEngine(SmokeReporter &r);
#endif

int runSelfTest()
{
    SmokeReporter r("quick-qml");
    checkJsEngine(r);
    checkComponent(r);
    checkPropertyMap(r);
    checkQuickStyle(r);
    checkVisualQmlFiles(r);
#ifdef SMOKE_HAVE_QUICK3D
    checkQuick3D(r);
#else
    r.check("quick3d/module-available", [&](QString &d) {
        r.skip(d, QStringLiteral("Qt Quick 3D is not in this SDK (needs OpenGL)"));
        return false;
    });
#endif
    checkQuickItems(r);
    checkSceneGraphNodes(r);
    checkSceneGraphRenderPath(r);
    checkNativeTextures(r);
    checkSceneGraphFactories(r);
#if QT_VERSION_MAJOR == 5
    checkQt5SceneGraphEngine(r);
#endif
    checkWaylandQuick(r);
    return r.summary();
}

#endif  // SMOKE_QT5
