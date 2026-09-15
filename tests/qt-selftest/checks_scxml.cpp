// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// QtScxml checks: parse a minimal inline state chart (no external .scxml
// file or generated C++ data model needed) and drive it through a real
// transition, exercising the state machine, its data model, and events.
#include "../common/smokecheck.h"

#if !SMOKE_QT5

void checkScxml(SmokeReporter &r)
{
    r.check("scxml/module", [&](QString &d) {
        r.skip(d, QStringLiteral("QtScxml has no Qt 4 module"));
        return false;
    });
}

#else

#include <QScxmlStateMachine>
#include <QScxmlError>
#include <QScxmlEvent>
#include <QScxmlDataModel>
#include <QScxmlNullDataModel>
#if QT_VERSION_MAJOR < 6
#include <QScxmlEcmaScriptDataModel>
#endif
#include <QScxmlCppDataModel>
#include <QScxmlCompiler>
#include <QScxmlTableData>
#include <QScxmlInvokableService>
#include <QScxmlStaticScxmlServiceFactory>
#include <QScxmlDynamicScxmlServiceFactory>
#include <QXmlStreamReader>
#include <QMetaObject>
#include <QBuffer>
#include <QCoreApplication>
#include <QElapsedTimer>

void checkScxml(SmokeReporter &r)
{
    r.check("scxml/parse-and-run", [&](QString &d) {
        static const char *scxml =
            "<scxml xmlns='http://www.w3.org/2005/07/scxml' version='1.0' initial='a'>"
            "<state id='a'><transition event='go' target='b'/></state>"
            "<final id='b'/>"
            "</scxml>";
        QByteArray bytes(scxml);
        QBuffer buffer(&bytes);
        buffer.open(QIODevice::ReadOnly);
        QScxmlStateMachine *machine = QScxmlStateMachine::fromData(&buffer);
        if (!machine || !machine->parseErrors().isEmpty()) {
            d = machine ? machine->parseErrors().first().toString() : "fromData returned null";
            delete machine;
            return false;
        }
        machine->init();
        machine->start();
        // start() and submitEvent() queue work for the machine's event processing, and
        // this app never calls exec(): pump events before "go" and after.
        QElapsedTimer t; t.start();
        while (!machine->isActive(QStringLiteral("a")) && t.elapsed() < 2000)
            QCoreApplication::processEvents();
        bool activeA = machine->isActive(QStringLiteral("a"));
        machine->submitEvent(QStringLiteral("go"));
        t.restart();
        while (machine->isRunning() && !machine->isActive(QStringLiteral("b")) && t.elapsed() < 2000)
            QCoreApplication::processEvents();
        bool finished = !machine->isRunning() || machine->isActive(QStringLiteral("b"));
        if (!activeA || !finished) {
            d = QString("activeA=%1 running=%2 activeB=%3").arg(activeA)
                    .arg(machine->isRunning()).arg(machine->isActive(QStringLiteral("b")));
        }
        delete machine;
        return activeA && finished;
    });
    r.check("scxml/error-value-type", [&](QString &d) {
        QScxmlError err(QStringLiteral("test.scxml"), 3, 5, QStringLiteral("bad state"));
        return err.line() == 3 && err.column() == 5 && err.description().contains("bad");
    });
    r.check("scxml/event-value-type", [&](QString &d) {
        QScxmlEvent event;
        event.setName(QStringLiteral("go"));
        event.setData(QVariant(42));
        return event.name() == QStringLiteral("go") && event.data().toInt() == 42;
    });
    r.check("scxml/datamodels-construct", [&](QString &d) {
        // QScxmlCppDataModel itself is still abstract: the four
        // evaluateTo*() overrides come from the Q_SCXML_DATAMODEL macro,
        // meant to be invoked by qscxmlc's *generated* subclasses - a
        // hand-written minimal subclass fills in the same four.
        class MinimalCppDataModel : public QScxmlCppDataModel {
        public:
            QString evaluateToString(QScxmlExecutableContent::EvaluatorId, bool *ok) override {
                *ok = true; return QString();
            }
            bool evaluateToBool(QScxmlExecutableContent::EvaluatorId, bool *ok) override {
                *ok = true; return true;
            }
            QVariant evaluateToVariant(QScxmlExecutableContent::EvaluatorId, bool *ok) override {
                *ok = true; return QVariant();
            }
            void evaluateToVoid(QScxmlExecutableContent::EvaluatorId, bool *ok) override { *ok = true; }
        };
        QScxmlNullDataModel nullModel;
#if QT_VERSION_MAJOR < 6
        QScxmlEcmaScriptDataModel ecmaModel;
#endif
        MinimalCppDataModel cppModel;
        // Reached through the real base class all three are registered
        // against a state machine as -
        // QScxmlStateMachine::setDataModel(QScxmlDataModel*).
        QScxmlDataModel *asBase1 = &nullModel;
#if QT_VERSION_MAJOR < 6
        QScxmlDataModel *asBase2 = &ecmaModel;
#else
        QScxmlDataModel *asBase2 = &nullModel;   // no ECMAScript data model in Qt 6
#endif
        QScxmlDataModel *asBase3 = &cppModel;
        return asBase1 != nullptr && asBase2 != nullptr && asBase3 != nullptr;
    });
    r.check("scxml/compiler", [&](QString &d) {
        static const char *scxml =
            "<scxml xmlns='http://www.w3.org/2005/07/scxml' version='1.0' initial='a'>"
            "<state id='a'/></scxml>";
        QByteArray scxmlBytes(scxml);
        QXmlStreamReader reader(scxmlBytes);
        QScxmlCompiler compiler(&reader);
        QScxmlStateMachine *machine = compiler.compile();
        bool ok = machine != nullptr && compiler.errors().isEmpty();
        delete machine;
        return ok;
    });
    r.check("scxml/tabledata-and-invokable-service", [&](QString &d) {
        // QScxmlTableData is what qscxmlc's generated code implements;
        // QScxmlInvokableService(Factory) invokes a nested service. Minimal stand-ins
        // for both, driven through their interfaces.
        class FixedTableData : public QScxmlTableData {
        public:
            QString string(QScxmlExecutableContent::StringId) const override { return QStringLiteral("s"); }
            QScxmlExecutableContent::InstructionId *instructions() const override { return nullptr; }
            QScxmlExecutableContent::EvaluatorInfo evaluatorInfo(QScxmlExecutableContent::EvaluatorId) const override {
                return { QScxmlExecutableContent::NoString, QScxmlExecutableContent::NoString };
            }
            QScxmlExecutableContent::AssignmentInfo assignmentInfo(QScxmlExecutableContent::EvaluatorId) const override {
                return { QScxmlExecutableContent::NoString, QScxmlExecutableContent::NoString,
                         QScxmlExecutableContent::NoString };
            }
            QScxmlExecutableContent::ForeachInfo foreachInfo(QScxmlExecutableContent::EvaluatorId) const override {
                return { QScxmlExecutableContent::NoString, QScxmlExecutableContent::NoString,
                         QScxmlExecutableContent::NoString, QScxmlExecutableContent::NoString };
            }
            QScxmlExecutableContent::StringId *dataNames(int *count) const override { *count = 0; return nullptr; }
            QScxmlExecutableContent::ContainerId initialSetup() const override {
                return QScxmlExecutableContent::NoContainer;
            }
            QString name() const override { return QStringLiteral("qt-smoke-machine"); }
            const qint32 *stateMachineTable() const override { return nullptr; }
            QScxmlInvokableServiceFactory *serviceFactory(int) const override { return nullptr; }
        };
        FixedTableData tableData;

        class FixedService : public QScxmlInvokableService {
        public:
            using QScxmlInvokableService::QScxmlInvokableService;
            bool start() override { return true; }
            QString id() const override { return QStringLiteral("svc"); }
            QString name() const override { return QStringLiteral("fixed-service"); }
            void postEvent(QScxmlEvent *event) override { delete event; }
        };
        class FixedServiceFactory : public QScxmlInvokableServiceFactory {
        public:
            using QScxmlInvokableServiceFactory::QScxmlInvokableServiceFactory;
            QScxmlInvokableService *invoke(QScxmlStateMachine *parentMachine) override {
                return new FixedService(parentMachine, this);
            }
        };

        QByteArray bytes("<scxml xmlns='http://www.w3.org/2005/07/scxml' version='1.0' initial='a'>"
                         "<state id='a'/></scxml>");
        QBuffer buf(&bytes);
        buf.open(QIODevice::ReadOnly);
        QScxmlStateMachine *machine = QScxmlStateMachine::fromData(&buf);

        using namespace QScxmlExecutableContent;
        InvokeInfo invokeInfo{ NoString, NoString, NoString, NoString, NoEvaluator, NoContainer, false };
        FixedServiceFactory factory(invokeInfo, QVector<StringId>(), QVector<ParameterInfo>());
        QScxmlInvokableService *service = factory.invoke(machine);

        bool ok = tableData.name() == QStringLiteral("qt-smoke-machine")
            && tableData.initialSetup() == QScxmlExecutableContent::NoContainer
            && service->start() && service->id() == QStringLiteral("svc");
        delete service;
        delete machine;
        return ok;
    });
    r.check("scxml/static-and-dynamic-service-factory", [&](QString &d) {
        // Both are concrete factories generated code uses to describe an
        // <invoke> element's target - InvokeInfo/StringId/ParameterInfo are
        // plain index structs into the (here, absent) compiled string table,
        // zero-initialized since there's no real table backing them.
        using namespace QScxmlExecutableContent;
        InvokeInfo invokeInfo{ NoString, NoString, NoString, NoString, NoEvaluator, NoContainer, false };
        QVector<StringId> names;
        QVector<ParameterInfo> params;

        QScxmlStaticScxmlServiceFactory staticFactory(&QObject::staticMetaObject, invokeInfo, names, params);
        QScxmlDynamicScxmlServiceFactory dynamicFactory(invokeInfo, names, params);

        QScxmlInvokableServiceFactory *base1 = &staticFactory;
        QScxmlInvokableServiceFactory *base2 = &dynamicFactory;
        return base1 != nullptr && base2 != nullptr;
    });
}

#endif // SMOKE_QT5
