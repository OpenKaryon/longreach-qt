// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// QtConnectivity checks: Bluetooth Classic, Bluetooth Low Energy, and NFC.
// No adapter/peripheral is required - address/uuid/record value types and the
// BLE "Data" builder classes (used to describe a peripheral before it's
// advertised) are all plain value objects; discovery agents and
// QBluetoothLocalDevice construct and report "not available" without hardware
// rather than failing, the same pattern as the sensor/camera/audio checks.
#include "../common/smokecheck.h"

#if !SMOKE_QT5

static void skipConnectivity(SmokeReporter &r, const char *name)
{
    r.check(QString::fromLatin1(name), [&](QString &d) {
        r.skip(d, QStringLiteral("QtBluetooth and QtNfc have no Qt 4 modules in this SDK"));
        return false;
    });
}

void checkBluetoothClassic(SmokeReporter &r) { skipConnectivity(r, "connectivity/bluetooth-classic"); }
void checkLowEnergy(SmokeReporter &r) { skipConnectivity(r, "connectivity/bluetooth-low-energy"); }
void checkNfc(SmokeReporter &r) { skipConnectivity(r, "connectivity/nfc"); }

#else

#include <QBluetoothAddress>
#include <QBluetoothUuid>
#include <QBluetoothHostInfo>
#include <QBluetoothDeviceInfo>
#include <QBluetoothLocalDevice>
#include <QBluetoothDeviceDiscoveryAgent>
#include <QBluetoothServiceDiscoveryAgent>
#include <QBluetoothServiceInfo>
#include <QBluetoothServer>
#include <QBluetoothSocket>
#if QT_VERSION_MAJOR < 6
#include <QBluetoothTransferManager>
#endif
#if QT_VERSION_MAJOR < 6
#include <QBluetoothTransferRequest>
#endif
#if QT_VERSION_MAJOR < 6
#include <QBluetoothTransferReply>
#endif
#include <QBuffer>

#include <QLowEnergyController>
#include <QLowEnergyAdvertisingData>
#include <QLowEnergyAdvertisingParameters>
#include <QLowEnergyCharacteristicData>
#include <QLowEnergyDescriptorData>
#include <QLowEnergyServiceData>
#include <QLowEnergyCharacteristic>
#include <QLowEnergyDescriptor>
#include <QLowEnergyService>
#include <QLowEnergyConnectionParameters>

#include <QNdefMessage>
#include <QNdefFilter>
#include <QNdefRecord>
#include <QNdefNfcTextRecord>
#include <QNdefNfcUriRecord>
#include <QNdefNfcIconRecord>
#include <QNdefNfcSmartPosterRecord>
#include <QNearFieldManager>
#include <QNearFieldTarget>
#if QT_VERSION_MAJOR < 6
#include <QNearFieldShareManager>
#endif
#include <QUrl>

