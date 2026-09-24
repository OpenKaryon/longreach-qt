// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// A second batch of Qt 6 additions to QtCore, QtGui and QtQml - the ones left
// over after checks_qt6_qtbase.cpp, and a different kind of API from those.
//
// Most of what is here is an *interface*: a class whose only form is a subclass,
// because the implementation belongs to a backend rather than to an application.
// QAbstractUndoItem, the three accessibility interfaces and QSessionManager are
// all that shape - QSessionManager's constructor is private with QGuiApplication
// as its only friend, so the way an application names the type at all is the
// signature of the session signals. Naming them through a base pointer or a
// signal parameter is the whole of what a caller can do, and it is what the
// checks do.
//
// The rest are small value and helper types the property system and QVariant
// grew in Qt 6 and the suite had no reason to reach: QVariantConstPointer and
// QVariantTypeCoercer sit behind the mutable container iterators covered next
// door, and QPropertyBindingSourceLocation is what a binding records so that
// a dependency cycle can be reported against the line that wrote it.
#include "../common/smokecheck.h"

#include <QCoreApplication>
#include <QStringList>
#include <QVariant>

#if QT_VERSION_MAJOR >= 6
#include <QAbstractEventDispatcher>
#include <QAccessible>
#include <QGuiApplication>
#include <QJSEngine>
#include <QJSManagedValue>
#include <QJSValue>
#include <QMetaType>
#include <QProperty>
#include <QTextDocument>
#include <QWindow>
#include <QtGui/qevent.h>
// QPA. The suite already reaches this layer through Qt::GuiPrivate elsewhere;
// QSupportedWritingSystems is the one value type in it that a font database
// backend fills in rather than an interface it implements.
#include <qpa/qplatformfontdatabase.h>
#endif

#if QT_VERSION_MAJOR >= 6
namespace {

// QTextDocument's undo stack holds these rather than QUndoCommands, and the
// class is pure virtual, so a subclass is the only form it takes.
class SmokeUndoItem : public QAbstractUndoItem
{
public:
    void undo() override { --depth; }
    void redo() override { ++depth; }

    int depth = 0;
};

// The three accessibility interfaces Qt 6 added. Each is a standalone abstract
// class that an accessible object implements alongside QAccessibleInterface and
// hands back from interface_cast(), which is why they can be exercised on their
// own with no widget and no accessibility bridge running.
class SmokeAttributes : public QAccessibleAttributesInterface
{
public:
    QList<QAccessible::Attribute> attributeKeys() const override
    { return { QAccessible::Attribute::Level }; }

    QVariant attributeValue(QAccessible::Attribute key) const override
    { return key == QAccessible::Attribute::Level ? QVariant(2) : QVariant(); }
};

class SmokeHyperlink : public QAccessibleHyperlinkInterface
{
public:
    QString anchor() const override { return QStringLiteral("qt-smoke"); }
    QString anchorTarget() const override { return QStringLiteral("https://example.invalid/"); }
    int startIndex() const override { return 4; }
    int endIndex() const override { return 12; }
    bool isValid() const override { return true; }
};

class SmokeSelection : public QAccessibleSelectionInterface
{
public:
    int selectedItemCount() const override { return m_selected; }
    QList<QAccessibleInterface *> selectedItems() const override { return {}; }
    bool select(QAccessibleInterface *) override { ++m_selected; return true; }
    bool unselect(QAccessibleInterface *) override { --m_selected; return true; }
    bool selectAll() override { m_selected = 3; return true; }
    bool clear() override { m_selected = 0; return true; }

private:
    int m_selected = 0;
};

// QInternal's callback registry takes a plain function pointer, so the flag it
// sets has to live outside the lambda that checks it.
bool smokeInternalCallbackRan = false;

bool smokeInternalCallback(void **)
{
    smokeInternalCallbackRan = true;
    return false; // "not handled" - Qt carries on with its own notify path
}

} // namespace
#endif

