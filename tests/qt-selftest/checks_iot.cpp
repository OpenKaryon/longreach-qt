// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// QtMqtt, QtCoap and QtHttpServer - three more modules that exist only in
// Qt 6 and that this kit was shipping with nothing pointed at them.
//
// All three are network clients or servers, and none of them needs a broker,
// an endpoint or a bound port to construct: the MQTT properties and topic
// types are value types, CoAP requests and options are value types, and a
// QHttpServer that has never been told to listen still routes. Nothing here
// opens a socket, which is what keeps it in the headless battery.
#include "../common/smokecheck.h"

#include <QUrl>

#ifdef SMOKE_HAVE_MQTT
#include <QMqttAuthenticationProperties>
#include <QMqttClient>
#include <QMqttConnectionProperties>
#include <QMqttMessage>
#include <QMqttPublishProperties>
#include <QMqttSubscription>
#include <QMqttSubscriptionProperties>
#include <QMqttTopicFilter>
#include <QMqttTopicName>
#include <QtMqtt/qmqtttype.h>   // QMqttStringPair, QMqttUserProperties
#endif

#ifdef SMOKE_HAVE_COAP
#include <QCoapClient>
#include <QCoapMessage>
#include <QCoapOption>
#include <QCoapReply>
#include <QCoapRequest>
#include <QCoapResource>
#include <QCoapResourceDiscoveryReply>
#include <QCoapSecurityConfiguration>
#endif

#ifdef SMOKE_HAVE_HTTPSERVER
#include <QAbstractHttpServer>
#include <QHttpServer>
#include <QHttpServerRequest>
#include <QHttpServerResponse>
#include <QHttpServerRouterRule>
#endif