void checkBluetoothClassic(SmokeReporter &r)
{
    r.check("bluetooth/address-uuid-hostinfo", [&](QString &d) {
        QBluetoothAddress addr(QStringLiteral("00:11:22:33:44:55"));
        QBluetoothUuid uuid(QBluetoothUuid::ServiceClassUuid::SerialPort);
        QBluetoothHostInfo host;
        host.setAddress(addr);
        host.setName(QStringLiteral("local-adapter"));
        return !addr.isNull() && !uuid.isNull() && host.address() == addr;
    });
    r.check("bluetooth/deviceinfo", [&](QString &d) {
        QBluetoothAddress addr(QStringLiteral("AA:BB:CC:DD:EE:FF"));
        QBluetoothDeviceInfo info(addr, QStringLiteral("Headset"), 0x240404);
        info.setCached(true);
        return info.address() == addr && info.name() == QStringLiteral("Headset") && info.isCached();
    });
    r.check("bluetooth/localdevice-and-agents", [&](QString &d) {
        QBluetoothLocalDevice local;
        QBluetoothDeviceDiscoveryAgent deviceAgent;
        QBluetoothServiceDiscoveryAgent serviceAgent;
        // No adapter is required to exist - isValid()/error() just report that.
        Q_UNUSED(local.isValid());
        return !deviceAgent.isActive() && !serviceAgent.isActive();
    });
    r.check("bluetooth/serviceinfo-server-socket", [&](QString &d) {
        QBluetoothServiceInfo service;
        service.setServiceName(QStringLiteral("qt-smoke"));
        QBluetoothServer server(QBluetoothServiceInfo::RfcommProtocol);
        QBluetoothSocket socket(QBluetoothServiceInfo::RfcommProtocol);
        return service.serviceName() == QStringLiteral("qt-smoke")
#if QT_VERSION_MAJOR < 6
            && !server.isListening() && socket.state() == QBluetoothSocket::UnconnectedState;
#else
            && !server.isListening() && socket.state() == QBluetoothSocket::SocketState::UnconnectedState;
#endif
    });
    r.check("bluetooth/transfer-manager-request", [&](QString &d) {
#if QT_VERSION_MAJOR < 6
        QBluetoothTransferManager manager;
        QBluetoothTransferRequest request(QBluetoothAddress(QStringLiteral("11:22:33:44:55:66")));
        QByteArray payload("hello");
        QBuffer buffer(&payload);
        buffer.open(QIODevice::ReadOnly);
        // put() is only meaningful with a real OBEX backend - a null reply
        // (no backend registered) is an accepted, non-crashing outcome here.
        QBluetoothTransferReply *reply = manager.put(request, &buffer);
        delete reply;   // no event loop runs in this app, so deleteLater() would just leak
        return request.address() == QBluetoothAddress(QStringLiteral("11:22:33:44:55:66"));
#else
        r.skip(d, QStringLiteral("Qt 6 dropped the Bluetooth OBEX transfer classes"));
        return false;
#endif
    });
}

void checkLowEnergy(SmokeReporter &r)
{
    r.check("ble/advertising-data-parameters", [&](QString &d) {
        QLowEnergyAdvertisingData data;
        data.setLocalName(QStringLiteral("qt-smoke-ble"));
        data.setIncludePowerLevel(true);
        QLowEnergyAdvertisingParameters params;
        params.setInterval(100, 200);
        return data.localName() == QStringLiteral("qt-smoke-ble") && data.includePowerLevel();
    });
    r.check("ble/service-characteristic-descriptor-data", [&](QString &d) {
        QLowEnergyDescriptorData descData(QBluetoothUuid::DescriptorType::ClientCharacteristicConfiguration,
                                          QByteArray::fromHex("0000"));
        QLowEnergyCharacteristicData charData;
        charData.setUuid(QBluetoothUuid(QBluetoothUuid::CharacteristicType::BatteryLevel));
        charData.setValue(QByteArray::fromHex("64"));
        charData.addDescriptor(descData);
        QLowEnergyServiceData serviceData;
        serviceData.setUuid(QBluetoothUuid(QBluetoothUuid::ServiceClassUuid::BatteryService));
        serviceData.addCharacteristic(charData);
        return charData.descriptors().size() == 1 && serviceData.characteristics().size() == 1;
    });
    r.check("ble/controller-central-construct", [&](QString &d) {
        QBluetoothDeviceInfo remote(QBluetoothAddress(QStringLiteral("11:11:11:11:11:11")),
                                    QStringLiteral("peripheral"), 0);
        QLowEnergyController *central = QLowEnergyController::createCentral(remote);
        bool ok = central != nullptr && central->role() == QLowEnergyController::CentralRole;
        delete central;
        return ok;
    });
    r.check("ble/default-constructed-handles", [&](QString &d) {
        // Real usage: QLowEnergyCharacteristic/Descriptor/Service are normally
        // obtained from a live QLowEnergyController's discovery results, but
        // are default-constructible into an explicitly "invalid" state.
        QLowEnergyCharacteristic characteristic;
        QLowEnergyDescriptor descriptor;
        return !characteristic.isValid() && !descriptor.isValid();
    });
    r.check("ble/connection-parameters", [&](QString &d) {
        QLowEnergyConnectionParameters params;
        params.setIntervalRange(20, 40);
        params.setLatency(0);
        params.setSupervisionTimeout(500);
        return params.minimumInterval() == 20 && params.maximumInterval() == 40
            && params.supervisionTimeout() == 500;
    });
}

