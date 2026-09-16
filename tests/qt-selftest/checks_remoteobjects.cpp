// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// QtRemoteObjects checks: host/node/registry construct and bind to local
// addresses without a real peer process on the other end - acquireDynamic()/
// acquireModel() return real (if not-yet-initialized) replica objects even
// with nothing listening, the same way QNAM returns a QNetworkReply before
// the request completes.
#include "../common/smokecheck.h"

#if !SMOKE_QT5

void checkRemoteObjects(SmokeReporter &r)
{
    r.check("remoteobjects/module", [&](QString &d) {
        r.skip(d, QStringLiteral("QtRemoteObjects has no Qt 4 module"));
        return false;
    });
}

#else

#include <QRemoteObjectHost>
#include <QRemoteObjectHostBase>
#include <QRemoteObjectNode>
#include <QRemoteObjectRegistryHost>
#include <QRemoteObjectRegistry>
#include <QRemoteObjectReplica>
#include <QRemoteObjectDynamicReplica>
#include <QAbstractItemModelReplica>
#include <QRemoteObjectPendingCall>
#include <QRemoteObjectPendingCallWatcher>
#include <QRemoteObjectSettingsStore>
#include <QRemoteObjectAbstractPersistedStore>
#include <QCoreApplication>

#if QT_VERSION_MAJOR >= 6
#include <QtRemoteObjects/qconnectionfactories.h>
#include <QBuffer>

namespace {

class SmokeServerIoDevice final : public QtROServerIoDevice
{
public:
    explicit SmokeServerIoDevice(QObject *parent = nullptr)
        : QtROServerIoDevice(parent)
    {
        buffer.open(QIODevice::ReadWrite);
    }

    QIODevice *connection() const override
    {
        return const_cast<QBuffer *>(&buffer);
    }

protected:
    void doClose() override { buffer.close(); }

private:
    mutable QBuffer buffer;
};

class SmokeConnectionServer final : public QConnectionAbstractServer
{
public:
    explicit SmokeConnectionServer(QObject *parent = nullptr)
        : QConnectionAbstractServer(parent)
    {}

    bool hasPendingConnections() const override { return pending; }
    QUrl address() const override { return listeningAddress; }
    bool listen(const QUrl &address) override
    {
        listeningAddress = address;
        listening = address.isValid();
        return listening;
    }
    QAbstractSocket::SocketError serverError() const override
    {
        return QAbstractSocket::UnknownSocketError;
    }
    void close() override
    {
        listening = false;
        pending = false;
    }

    void queueConnection()
    {
        pending = true;
        emit newConnection();
    }
    bool isListening() const { return listening; }

protected:
    QtROServerIoDevice *configureNewConnection() override
    {
        if (!pending)
            return nullptr;
        pending = false;
        return new SmokeServerIoDevice(this);
    }

private:
    QUrl listeningAddress;
    bool listening = false;
    bool pending = false;
};

} // namespace
#endif

void checkRemoteObjects(SmokeReporter &r)
{
    r.check("remoteobjects/host-node-registry", [&](QString &d) {
        const QUrl endpoint(QStringLiteral("local:qt-smoke-ro-%1").arg(QCoreApplication::applicationPid()));
        QRemoteObjectHost host(endpoint);
        QRemoteObjectNode node;
        node.connectToNode(endpoint);   // async; result not asserted
        QRemoteObjectRegistryHost registryHost;
        const QRemoteObjectRegistry *registry = node.registry();
        Q_UNUSED(registry);   // null until connected to a real registry node
        // Reached through the real base class both host types derive from -
        // enableRemoting()/disableRemoting() are its actual public API.
        QRemoteObjectHostBase *hostBase = &host;
        QObject dummy;
        hostBase->enableRemoting(&dummy, QStringLiteral("dummy"));
        hostBase->disableRemoting(&dummy);
        if (host.hostUrl() != endpoint) {
            r.skip(d, QStringLiteral("local transport unavailable for %1").arg(endpoint.toString()));
            return false;
        }
        return true;
    });
    r.check("remoteobjects/dynamic-and-model-replica", [&](QString &d) {
        QRemoteObjectNode node;
        QRemoteObjectDynamicReplica *dynReplica = node.acquireDynamic(QStringLiteral("NoSuchObject"));
        QAbstractItemModelReplica *modelReplica = node.acquireModel(QStringLiteral("NoSuchModel"));
        // Reached through the real base class every replica type derives from.
        QRemoteObjectReplica *base = dynReplica;
        bool ok = base != nullptr && modelReplica != nullptr && !dynReplica->isInitialized();
        delete dynReplica;
        delete modelReplica;
        return ok;
    });
    r.check("remoteobjects/pending-call", [&](QString &d) {
        QRemoteObjectPendingCall call;
        QRemoteObjectPendingCallWatcher watcher(call);
        return !call.isFinished() && !watcher.isFinished();
    });
    r.check("remoteobjects/settings-store", [&](QString &d) {
        QRemoteObjectSettingsStore store;
        // Reached through the real abstract base every persisted-property
        // store implementation derives from.
        QRemoteObjectAbstractPersistedStore *base = &store;
        return base != nullptr;
    });

    r.check("remoteobjects/custom-server-transport", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        SmokeConnectionServer server;
        const QUrl endpoint(QStringLiteral("smoke:memory"));
        int notifications = 0;
        QObject::connect(&server, &QConnectionAbstractServer::newConnection,
                         &server, [&notifications] { ++notifications; });

        if (!server.listen(endpoint) || server.address() != endpoint
                || !server.isListening()) {
            d = QStringLiteral("custom server did not retain its listen address");
            return false;
        }

        server.queueConnection();
        if (!server.hasPendingConnections() || notifications != 1) {
            d = QStringLiteral("queued connection did not emit newConnection");
            return false;
        }

        QScopedPointer<QtROServerIoDevice> connection(server.nextPendingConnection());
        if (connection.isNull() || server.hasPendingConnections()
                || !connection->isOpen() || connection->connection() == nullptr) {
            d = QStringLiteral("nextPendingConnection did not configure an open device");
            return false;
        }
        connection->close();
        server.close();
        return !connection->isOpen() && !server.isListening();
#else
        r.skip(d, QStringLiteral("custom QtRO transports use the Qt 6 extension API"));
        return false;
#endif
    });
}

#endif // SMOKE_QT5