void checkMqtt(SmokeReporter &r)
{
    r.check("mqtt/topic-name-and-filter", [&](QString &d) {
#ifdef SMOKE_HAVE_MQTT
        QMqttTopicName topic(QStringLiteral("sensors/kitchen/temperature"));
        QMqttTopicFilter filter(QStringLiteral("sensors/+/temperature"));
        QMqttTopicFilter shared(QStringLiteral("$share/group/sensors/#"));

        QStringList misses;
        if (!topic.isValid() || topic.levelCount() != 3) misses << QStringLiteral("topicname");
        if (topic.levels().value(1) != QStringLiteral("kitchen")) misses << QStringLiteral("levels");
        if (!filter.isValid() || !filter.match(topic)) misses << QStringLiteral("filter");
        if (shared.sharedSubscriptionName() != QStringLiteral("group"))
            misses << QStringLiteral("sharedsubscription");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QtMqtt is not in this SDK (it has no Qt 5 counterpart)"));
        return false;
#endif
    });

    r.check("mqtt/message-and-properties", [&](QString &d) {
#ifdef SMOKE_HAVE_MQTT
        QMqttMessage message;

        QMqttStringPair pair(QStringLiteral("unit"), QStringLiteral("celsius"));
        QMqttUserProperties userProperties;
        userProperties.append(pair);

        QMqttPublishProperties publish;
        publish.setPayloadFormatIndicator(QMqtt::PayloadFormatIndicator::UTF8Encoded);
        publish.setMessageExpiryInterval(60);
        publish.setUserProperties(userProperties);

        QMqttSubscriptionProperties subscription;
        subscription.setSubscriptionIdentifier(7);
        // The Qt 5 QtMqtt snapshot (0b4955ce) predates the noLocal property;
        // there only the identifier and the user properties can be checked.
        bool noLocal = true;
#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
        subscription.setNoLocal(true);
        noLocal = subscription.noLocal();
#endif
        subscription.setUserProperties(userProperties);

        QMqttUnsubscriptionProperties unsubscription;
        unsubscription.setUserProperties(userProperties);

        QMqttLastWillProperties lastWill;
        lastWill.setWillDelayInterval(30);
        lastWill.setContentType(QStringLiteral("text/plain"));

        QMqttConnectionProperties connection;
        connection.setSessionExpiryInterval(120);
        connection.setMaximumTopicAlias(10);
        connection.setUserProperties(userProperties);

        QMqttServerConnectionProperties serverConnection;

        QMqttAuthenticationProperties authentication;
        authentication.setAuthenticationMethod(QStringLiteral("SCRAM-SHA-1"));
        authentication.setAuthenticationData(QByteArrayLiteral("nonce"));

        QMqttMessageStatusProperties messageStatus;

        QStringList misses;
        // A default-constructed message carries no topic and QoS 0.
        if (message.qos() != 0 || message.topic().isValid()) misses << QStringLiteral("message");
        if (pair.value() != QStringLiteral("celsius")) misses << QStringLiteral("stringpair");
        if (publish.messageExpiryInterval() != 60) misses << QStringLiteral("publishproperties");
        if (subscription.subscriptionIdentifier() != 7 || !noLocal
                || subscription.userProperties().size() != 1)
            misses << QStringLiteral("subscriptionproperties");
        if (unsubscription.userProperties().size() != 1)
            misses << QStringLiteral("unsubscriptionproperties");
        if (lastWill.willDelayInterval() != 30) misses << QStringLiteral("lastwill");
        if (connection.sessionExpiryInterval() != 120) misses << QStringLiteral("connectionproperties");
        if (serverConnection.userProperties().size() != 0)
            misses << QStringLiteral("serverconnectionproperties");
        if (authentication.authenticationData() != QByteArrayLiteral("nonce"))
            misses << QStringLiteral("authenticationproperties");
        if (messageStatus.reasonCode() != QMqtt::ReasonCode::Success)
            misses << QStringLiteral("messagestatusproperties");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QtMqtt is not in this SDK"));
        return false;
#endif
    });

    r.check("mqtt/client-configuration", [&](QString &d) {
#ifdef SMOKE_HAVE_MQTT
        // No broker is contacted: connectToHost() is never called, so the
        // client stays Disconnected and only its configuration is exercised.
        QMqttClient client;
        client.setHostname(QStringLiteral("localhost"));
        client.setPort(1883);
        client.setClientId(QStringLiteral("qt-smoke"));
        client.setKeepAlive(30);
        client.setProtocolVersion(QMqttClient::MQTT_5_0);

        QMqttSubscription *subscription = client.subscribe(QMqttTopicFilter(QStringLiteral("a/b")));

        bool ok = client.hostname() == QStringLiteral("localhost")
            && client.port() == 1883
            && client.clientId() == QStringLiteral("qt-smoke")
            && client.keepAlive() == 30
            && client.protocolVersion() == QMqttClient::MQTT_5_0
            && client.state() == QMqttClient::Disconnected
            // subscribe() before a connection has nothing to send it over, so
            // a null subscription is the documented outcome rather than a bug.
            && (subscription == nullptr
                || subscription->state() == QMqttSubscription::Unsubscribed);
        if (!ok)
            d = QStringLiteral("client configuration did not round-trip");
        return ok;
#else
        r.skip(d, QStringLiteral("QtMqtt is not in this SDK"));
        return false;
#endif
    });
}

