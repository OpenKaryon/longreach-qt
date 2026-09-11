// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// QtDBus. The kit builds it into the Linux and macOS SDKs and never built it
// for Windows, which is why this whole module had gone untested: the one
// platform the suite was verified on is the one platform without it.
//
// Nothing here needs a running bus. QDBusConnection::sessionBus() on a machine
// with no session bus hands back an invalid connection and says so through
// lastError() - that is the documented outcome, not a failure - and everything
// else in the module is either a value type or an interface meant to be
// subclassed. The one class that would listen on a socket, QDBusServer, is
// constructed through its address-less form, which does not.
#include "../common/smokecheck.h"

#ifdef SMOKE_HAVE_DBUS
#include <QDBusAbstractAdaptor>
#include <QDBusAbstractInterface>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusContext>
#include <QDBusError>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusObjectPath>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServer>
#include <QDBusServiceWatcher>
#include <QDBusSignature>
#include <QDBusUnixFileDescriptor>
#include <QDBusVariant>
#include <QDBusVirtualObject>

#include <QObject>
#include <QVariant>

namespace {

// The three extension points a D-Bus service implements: an adaptor to export
// an existing QObject, a virtual object to answer for a whole subtree, and
// QDBusContext to reach the message being handled from inside a slot.
class SmokeDBusAdaptor : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.qtproject.qtsmoke.Adaptor")
public:
    explicit SmokeDBusAdaptor(QObject *parent) : QDBusAbstractAdaptor(parent) {}

public Q_SLOTS:
    QString echo(const QString &text) const { return text; }
};

class SmokeVirtualObject : public QDBusVirtualObject
{
public:
    QString introspect(const QString &path) const override
    {
        return QStringLiteral("<node name=\"%1\"/>").arg(path);
    }
    bool handleMessage(const QDBusMessage &, const QDBusConnection &) override { return false; }
};

class SmokeContextObject : public QObject, protected QDBusContext
{
public:
    // calledFromDBus() is the whole point of QDBusContext, and it is false
    // outside a call - which is exactly the state this check is in.
    bool insideCall() { return calledFromDBus(); }
};

} // namespace
#endif

