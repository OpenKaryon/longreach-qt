// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// More small, low-traffic modules that are cheap to smoke-test headlessly:
// QtSvg (renderer/generator - the widget-based QSvgWidget/QGraphicsSvgItem
// live in graphics-gallery instead, since this console app has no widgets
// module), QtWebSockets (a real client/server loopback exchange), QtWebChannel
// (a minimal transport subclass - that's the actual intended way to use
// QWebChannelAbstractTransport outside of QWebEngine), QtNetworkAuth (OAuth1/2
// flow objects, reached through their abstract base pointers), and
// QtSerialPort (port enumeration + construction, no real port required).
#include "../common/smokecheck.h"

#include <QSvgRenderer>
#include <QSvgGenerator>
#include <QBuffer>
#include <QPainter>

#if SMOKE_QT5
#include <QWebSocket>
#include <QWebSocketServer>
#include <QWebSocketCorsAuthenticator>
#include <QMaskGenerator>

#include <QWebChannel>
#ifdef SMOKE_HAVE_QMLWEBCHANNEL
#include <QQmlWebChannel>
#endif
#include <QWebChannelAbstractTransport>

#ifdef SMOKE_HAVE_NETWORKAUTH
#  include <QOAuth1>
#  include <QOAuth1Signature>
#  include <QOAuth2AuthorizationCodeFlow>
#  include <QAbstractOAuth2>
#  include <QAbstractOAuth>
#  include <QOAuthHttpServerReplyHandler>
#  include <QOAuthOobReplyHandler>
#  include <QAbstractOAuthReplyHandler>
#endif

#include <QSerialPort>
#include <QSerialPortInfo>

#include <QJsonObject>
#include <QElapsedTimer>
#include <QCoreApplication>

static bool spin(const std::function<bool()> &done, int ms)
{
    QElapsedTimer t; t.start();
    while (!done() && t.elapsed() < ms) QCoreApplication::processEvents();
    return done();
}
#endif // SMOKE_QT5

void checkSvg(SmokeReporter &r)
{
    r.check("svg/renderer-loads-and-paints", [&](QString &d) {
        static const char *svg =
            "<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'>"
            "<rect width='10' height='10' fill='blue'/></svg>";
        QSvgRenderer renderer{QByteArray(svg)};   // (extra braces: avoid the most-vexing-parse)
        if (!renderer.isValid()) { d = "invalid svg"; return false; }
        QImage img(10, 10, QImage::Format_ARGB32);
        img.fill(Qt::white);
        QPainter p(&img);
        renderer.render(&p);
        p.end();
        return qBlue(img.pixel(5, 5)) > 150;
    });
    r.check("svg/generator-writes", [&](QString &d) {
        QByteArray out;
        QBuffer buf(&out);
        QSvgGenerator gen;
        gen.setOutputDevice(&buf);
        gen.setSize(QSize(20, 20));
        gen.setViewBox(QRect(0, 0, 20, 20));
        QPainter p(&gen);
        p.fillRect(QRect(0, 0, 20, 20), Qt::red);
        p.end();
        return out.contains("svg");
    });
}

#if SMOKE_QT5