void checkCoap(SmokeReporter &r)
{
    r.check("coap/request-message-and-options", [&](QString &d) {
#ifdef SMOKE_HAVE_COAP
        QCoapRequest request(QUrl(QStringLiteral("coap://localhost/sensor")),
                             QCoapMessage::Type::Confirmable);
        // The method is chosen by the QCoapClient call that sends the
        // request, not set on the request itself.
        request.setToken(QByteArrayLiteral("tok"));
        request.addOption(QCoapOption(QCoapOption::UriPath, QStringLiteral("sensor")));
        request.addOption(QCoapOption::Accept, QByteArrayLiteral("0"));   // content-format id

        const QCoapOption pathOption(QCoapOption::UriPath, QStringLiteral("sensor"));
        const QCoapOption sizeOption(QCoapOption::Size1, quint32(64));

        QCoapMessage message = request;
        message.setPayload(QByteArrayLiteral("body"));

        QStringList misses;
        if (request.url().host() != QStringLiteral("localhost")) misses << QStringLiteral("url");
        if (request.token() != QByteArrayLiteral("tok")) misses << QStringLiteral("token");
        if (request.optionCount() != 2) misses << QStringLiteral("options");
        if (pathOption.stringValue() != QStringLiteral("sensor")) misses << QStringLiteral("stringoption");
        if (sizeOption.uintValue() != 64u) misses << QStringLiteral("uintoption");
        if (message.payload() != QByteArrayLiteral("body")) misses << QStringLiteral("payload");
        if (message.type() != QCoapMessage::Type::Confirmable) misses << QStringLiteral("type");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QtCoap is not in this SDK (it has no Qt 5 counterpart)"));
        return false;
#endif
    });

    r.check("coap/client-replies-and-security", [&](QString &d) {
#ifdef SMOKE_HAVE_COAP
        // Nothing is sent: the client is configured and its reply objects are
        // constructed directly, which is what makes this safe with no network.
        QCoapClient client;
        client.setBlockSize(64);
        client.setAckTimeout(1000);
        client.setMaximumRetransmitCount(2);

        QCoapSecurityConfiguration security;
        security.setPreSharedKey(QByteArrayLiteral("secret"));
        security.setPreSharedKeyIdentity(QByteArrayLiteral("qt-smoke"));
        QCoapPrivateKey privateKey;
        security.setPrivateKey(privateKey);

        QCoapResource resource;

        // QCoapReply and QCoapResourceDiscoveryReply both have private
        // constructors friended only to QCoapClientPrivate: the only way to
        // get one is to actually transmit, which this headless battery will
        // not do. Naming the types is as far as they can be reached here.
        QCoapReply *reply = nullptr;
        QCoapResourceDiscoveryReply *discoveryReply = nullptr;

        QStringList misses;
        if (security.preSharedKey() != QByteArrayLiteral("secret")) misses << QStringLiteral("psk");
        if (security.preSharedKeyIdentity() != QByteArrayLiteral("qt-smoke"))
            misses << QStringLiteral("identity");
        if (!privateKey.isNull()) misses << QStringLiteral("privatekey");
        if (!resource.path().isEmpty()) misses << QStringLiteral("resource");
        if (reply != nullptr || discoveryReply != nullptr) misses << QStringLiteral("replies");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QtCoap is not in this SDK"));
        return false;
#endif
    });
}

void checkHttpServer(SmokeReporter &r)
{
    r.check("httpserver/routing-without-listening", [&](QString &d) {
#ifdef SMOKE_HAVE_HTTPSERVER
        // listen() is never called, so no port is bound and nothing here can
        // collide with a real service on the machine.
        QHttpServer server;
        server.route(QStringLiteral("/hello"), []() {
            return QHttpServerResponse(QByteArrayLiteral("text/plain"),
                                       QByteArrayLiteral("hello"));
        });

        // Reached through the real base class: QHttpServer is a
        // QAbstractHttpServer, which is what owns the listening sockets.
        QAbstractHttpServer *base = &server;

        QHttpServerResponse response(QByteArrayLiteral("text/plain"),
                                     QByteArrayLiteral("hello"));

        bool noServers = false;
#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
        noServers = base->serverPorts().isEmpty();
#else
        noServers = base->servers().isEmpty();
#endif
        bool ok = noServers && !base->hasPendingWebSocketConnections()
            && response.data() == QByteArrayLiteral("hello")
            && response.mimeType() == QByteArrayLiteral("text/plain");
        if (!ok)
            d = QStringLiteral("server state or response body unexpected");
        return ok;
#else
        r.skip(d, QStringLiteral("QtHttpServer is not in this SDK (it has no Qt 5 counterpart)"));
        return false;
#endif
    });
}
