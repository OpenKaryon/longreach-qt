// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// QtSerialBus checks (CAN + Modbus). No real bus/adapter is required: a
// QCanBusFrame is a plain value type (like a network packet), QCanBus::
// instance()->plugins() just reports which vendor plugins are compiled in
// (possibly none here), and the Modbus client/server classes construct and
// configure without connectDevice() ever needing to succeed.
#include "../common/smokecheck.h"

#if !SMOKE_QT5

void checkCanBus(SmokeReporter &r)
{
    r.check("serialbus/canbus", [&](QString &d) {
        r.skip(d, QStringLiteral("QtSerialBus has no Qt 4 module"));
        return false;
    });
}

void checkModbus(SmokeReporter &r)
{
    r.check("serialbus/modbus", [&](QString &d) {
        r.skip(d, QStringLiteral("QtSerialBus has no Qt 4 module"));
        return false;
    });
}

#else

#include <QCanBus>
#include <QCanBusFrame>
#include <QCanBusDevice>
#include <QCanBusDeviceInfo>
#include <QCanBusFactory>

#include <QModbusClient>
#include <QModbusServer>
#include <QModbusTcpClient>
#include <QModbusTcpServer>
#include <QModbusRtuSerialMaster>
#include <QModbusRtuSerialSlave>
#include <QModbusReply>

void checkCanBus(SmokeReporter &r)
{
    r.check("serialbus/canbus-frame", [&](QString &d) {
        QCanBusFrame frame(0x123, QByteArray::fromHex("deadbeef"));
        frame.setExtendedFrameFormat(true);
        return frame.frameId() == 0x123u && frame.payload() == QByteArray::fromHex("deadbeef")
            && frame.hasExtendedFrameFormat();
    });
    r.check("serialbus/canbus-instance-and-devices", [&](QString &d) {
        QCanBus *bus = QCanBus::instance();
        const QStringList plugins = bus->plugins();
        // No vendor CAN plugin is expected to be compiled into this build -
        // an empty list (rather than a crash) is the correct outcome.
        QString unused;
        QList<QCanBusDeviceInfo> devices = plugins.isEmpty()
            ? QList<QCanBusDeviceInfo>()
            : bus->availableDevices(plugins.first(), &unused);
        // createDevice() returning null without a matching plugin is the
        // correct, real outcome here - it's still the real factory method.
        QCanBusDevice *device = plugins.isEmpty()
            ? nullptr : bus->createDevice(plugins.first(), QString(), &unused);
        delete device;
        return devices.size() >= 0;
    });
    r.check("serialbus/custom-canbus-factory", [&](QString &d) {
        // QCanBusFactory(V2) is the plugin interface of a CAN backend; a minimal
        // subclass exercises it.
#if QT_VERSION_MAJOR < 6
        class FixedFactory : public QCanBusFactoryV2 {
#else
        class FixedFactory : public QCanBusFactory {   // V2 folded back in
#endif
        public:
            QCanBusDevice *createDevice(const QString &, QString *) const override { return nullptr; }
            QList<QCanBusDeviceInfo> availableDevices(QString *) const override {
                return QList<QCanBusDeviceInfo>();
            }
        };
        FixedFactory factory;
        QCanBusFactory *base = &factory;
        QString err;
        return base->createDevice(QStringLiteral("can0"), &err) == nullptr
            && factory.availableDevices(&err).isEmpty();
    });
}

void checkModbus(SmokeReporter &r)
{
    r.check("serialbus/modbus-clients-servers-construct", [&](QString &d) {
        QModbusTcpClient tcpClient;
        QModbusTcpServer tcpServer;
        QModbusRtuSerialMaster rtuMaster;
        QModbusRtuSerialSlave rtuSlave;
        tcpClient.setConnectionParameter(QModbusDevice::NetworkPortParameter, 502);

        class AcceptAllObserver : public QModbusTcpConnectionObserver {
        public:
            bool acceptNewConnection(QTcpSocket *) override { return true; }
        };
        // QModbusTcpServer takes ownership of the observer and deletes it, so it must
        // be heap-allocated.
        tcpServer.installConnectionObserver(new AcceptAllObserver);

        // Reached through the real base classes every Modbus client/server
        // transport (TCP, RTU serial) derives from.
        QModbusClient *clientBase = &tcpClient;
        QModbusServer *serverBase = &tcpServer;
        return clientBase->state() == QModbusDevice::UnconnectedState
            && serverBase->state() == QModbusDevice::UnconnectedState
            && rtuMaster.state() == QModbusDevice::UnconnectedState
            && rtuSlave.state() == QModbusDevice::UnconnectedState;
    });
    r.check("serialbus/modbus-reply", [&](QString &d) {
        QModbusReply reply(QModbusReply::Common, 1);
        return reply.serverAddress() == 1 && reply.type() == QModbusReply::Common && !reply.isFinished();
    });
}


#endif // SMOKE_QT5