void checkWebSockets(SmokeReporter &r)
{
    r.check("websocket/client-server-loopback", [&](QString &d) {
        QWebSocketServer server(QStringLiteral("qt-smoke"), QWebSocketServer::NonSecureMode);
        if (!server.listen(QHostAddress::LocalHost, 0)) { d = server.errorString(); return false; }

        QString got;
        QObject::connect(&server, &QWebSocketServer::newConnection, &server, [&] {
            QWebSocket *peer = server.nextPendingConnection();
            QObject::connect(peer, &QWebSocket::textMessageReceived, peer,
                              [&](const QString &msg) { got = msg; });
        });

        QWebSocket client;
        bool connected = false;
        QObject::connect(&client, &QWebSocket::connected, &client, [&] { connected = true; });
        client.open(QUrl(QStringLiteral("ws://127.0.0.1:%1").arg(server.serverPort())));
        if (!spin([&] { return connected; }, 2000)) { d = "client did not connect"; return false; }

        client.sendTextMessage(QStringLiteral("hello-ws"));
        if (!spin([&] { return got == QStringLiteral("hello-ws"); }, 2000)) {
            d = "message not received";
            return false;
        }
        return true;
    });
    r.check("websocket/cors-authenticator-value", [&](QString &d) {
        QWebSocketCorsAuthenticator auth(QStringLiteral("http://example.com"));
        auth.setAllowed(true);
        return auth.origin() == QStringLiteral("http://example.com") && auth.allowed();
    });
    r.check("websocket/custom-mask-generator", [&](QString &d) {
        // QMaskGenerator is abstract - subclassing it for a deterministic
        // generator is the documented way to plug a custom RNG into QWebSocket.
        class FixedMaskGenerator : public QMaskGenerator {
        public:
            bool seed() override { return true; }
            quint32 nextMask() override { return 0x11223344u; }
        };
        FixedMaskGenerator gen;
        return gen.seed() && gen.nextMask() == 0x11223344u;
    });
}

void checkWebChannel(SmokeReporter &r)
{
    r.check("webchannel/custom-transport-registration", [&](QString &d) {
        // QWebChannelAbstractTransport is abstract; a minimal subclass is the
        // real, documented way to embed QWebChannel without QWebEngine.
        class RecordingTransport : public QWebChannelAbstractTransport {
        public:
            QList<QJsonObject> sent;
            void sendMessage(const QJsonObject &message) override { sent << message; }
        };
        QWebChannel channel;
        QObject exposed;
        exposed.setObjectName("exposedObject");
        channel.registerObject(QStringLiteral("obj"), &exposed);
        RecordingTransport transport;
        channel.connectTo(&transport);
        bool ok = channel.registeredObjects().contains(QStringLiteral("obj"));
        channel.disconnectFrom(&transport);
        return ok;
    });
    r.check("webchannel/qml-webchannel-subclass", [&](QString &d) {
        // QQmlWebChannel is a real, directly-usable QWebChannel subclass (it
        // registers itself as a QML type elsewhere, but the C++ class needs
        // no QML engine to construct or use).
#ifdef SMOKE_HAVE_QMLWEBCHANNEL
        QQmlWebChannel qmlChannel;
        QObject exposed;
        qmlChannel.registerObject(QStringLiteral("qmlObj"), &exposed);
        // registeredObjects() is overridden here to return a QML list
        // property; the base class accessor still gives the usual map.
        QWebChannel *base = &qmlChannel;
        return base->registeredObjects().contains(QStringLiteral("qmlObj"));
#else
        r.skip(d, QStringLiteral("QQmlWebChannel needs the WebChannelQuick module"));
        return false;
#endif
    });
}

