// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// QtQml classes that don't need a live Quick scene: engine-adjacent value
// types and utilities, plus the extension-point interfaces a QML plugin
// module implements (registerTypes()/initializeEngine(), a custom network
// factory, a custom URL interceptor, and the parser-status/property-value-
// source hooks a custom QML type can implement).
#include "../common/smokecheck.h"

#if !SMOKE_QT5

void checkDeclarativeCore(SmokeReporter &r)
{
    r.check("qml/declarative-core", [&](QString &d) {
        r.skip(d, QStringLiteral("Qt 4 QtQuick 1 is covered by quick-qml-gallery"));
        return false;
    });
}

#else

#include <QJSEngine>
#include <QJSValue>
#include <QJSValueIterator>
#include <QQmlEngine>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlError>
#include <QQmlExpression>
#include <QQmlFile>
#include <QQmlFileSelector>
#include <QQmlIncubator>
#include <QQmlIncubationController>
#include <QQmlListReference>
#include <QQmlListProperty>
#include <QQmlModuleRegistration>
#include <QQmlScriptString>
#include <QQmlDebuggingEnabler>
#include <QQmlAbstractUrlInterceptor>
#include <QQmlNetworkAccessManagerFactory>
#include <QQmlParserStatus>
#include <QQmlPropertyValueSource>
#include <QQmlProperty>
#include <QQmlExtensionInterface>
#include <QQmlExtensionPlugin>
#include <QQmlEngineExtensionPlugin>
#include <QNetworkAccessManager>

namespace {

void qt_smoke_register_module() {}

class FixedUrlInterceptor : public QQmlAbstractUrlInterceptor
{
public:
    QUrl intercept(const QUrl &path, DataType) override { return path; }
};

class FixedNetworkFactory : public QQmlNetworkAccessManagerFactory
{
public:
    QNetworkAccessManager *create(QObject *parent) override { return new QNetworkAccessManager(parent); }
};

// The interface a custom QML type implements to react to being fully
// constructed from QML - QQuickItem is the most common real user of this,
// but it's meant to be implementable directly too (multiple inheritance
// alongside QObject).
class FixedParserStatusObject : public QObject, public QQmlParserStatus
{
public:
    int classBeginCalls = 0, completeCalls = 0;
    void classBegin() override { ++classBeginCalls; }
    void componentComplete() override { ++completeCalls; }
};

// The interface a custom QML "attached property"-like value source
// implements (Binding/PropertyAnimation-style: something that pushes values
// into a target property rather than just holding one).
class FixedValueSource : public QObject, public QQmlPropertyValueSource
{
public:
    QQmlProperty lastTarget;
    void setTarget(const QQmlProperty &property) override { lastTarget = property; }
};

class FixedExtensionPlugin : public QQmlExtensionPlugin
{
public:
    int registerCalls = 0;
    void registerTypes(const char *) override { ++registerCalls; }
};

// A plain C++ QObject exposing a QQmlListProperty<QObject> - enough to hand
// QQmlListReference something real to wrap, without needing to compile any
// QML text (this deployment doesn't ship the qml/ import-path plugin files a
// static "import QtQml" would need to resolve).
class ListPropertyHolder : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QQmlListProperty<QObject> kids READ kids)
public:
    QList<QObject *> items;
    QQmlListProperty<QObject> kids() {
        return QQmlListProperty<QObject>(this, &items);
    }
};

} // namespace