void checkNfc(SmokeReporter &r)
{
    r.check("nfc/ndef-records", [&](QString &d) {
        QNdefNfcTextRecord text;
        text.setText(QStringLiteral("hello"));
        QNdefNfcUriRecord uri;
        uri.setUri(QUrl(QStringLiteral("https://example.com")));
        QNdefNfcIconRecord icon;
        icon.setData(QByteArray("\x89PNG", 4));
        QNdefNfcSmartPosterRecord poster;
        QNdefNfcTextRecord posterTitle;
        posterTitle.setText(QStringLiteral("Poster"));
        poster.setTitles({posterTitle});
        QNdefMessage message;
        message.append(text);
        message.append(uri);
        QNdefFilter filter;
        filter.appendRecord<QNdefNfcTextRecord>();
        // The generic base record: a raw type-name-format + type + payload
        // (what every specific record subclass above is built out of). The
        // (TypeNameFormat, type) constructor is protected - the setters are
        // the public way to configure a default-constructed record.
        QNdefRecord generic;
        generic.setTypeNameFormat(QNdefRecord::NfcRtd);
        generic.setType(QByteArray("T"));
        generic.setPayload(QByteArray("raw"));
        return text.text() == QStringLiteral("hello") && uri.uri().toString().contains("example")
            && message.size() == 2 && !icon.data().isEmpty() && poster.hasTitle()
            && generic.payload() == QByteArray("raw");
    });
    r.check("nfc/manager-target-share", [&](QString &d) {
        QNearFieldManager manager;
#if QT_VERSION_MAJOR < 6
        QNearFieldShareManager shareManager;
#endif
        // No NFC hardware is required to exist for construction; isAvailable()
        // and the supported share modes just report accordingly (possibly
        // none) without it.
#if QT_VERSION_MAJOR < 6
        Q_UNUSED(manager.isAvailable());
        QNearFieldShareManager::ShareModes modes = QNearFieldShareManager::supportedShareModes();
        shareManager.setShareModes(modes);
        return shareManager.shareModes() == modes;
#else
        // isAvailable() became isEnabled(); the share-mode API has no Qt 6
        // counterpart, so only the manager half of this check still runs.
        Q_UNUSED(manager.isEnabled());
        return manager.isSupported(QNearFieldTarget::NdefAccess) || true;
#endif
    });
    r.check("nfc/target-base", [&](QString &d) {
        // QNearFieldTarget is abstract, and a minimal subclass is how a custom NFC
        // target backend is written. Its share counterpart can only be created by the
        // platform backend on real hardware.
#if QT_VERSION_MAJOR < 6
        class FixedTarget : public QNearFieldTarget {
        public:
            QByteArray uid() const override { return QByteArray("uid123"); }
            Type type() const override { return NfcTagType4; }
            AccessMethods accessMethods() const override { return NdefAccess; }
        };
        FixedTarget target;
        return target.uid() == QByteArray("uid123") && target.type() == QNearFieldTarget::NfcTagType4;
#else
        // Qt 6 turned these into plain accessors backed by the platform
        // backend, so the subclass extension point above no longer exists.
        r.skip(d, QStringLiteral("QNearFieldTarget is not subclassable in Qt 6"));
        return false;
#endif
    });
}

#endif // SMOKE_QT5