void checkQt6QtBaseAdditions2(SmokeReporter &r)
{
    r.check("core/variant-const-pointer-and-type-coercer", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        // QVariantConstPointer is what a const mutable-iterator dereference
        // hands back: a QVariant that pretends to be a pointer to one, so that
        // operator-> works on a value that is materialised on demand.
        QVariantConstPointer pointer(QVariant(42));
        const QVariant dereferenced = *pointer;
        const bool arrowWorks = pointer->toInt() == 42;

        // The coercer converts a QVariant to a requested metatype and returns a raw
        // pointer. The variants are named, not temporaries: when no conversion is
        // needed the pointer points into the argument.
        QtPrivate::QVariantTypeCoercer coercer;
        const QVariant alreadyInt(17);
        const QVariant notANumber(QStringLiteral("nonsense"));

        const void *asInt = coercer.convert(alreadyInt, QMetaType::fromType<int>());
        // convert() only answers for a value that already is, or converts
        // cleanly to, the requested type; coerce() is the one that falls back
        // to a default-constructed value rather than refusing. A string that is
        // not a number is the case that separates them.
        const void *refused = coercer.convert(notANumber, QMetaType::fromType<int>());
        const void *coerced = coercer.coerce(notANumber, QMetaType::fromType<int>());

        QStringList misses;
        if (dereferenced.toInt() != 42) misses << QStringLiteral("dereference");
        if (!arrowWorks) misses << QStringLiteral("arrow");
        if (!asInt || *static_cast<const int *>(asInt) != 17)
            misses << QStringLiteral("convert");
        if (refused) misses << QStringLiteral("convert-refuses");
        if (!coerced || *static_cast<const int *>(coerced) != 0)
            misses << QStringLiteral("coerce");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QVariantConstPointer/QVariantTypeCoercer are Qt 6 only"));
        return false;
#endif
    });

    r.check("core/property-observer-and-binding-location", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        QProperty<int> source(1);
        QProperty<int> derived;

        // A binding carries the source location that created it, for binding-loop
        // reports; constructed explicitly, as QT_PROPERTY_DEFAULT_BINDING_LOCATION
        // needs std::source_location.
        QPropertyBindingSourceLocation location;
        location.fileName = "checks_qt6_qtbase2.cpp";
        location.functionName = "checkQt6QtBaseAdditions2";
        location.line = 1;

        QPropertyBinding<int> binding([&source]() { return source.value() * 10; }, location);
        derived.setBinding(binding);

        // QPropertyChangeHandler derives from QPropertyObserver - the node that
        // is actually threaded into the property's observer list. The handler is
        // the only way to make one, and upcasting is the only way to name it.
        int notifications = 0;
        auto handler = derived.onValueChanged([&notifications]() { ++notifications; });
        QPropertyObserver *observer = &handler;

        const int before = derived.value();
        source = 5;
        const int after = derived.value();

        QStringList misses;
        if (!binding.isNull()) {
            if (before != 10) misses << QStringLiteral("initial");
            if (after != 50) misses << QStringLiteral("propagated");
        } else {
            misses << QStringLiteral("binding");
        }
        if (notifications == 0) misses << QStringLiteral("observer-notified");
        if (!observer) misses << QStringLiteral("observer");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("the bindable property system is Qt 6 only"));
        return false;
#endif
    });

    r.check("core/property-binding-data-and-writing-systems", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        // QPropertyBindingData: one word holding a binding, observers or nothing; a
        // fresh one is nothing, with both flags false.
        QtPrivate::QPropertyBindingData bindingData;

        // What a platform font database reports about a font: which writing
        // systems it can render. Set-like, and the default is all-false.
        QSupportedWritingSystems writingSystems;
        writingSystems.setSupported(QFontDatabase::Latin, true);
        writingSystems.setSupported(QFontDatabase::Greek, true);
        writingSystems.setSupported(QFontDatabase::Greek, false);

        QStringList misses;
        if (bindingData.hasBinding()) misses << QStringLiteral("hasbinding");
        if (bindingData.isNotificationDelayed()) misses << QStringLiteral("delayed");
        if (!writingSystems.supported(QFontDatabase::Latin))
            misses << QStringLiteral("latin");
        if (writingSystems.supported(QFontDatabase::Greek))
            misses << QStringLiteral("greek-cleared");
        if (writingSystems.supported(QFontDatabase::Hebrew))
            misses << QStringLiteral("hebrew-unset");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("these are reached on Qt 6 here"));
        return false;