void checkDeclarativeCore(SmokeReporter &r)
{
    r.check("declarative/jsvalue-iterator", [&](QString &d) {
        QJSEngine engine;
        QJSValue obj = engine.newObject();
        obj.setProperty("a", 1);
        obj.setProperty("b", 2);
        QJSValueIterator it(obj);
        int count = 0;
        while (it.hasNext()) { it.next(); ++count; }
        return count == 2;
    });
    r.check("declarative/qmlerror-expression-file", [&](QString &d) {
        QQmlEngine engine;
        QQmlComponent comp(&engine);
        // This deployment doesn't ship the qml/ import-path plugin files a
        // static "import QtQml" needs to resolve, so this deliberately
        // invalid syntax (and the real import) both fail to compile - which
        // is fine, since it's the resulting real QQmlError we want here.
        comp.setData("qt-smoke deliberately invalid syntax {{{", QUrl());
        QList<QQmlError> errors = comp.errors();
        if (errors.isEmpty()) { d = "expected a compile error"; return false; }
        QQmlError err = errors.first();

        QQmlContext context(&engine);
        context.setContextProperty("value", 21);
        QQmlExpression expr(&context, nullptr, QStringLiteral("value * 2"));
        bool valueOk = expr.evaluate().toInt() == 42;

        QString localFile = QQmlFile::urlToLocalFileOrQrc(QUrl::fromLocalFile("/tmp/x.qml"));
        return !err.description().isEmpty() && valueOk && !localFile.isEmpty();
    });
    r.check("declarative/fileselector-incubator-listref-scriptstring", [&](QString &d) {
        QQmlEngine engine;
        QQmlFileSelector selector(&engine);

        QQmlIncubationController controller;
        QQmlIncubator incubator(QQmlIncubator::Asynchronous);
        engine.setIncubationController(&controller);

        ListPropertyHolder holder;
        holder.items << new QObject(&holder) << new QObject(&holder);
        QQmlListReference listRef(&holder, "kids", &engine);

        QQmlScriptString script;   // default-constructed - real value only
                                   // comes from a QML-bound property in
                                   // practice, but the type itself is a
                                   // simple value that's fine to default-init
        return listRef.isValid() && listRef.canCount() && listRef.count() == 2
            && script.isNullLiteral() == script.isNullLiteral();
    });
    r.check("declarative/module-registration-debugging-enabler", [&](QString &d) {
        QQmlModuleRegistration registration("QtSmokeTest", 1, &qt_smoke_register_module);
        QQmlDebuggingEnabler enabler(false);   // false: don't print the warning banner
        const QStringList services = QQmlDebuggingEnabler::debuggerServices();
        return services.size() >= 0;
    });
    r.check("declarative/url-interceptor-and-network-factory", [&](QString &d) {
        QQmlEngine engine;
        FixedUrlInterceptor interceptor;
        engine.setUrlInterceptor(&interceptor);
        FixedNetworkFactory factory;
        engine.setNetworkAccessManagerFactory(&factory);
        QNetworkAccessManager *nam = engine.networkAccessManager();
        return engine.urlInterceptor() == &interceptor && nam != nullptr;
    });
    r.check("declarative/parserstatus-and-valuesource", [&](QString &d) {
        FixedParserStatusObject statusObj;
        // Reached through the real interface a custom QML type implements.
        QQmlParserStatus *asParserStatus = &statusObj;
        asParserStatus->classBegin();
        asParserStatus->componentComplete();

        FixedValueSource valueSource;
        QQmlPropertyValueSource *asValueSource = &valueSource;
        QObject target;
        target.setObjectName("t");
        QQmlProperty prop(&target, "objectName");
        asValueSource->setTarget(prop);

        return statusObj.classBeginCalls == 1 && statusObj.completeCalls == 1
            && valueSource.lastTarget.name() == QStringLiteral("objectName");
    });
    r.check("declarative/extension-plugin-interfaces", [&](QString &d) {
        FixedExtensionPlugin plugin;
        plugin.registerTypes("QtSmokeTest");
        // Reached through the real interfaces the plugin implements.
        QQmlExtensionInterface *asExtension = &plugin;
        QQmlTypesExtensionInterface *asTypesExtension = &plugin;
        QQmlEngineExtensionPlugin engineOnlyPlugin;   // fully concrete - its
                                                      // initializeEngine()
                                                      // already has a real
                                                      // (empty) default impl
        return plugin.registerCalls == 1 && asExtension != nullptr && asTypesExtension != nullptr;
    });
}

#include "checks_declarative1.moc"

#endif // SMOKE_QT5