void checkDBusValueTypes(SmokeReporter &r)
{
    r.check("dbus/value-types-and-message", [&](QString &d) {
#ifdef SMOKE_HAVE_DBUS
        const QDBusObjectPath path(QStringLiteral("/org/qtproject/qtsmoke"));
        const QDBusSignature signature(QStringLiteral("a{sv}"));
        const QDBusVariant variant(QVariant(42));
        QDBusUnixFileDescriptor fd;   // null until given a real descriptor

        QDBusMessage call = QDBusMessage::createMethodCall(
            QStringLiteral("org.qtproject.qtsmoke"), path.path(),
            QStringLiteral("org.qtproject.qtsmoke.Adaptor"), QStringLiteral("echo"));
        call << QStringLiteral("hello");

        const QDBusMessage reply = call.createReply(QVariant(QStringLiteral("hello")));
        const QDBusMessage failure = call.createErrorReply(
            QDBusError::errorString(QDBusError::ServiceUnknown),
            QStringLiteral("no such service"));
        const QDBusError error(failure);

        QDBusMessage signal = QDBusMessage::createSignal(
            path.path(), QStringLiteral("org.qtproject.qtsmoke.Adaptor"),
            QStringLiteral("changed"));

        QStringList misses;
        if (path.path() != QStringLiteral("/org/qtproject/qtsmoke")) misses << QStringLiteral("objectpath");
        if (signature.signature() != QStringLiteral("a{sv}")) misses << QStringLiteral("signature");
        if (variant.variant().toInt() != 42) misses << QStringLiteral("variant");
        if (fd.isValid()) misses << QStringLiteral("unixfd");
        if (call.type() != QDBusMessage::MethodCallMessage) misses << QStringLiteral("methodcall");
        if (call.arguments().value(0).toString() != QStringLiteral("hello"))
            misses << QStringLiteral("arguments");
        if (reply.type() != QDBusMessage::ReplyMessage) misses << QStringLiteral("reply");
        if (error.type() != QDBusError::ServiceUnknown) misses << QStringLiteral("error");
        if (signal.type() != QDBusMessage::SignalMessage) misses << QStringLiteral("signal");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QtDBus is not in this SDK"));
        return false;
#endif
    });

    r.check("dbus/argument-marshalling", [&](QString &d) {
#ifdef SMOKE_HAVE_DBUS
        // QDBusArgument is how a custom type crosses the bus. Streaming into a
        // default-constructed one is the marshalling half; the demarshalling
        // half needs a message that came off a real connection, so only the
        // metatype registry is exercised for it.
        QDBusArgument argument;
        argument.beginStructure();
        argument << QStringLiteral("name") << 7;
        argument.endStructure();

#if QT_VERSION_MAJOR < 6
        const int stringType = QDBusMetaType::signatureToType("s");
        const char *intSignature = QDBusMetaType::typeToSignature(QMetaType::Int);
#else
        // Qt 6 renamed signatureToType(const char*) -> int to
        // signatureToMetaType(const char*) -> QMetaType.
        const int stringType = QDBusMetaType::signatureToMetaType("s").id();
        const char *intSignature = QDBusMetaType::typeToSignature(QMetaType(QMetaType::Int));
#endif

        QStringList misses;
        if (argument.currentType() != QDBusArgument::UnknownType)
            misses << QStringLiteral("argument-state");
        if (stringType != QMetaType::QString) misses << QStringLiteral("signaturetotype");
        if (!intSignature || QByteArray(intSignature) != QByteArrayLiteral("i"))
            misses << QStringLiteral("typetosignature");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QtDBus is not in this SDK"));
        return false;
#endif
    });

    r.check("dbus/connection-and-interfaces", [&](QString &d) {
#ifdef SMOKE_HAVE_DBUS
        // No bus is required to exist. An unconnected QDBusConnection is a
        // valid object that reports why it is not usable.
        QDBusConnection session = QDBusConnection::sessionBus();
        QDBusConnectionInterface *busInterface = session.interface();

        QDBusInterface remote(QStringLiteral("org.qtproject.qtsmoke"),
                              QStringLiteral("/org/qtproject/qtsmoke"),
                              QStringLiteral("org.qtproject.qtsmoke.Adaptor"),
                              session);
        // Reached through the real bases: every generated D-Bus proxy derives
        // from QDBusAbstractInterface, which derives from the moc helper base.
        QDBusAbstractInterface *interfaceBase = &remote;
        QDBusAbstractInterfaceBase *mocBase = &remote;

        QDBusServiceWatcher watcher;
        watcher.setConnection(session);
        watcher.addWatchedService(QStringLiteral("org.qtproject.qtsmoke"));
        watcher.setWatchMode(QDBusServiceWatcher::WatchForOwnerChange);

        // The address-less form does not listen on anything.
        QDBusServer server;

        QObject exported;
        SmokeDBusAdaptor adaptor(&exported);
        QDBusAbstractAdaptor *adaptorBase = &adaptor;
        SmokeVirtualObject virtualObject;
        QDBusVirtualObject *virtualBase = &virtualObject;
        SmokeContextObject context;

        QStringList misses;
        if (session.name() != QDBusConnection::sessionBus().name())
            misses << QStringLiteral("connection-name");
        if (!interfaceBase->interface().endsWith(QStringLiteral("Adaptor")))
            misses << QStringLiteral("interface");
        if (mocBase == nullptr) misses << QStringLiteral("interfacebase");
        if (!watcher.watchedServices().contains(QStringLiteral("org.qtproject.qtsmoke")))
            misses << QStringLiteral("servicewatcher");
        if (adaptorBase->parent() != &exported) misses << QStringLiteral("adaptor");
        if (!virtualBase->introspect(QStringLiteral("/x")).contains(QStringLiteral("/x")))
            misses << QStringLiteral("virtualobject");
        if (context.insideCall()) misses << QStringLiteral("context");
        // busInterface is null without a bus, and server.isConnected() is
        // false without an address - both are the environment, not the API.
        Q_UNUSED(busInterface);
        Q_UNUSED(server);
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        if (misses.isEmpty() && !session.isConnected()) {
            r.skip(d, QStringLiteral("no D-Bus session bus; the API half still ran"));
            return false;
        }
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QtDBus is not in this SDK"));
        return false;
#endif
    });

    r.check("dbus/pending-call-and-reply", [&](QString &d) {
#ifdef SMOKE_HAVE_DBUS
        QDBusConnection session = QDBusConnection::sessionBus();
        QDBusMessage call = QDBusMessage::createMethodCall(
            QStringLiteral("org.freedesktop.DBus"), QStringLiteral("/"),
            QStringLiteral("org.freedesktop.DBus"), QStringLiteral("ListNames"));

        // Without a bus the call usually returns finished and in error, but an
        // autolaunched session bus can leave it pending: always wait, then judge by
        // the reply.
        const bool connected = session.isConnected();
        QDBusPendingCall pending = session.asyncCall(call);
        pending.waitForFinished();
        QDBusPendingCallWatcher watcher(pending);
        QDBusPendingReply<QStringList> reply(pending);
        // Reached through the real base every QDBusPendingReply<> shares; it
        // was renamed from ...Data to ...Base in Qt 6.
#if QT_VERSION_MAJOR < 6
        QDBusPendingReplyData *replyBase = &reply;
#else
        QDBusPendingReplyBase *replyBase = &reply;
#endif

        QStringList misses;
        if (!pending.isFinished()) misses << QStringLiteral("pendingcall");
        if (watcher.isFinished() != pending.isFinished()) misses << QStringLiteral("watcher");
        if (!replyBase->isFinished()) misses << QStringLiteral("replybase");
        if (!reply.isError() && !reply.value().contains(QStringLiteral("org.freedesktop.DBus")))
            misses << QStringLiteral("ListNames reply without the bus daemon");
        if (connected && reply.isError())
            misses << QStringLiteral("connected, but ListNames failed");
        if (!misses.isEmpty() || reply.isError())
            d = misses.join(QLatin1Char(','));
        if (reply.isError())
            d += QStringLiteral("%1connected=%2 error=%3")
                     .arg(d.isEmpty() ? QString() : QStringLiteral(" "),
                          connected ? QStringLiteral("yes") : QStringLiteral("no"),
                          reply.error().name());
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QtDBus is not in this SDK"));
        return false;
#endif
    });
}

#ifdef SMOKE_HAVE_DBUS
#include "checks_dbus.moc"
#endif