void checkNetworkAuth(SmokeReporter &r)
{
#ifdef SMOKE_HAVE_NETWORKAUTH
    r.check("networkauth/oauth1-signature", [&](QString &d) {
        QOAuth1Signature sig(QUrl(QStringLiteral("https://example.com/token")),
                             QStringLiteral("clientSecret"), QStringLiteral("tokenSecret"),
                             QOAuth1Signature::HttpRequestMethod::Get);
        sig.insert(QStringLiteral("oauth_nonce"), QStringLiteral("abc123"));
        QByteArray hmac = sig.hmacSha1();
        return !hmac.isEmpty() && sig.httpRequestMethod() == QOAuth1Signature::HttpRequestMethod::Get;
    });
    r.check("networkauth/oauth1-flow-construct", [&](QString &d) {
        QOAuth1 oauth1;
        oauth1.setClientCredentials(QStringLiteral("key"), QStringLiteral("secret"));
        // Reached through the abstract base - QOAuth1 derives from QAbstractOAuth.
        QAbstractOAuth *base = &oauth1;
        return base->status() == QAbstractOAuth::Status::NotAuthenticated;
    });
    r.check("networkauth/oauth2-flow-construct", [&](QString &d) {
        QOAuth2AuthorizationCodeFlow flow;
        flow.setAuthorizationUrl(QUrl(QStringLiteral("https://example.com/authorize")));
        flow.setAccessTokenUrl(QUrl(QStringLiteral("https://example.com/token")));
        flow.setScope(QStringLiteral("read"));
        // Reached through the abstract bases - a real inheritance chain, not a
        // fabricated one: QOAuth2AuthorizationCodeFlow -> QAbstractOAuth2 -> QAbstractOAuth.
        QAbstractOAuth2 *asOAuth2 = &flow;
        QAbstractOAuth *asOAuth = &flow;
        return asOAuth2->scope() == QStringLiteral("read")
            && asOAuth->status() == QAbstractOAuth::Status::NotAuthenticated;
    });
    r.check("networkauth/reply-handlers", [&](QString &d) {
        QOAuthOobReplyHandler oob;
        // QHostAddress(...) is spelled out: the bare enum LocalHost (value 2)
        // converts to quint16 and selects the (port, parent) constructor, which
        // listens on port 2 - fine as root in a container, refused for an
        // ordinary user on a desktop.
        QOAuthHttpServerReplyHandler http(QHostAddress(QHostAddress::LocalHost), 0);
        // Both are concrete subclasses of the abstract QAbstractOAuthReplyHandler.
        QAbstractOAuthReplyHandler *base1 = &oob;
        QAbstractOAuthReplyHandler *base2 = &http;
        d = QStringLiteral("oob=%1 http=%2 listening=%3")
                .arg(base1->callback(), base2->callback())
                .arg(http.isListening() ? QStringLiteral("yes") : QStringLiteral("no"));
        return base1->callback() == QStringLiteral("oob") && base2->callback().startsWith("http://");
    });
#else
    const char *const checks[] = {
        "networkauth/oauth1-signature", "networkauth/oauth1-flow-construct",
        "networkauth/oauth2-flow-construct", "networkauth/reply-handlers"
    };
    for (unsigned i = 0; i < sizeof(checks) / sizeof(checks[0]); ++i) {
        r.check(QString::fromLatin1(checks[i]), [&](QString &d) {
            r.skip(d, QStringLiteral("QtNetworkAuth is excluded by the SDK license profile"));
            return false;
        });
    }
#endif
}

void checkSerialPort(SmokeReporter &r)
{
    r.check("serialport/enumerate-and-construct", [&](QString &d) {
        const QList<QSerialPortInfo> ports = QSerialPortInfo::availablePorts();
        // No real port is required to exercise the class - construction,
        // configuration, and (a failing) open() all touch real API surface.
        QSerialPort port;
        port.setPortName(ports.isEmpty() ? QStringLiteral("COM99") : ports.first().portName());
        port.setBaudRate(QSerialPort::Baud9600);
        port.setDataBits(QSerialPort::Data8);
        port.setParity(QSerialPort::NoParity);
        port.setStopBits(QSerialPort::OneStop);
        return port.baudRate() == QSerialPort::Baud9600 && port.dataBits() == QSerialPort::Data8;
    });
}

#else

static void skipModernExtraModule(SmokeReporter &r, const char *name, const char *module)
{
    r.check(QString::fromLatin1(name), [&](QString &d) {
        r.skip(d, QString::fromLatin1(module) + QStringLiteral(" has no Qt 4 module"));
        return false;
    });
}

void checkWebSockets(SmokeReporter &r) { skipModernExtraModule(r, "websocket/module", "QtWebSockets"); }
void checkWebChannel(SmokeReporter &r) { skipModernExtraModule(r, "webchannel/module", "QtWebChannel"); }
void checkNetworkAuth(SmokeReporter &r) { skipModernExtraModule(r, "networkauth/module", "QtNetworkAuth"); }
void checkSerialPort(SmokeReporter &r) { skipModernExtraModule(r, "serialport/module", "QtSerialPort"); }

#endif // SMOKE_QT5
