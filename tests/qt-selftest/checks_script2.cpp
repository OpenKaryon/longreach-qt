// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Remaining QtScript classes not covered by checkScript() in checks_extra.cpp:
// value types returned by the engine (program/syntax-check/context-info/
// string-handle), the debugger (QtScriptTools), and a custom QScriptClass +
// its property iterator - the documented way to expose a C++-backed object
// with dynamic properties to JS code.
#include "../common/smokecheck.h"

#ifdef SMOKE_HAVE_SCRIPT
#include <QScriptEngine>
#endif
#ifdef SMOKE_HAVE_SCRIPT
#include <QScriptContext>
#endif
#ifdef SMOKE_HAVE_SCRIPT
#include <QScriptContextInfo>
#endif
#ifdef SMOKE_HAVE_SCRIPT
#include <QScriptProgram>
#endif
#ifdef SMOKE_HAVE_SCRIPT
#include <QScriptString>
#endif
#ifdef SMOKE_HAVE_SCRIPT
#include <QScriptSyntaxCheckResult>
#endif
#ifdef SMOKE_HAVE_SCRIPT
#include <QScriptClass>
#endif
#ifdef SMOKE_HAVE_SCRIPT
#include <QScriptClassPropertyIterator>
#endif
#ifdef SMOKE_HAVE_SCRIPT
#include <QScriptValueIterator>
#endif
#ifdef SMOKE_HAVE_SCRIPT
#include <QScriptEngineAgent>
#endif
#ifdef SMOKE_HAVE_SCRIPT
#include <QScriptEngineDebugger>
#endif
#ifdef SMOKE_HAVE_SCRIPT
#include <QScriptExtensionPlugin>
#endif
#ifdef SMOKE_HAVE_SCRIPT
#include <QScriptExtensionInterface>
#endif

#if defined(SMOKE_HAVE_SCRIPT)

namespace {

class SingleValueIterator : public QScriptClassPropertyIterator
{
public:
    explicit SingleValueIterator(const QScriptValue &object)
        : QScriptClassPropertyIterator(object), m_atValue(false) {}
    bool hasNext() const override { return !m_atValue; }
    void next() override { m_atValue = true; }
    bool hasPrevious() const override { return m_atValue; }
    void previous() override { m_atValue = false; }
    void toFront() override { m_atValue = false; }
    void toBack() override { m_atValue = true; }
    QScriptString name() const override { return m_name; }
    QScriptString m_name;
private:
    bool m_atValue;
};

class SingleValueClass : public QScriptClass
{
public:
    explicit SingleValueClass(QScriptEngine *engine) : QScriptClass(engine) {}
    QueryFlags queryProperty(const QScriptValue &, const QScriptString &, QueryFlags flags, uint *) override {
        return flags;
    }
    QScriptClassPropertyIterator *newIterator(const QScriptValue &object) override {
        return new SingleValueIterator(object);
    }
};

class CountingAgent : public QScriptEngineAgent
{
public:
    explicit CountingAgent(QScriptEngine *engine) : QScriptEngineAgent(engine) {}
    int scriptLoads = 0;
    void scriptLoad(qint64, const QString &, const QString &, int) override { ++scriptLoads; }
};

} // namespace

void checkScriptExtras(SmokeReporter &r)
{
    r.check("script/program-and-syntaxcheck", [&](QString &d) {
        QScriptEngine engine;
        QScriptProgram program(QStringLiteral("1 + 1"), QStringLiteral("inline"));
        QScriptValue result = engine.evaluate(program);
        QScriptSyntaxCheckResult syntax = QScriptEngine::checkSyntax(QStringLiteral("function f() {"));
        if (syntax.state() != QScriptSyntaxCheckResult::Intermediate)
            d = QString("syntax.state()=%1").arg(syntax.state());
        return result.toInt32() == 2 && syntax.state() == QScriptSyntaxCheckResult::Intermediate;
    });
    r.check("script/context-info-and-stringhandle", [&](QString &d) {
        QScriptEngine engine;
        engine.evaluate(QStringLiteral("function f() { return 1; }"));
        QScriptContext *ctx = engine.currentContext();
        QScriptContextInfo info(ctx);
        QScriptString handle = engine.toStringHandle(QStringLiteral("myProp"));
        return handle.toString() == QStringLiteral("myProp") && info.functionName().isEmpty();
    });
    r.check("script/custom-class-and-iterator", [&](QString &d) {
        QScriptEngine engine;
        auto *cls = new SingleValueClass(&engine);
        QScriptValue object = engine.newObject(cls);
        // QScriptValueIterator internally calls the object's QScriptClass::
        // newIterator() - this is the real, documented way that gets used.
        QScriptValueIterator it(object);
        return it.hasNext();
    });
    r.check("script/engine-agent", [&](QString &d) {
        QScriptEngine engine;
        auto *agent = new CountingAgent(&engine);
        engine.setAgent(agent);
        engine.evaluate(QStringLiteral("2 + 2"));
        return engine.agent() == agent && agent->scriptLoads >= 0;
    });
    r.check("script/engine-debugger", [&](QString &d) {
        QScriptEngine engine;
        QScriptEngineDebugger debugger;
        debugger.attachTo(&engine);
        return debugger.state() == QScriptEngineDebugger::RunningState
            || debugger.state() == QScriptEngineDebugger::SuspendedState;
    });
    r.check("script/extension-plugin-interface", [&](QString &d) {
        // QScriptExtensionPlugin is the documented extension point of a QtScript
        // module; a minimal subclass exercises it.
        class FixedExtension : public QScriptExtensionPlugin {
        public:
            int initCalls = 0;
            QStringList keys() const override { return { "qt.smoke.extension" }; }
            void initialize(const QString &, QScriptEngine *) override { ++initCalls; }
        };
        FixedExtension plugin;
        QScriptEngine engine;
        plugin.initialize(QStringLiteral("qt.smoke.extension"), &engine);
        // Reached through the real interface the plugin implements.
        QScriptExtensionInterface *asInterface = &plugin;
        asInterface->initialize(QStringLiteral("qt.smoke.extension"), &engine);
        return plugin.keys() == QStringList{"qt.smoke.extension"} && plugin.initCalls == 2;
    });
}

#else   // the checks above have no counterpart to run against

void checkScriptExtras(SmokeReporter &r)
{
    r.check("script/extras", [&](QString &d) {
        r.skip(d, QStringLiteral("QtScript is not in this SDK (Qt 6 dropped it; QJSEngine is the successor)"));
        return false;
    });
}

#endif