#endif
    });

    r.check("core/internal-callback-registry", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        // QInternal is the hook Qt's own tools use to intercept event delivery.
        // Registering one affects every event that follows, so this unregisters
        // before returning rather than leaving the rest of the run hooked.
        smokeInternalCallbackRan = false;

        const bool registered =
            QInternal::registerCallback(QInternal::EventNotifyCallback, smokeInternalCallback);

        void *args[3] = { nullptr, nullptr, nullptr };
        const bool handled = QInternal::activateCallbacks(QInternal::EventNotifyCallback, args);

        const bool unregistered =
            QInternal::unregisterCallback(QInternal::EventNotifyCallback, smokeInternalCallback);

        QStringList misses;
        if (!registered) misses << QStringLiteral("register");
        if (!smokeInternalCallbackRan) misses << QStringLiteral("activate");
        if (handled) misses << QStringLiteral("handled"); // the callback said "no"
        if (!unregistered) misses << QStringLiteral("unregister");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QInternal's callback registry is checked on Qt 6"));
        return false;
#endif
    });

    r.check("core/event-dispatcher-v2", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        // Qt 6.7 re-based the platform event dispatchers on a second interface
        // that takes Qt::TimerId and std::chrono durations instead of int
        // milliseconds. Which one this build got is a property of the platform
        // dispatcher, so the check asks rather than asserts.
        QAbstractEventDispatcher *dispatcher = QAbstractEventDispatcher::instance();
        if (!dispatcher) {
            d = QStringLiteral("no event dispatcher on the main thread");
            return false;
        }

        QAbstractEventDispatcherV2 *v2 = qobject_cast<QAbstractEventDispatcherV2 *>(dispatcher);
        if (!v2) {
            r.skip(d, QStringLiteral("this platform's dispatcher is not a V2"));
            return false;
        }

        // Reached through the V2 pointer, so it is the V2 overload set that is
        // being named: a duration rather than an int.
        const QList<QAbstractEventDispatcher::TimerInfoV2> timers =
            v2->timersForObject(QCoreApplication::instance());

        QStringList misses;
        if (!v2->inherits("QAbstractEventDispatcher")) misses << QStringLiteral("inherits");
        if (timers.size() < 0) misses << QStringLiteral("timers");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QAbstractEventDispatcherV2 is Qt 6 only"));
        return false;
#endif
    });

    r.check("gui/abstract-undo-item", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        SmokeUndoItem item;
        QAbstractUndoItem *asInterface = &item;

        asInterface->redo();
        asInterface->redo();
        asInterface->undo();

        QStringList misses;
        if (item.depth != 1) misses << QStringLiteral("undo-redo");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QAbstractUndoItem is reached on Qt 6 here"));
        return false;
#endif
    });

    r.check("gui/accessibility-attribute-hyperlink-selection-interfaces", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        SmokeAttributes attributes;
        SmokeHyperlink hyperlink;
        SmokeSelection selection;

        QAccessibleAttributesInterface *attributesInterface = &attributes;
        QAccessibleHyperlinkInterface *hyperlinkInterface = &hyperlink;
        QAccessibleSelectionInterface *selectionInterface = &selection;

        selectionInterface->selectAll();
        const int afterSelectAll = selectionInterface->selectedItemCount();
        selectionInterface->clear();
        selectionInterface->select(nullptr);

        QStringList misses;
        if (attributesInterface->attributeKeys().size() != 1)
            misses << QStringLiteral("attributekeys");
        if (attributesInterface->attributeValue(QAccessible::Attribute::Level).toInt() != 2)
            misses << QStringLiteral("attributevalue");
        if (hyperlinkInterface->anchor() != QStringLiteral("qt-smoke"))
            misses << QStringLiteral("anchor");
        if (hyperlinkInterface->startIndex() != 4 || hyperlinkInterface->endIndex() != 12)
            misses << QStringLiteral("anchor-range");
        if (!hyperlinkInterface->isValid()) misses << QStringLiteral("hyperlink-valid");
        if (afterSelectAll != 3) misses << QStringLiteral("selectall");
        if (selectionInterface->selectedItemCount() != 1) misses << QStringLiteral("select");
        // isSelected() is the interface's default. selectedItem() is not called: on an
        // empty selection Qt logs "Selection index out of range".
        if (selectionInterface->isSelected(nullptr)) misses << QStringLiteral("isselected");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("these accessibility interfaces are Qt 6 only"));
        return false;
#endif
    });

    r.check("gui/child-window-event", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        // The QWindow counterpart of QChildEvent, added in Qt 6.7. It carries a
        // window pointer and nothing else, and the event does not own it - so a
        // null child is a legal event to construct and is what a check with no
        // display can make.
        QChildWindowEvent added(QEvent::ChildWindowAdded, nullptr);
        QChildWindowEvent removed(QEvent::ChildWindowRemoved, nullptr);
        QEvent *asEvent = &added;

        QStringList misses;
        if (added.type() != QEvent::ChildWindowAdded) misses << QStringLiteral("added-type");
        if (removed.type() != QEvent::ChildWindowRemoved) misses << QStringLiteral("removed-type");
        if (added.child() != nullptr) misses << QStringLiteral("child");
        if (asEvent->type() != QEvent::ChildWindowAdded) misses << QStringLiteral("as-event");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QChildWindowEvent is Qt 6 only"));
        return false;
#endif
    });

    r.check("gui/session-manager", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
#if QT_CONFIG(sessionmanager)
        // QSessionManager has a private constructor (QGuiApplication is its friend),
        // so the signal signature is where callers meet it; connecting is the check.
        auto *app = qobject_cast<QGuiApplication *>(QCoreApplication::instance());
        if (!app) {
            d = QStringLiteral("no QGuiApplication instance");
            return false;
        }

        QObject context;
        int sawManager = 0;
        const QMetaObject::Connection saveState =
            QObject::connect(app, &QGuiApplication::saveStateRequest, &context,
                             [&sawManager](QSessionManager &manager) {
                                 Q_UNUSED(manager);
                                 ++sawManager;
                             });
        const QMetaObject::Connection commitData =
            QObject::connect(app, &QGuiApplication::commitDataRequest, &context,
                             [&sawManager](QSessionManager &manager) {
                                 Q_UNUSED(manager);
                                 ++sawManager;
                             });

        // Nothing here is session-restored: the suite is started by hand.
        const bool restored = app->isSessionRestored();

        // Both are read before disconnecting, because disconnecting is what
        // makes a QMetaObject::Connection test false - testing afterwards asks
        // whether the disconnect worked, not whether the connect did.
        const bool saveStateConnected = static_cast<bool>(saveState);
        const bool commitDataConnected = static_cast<bool>(commitData);

        QObject::disconnect(saveState);
        QObject::disconnect(commitData);

        QStringList misses;
        if (!saveStateConnected) misses << QStringLiteral("savestate-connect");
        if (!commitDataConnected) misses << QStringLiteral("commitdata-connect");
        if (restored) misses << QStringLiteral("restored");
        if (sawManager != 0) misses << QStringLiteral("unexpected-request");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("this Qt is built without session management"));
        return false;
#endif
#else
        r.skip(d, QStringLiteral("QSessionManager is reached on Qt 6 here"));
        return false;
#endif
    });

    r.check("qml/managed-value", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        // QJSManagedValue keeps its engine with the value, which lets it offer
        // prototypes, property deletion and callability.
        QJSEngine engine;

        QJSManagedValue number(QJSValue(6), &engine);
        QJSManagedValue text(QStringLiteral("qt-smoke"), &engine);
        QJSManagedValue object(engine.newObject(), &engine);
        object.setProperty(QStringLiteral("answer"), QJSValue(42));

        QJSManagedValue callable = engine.toManagedValue(
            engine.evaluate(QStringLiteral("(function (x) { return x * 7; })")));
        const QJSValue called = callable.call({ QJSValue(6) });

        QStringList misses;
        if (!number.isNumber() || number.toNumber() != 6) misses << QStringLiteral("number");
        if (!text.isString() || text.toString() != QStringLiteral("qt-smoke"))
            misses << QStringLiteral("string");
        if (!object.isObject()) misses << QStringLiteral("object");
        if (object.property(QStringLiteral("answer")).toInt() != 42)
            misses << QStringLiteral("property");
        if (!object.hasProperty(QStringLiteral("answer"))) misses << QStringLiteral("hasproperty");
        if (!callable.isFunction()) misses << QStringLiteral("function");
        if (called.toInt() != 42) misses << QStringLiteral("call");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QJSManagedValue is Qt 6 only"));
        return false;
#endif
    });
}
