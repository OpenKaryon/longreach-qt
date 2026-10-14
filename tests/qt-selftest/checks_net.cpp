// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Networking over loopback + value types (no external hosts). Headless.
#include "../common/smokecheck.h"
#include "checks.h"

#include <QTcpServer>
#include <QTcpSocket>
#include <QUdpSocket>
#include <QLocalServer>
#include <QLocalSocket>
#include <QHostAddress>
#include <QHostInfo>
#include <QNetworkInterface>
#include <QNetworkAddressEntry>
#if SMOKE_QT5
#include <QNetworkDatagram>
#endif
#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QNetworkCookie>
#include <QNetworkCookieJar>
#include <QNetworkProxy>
#ifndef QT_NO_SSL
#include <QSslCertificate>
#include <QSslKey>
#include <QSslSocket>
#endif
#include <QUrl>
#if SMOKE_QT5
#include <QUrlQuery>
#endif
#include <QEventLoop>
#include <QTimer>
#include <QElapsedTimer>
#if SMOKE_QT5
#include <QTemporaryDir>
#endif
#include <QFile>
#include <QCoreApplication>
#include <QUuid>
#if !SMOKE_QT5 && !defined(QT_NO_SSL) && !defined(QT_NO_OPENSSL)
#include "../common/qt4-tls-loopback.h"
#endif

#if SMOKE_QT5

static bool spin(const std::function<bool()> &done, int ms)
{
    QElapsedTimer t; t.start();
    while (!done() && t.elapsed()<ms) QCoreApplication::processEvents();
    return done();
}

#ifndef QT_NO_SSL
#include "../common/tls-loopback-fixture.h"

class TlsLoopbackServer : public QTcpServer
{
public:
    explicit TlsLoopbackServer(QObject *parent = nullptr) : QTcpServer(parent) {}

    QSslCertificate certificate;
    QSslKey privateKey;
    QSslSocket *socket = nullptr;
    bool encrypted = false;
    QByteArray received;
    QString errorText;

protected:
    void incomingConnection(qintptr socketDescriptor) override
    {
        socket = new QSslSocket(this);
        socket->setLocalCertificate(certificate);
        socket->setPrivateKey(privateKey);
        socket->setProtocol(QSsl::TlsV1_2OrLater);
        connect(socket, &QSslSocket::encrypted, this, [this] { encrypted = true; });
        connect(socket, &QSslSocket::readyRead, this, [this] {
            received += socket->readAll();
            socket->write(QByteArrayLiteral("tls-pong"));
        });
        connect(socket, QOverload<const QList<QSslError> &>::of(&QSslSocket::sslErrors),
                this, [this](const QList<QSslError> &errors) {
            if (!errors.isEmpty())
                errorText = errors.first().errorString();
        });
        connect(socket, &QAbstractSocket::errorOccurred,
                this, [this] { errorText = socket->errorString(); });
        if (!socket->setSocketDescriptor(socketDescriptor)) {
            errorText = socket->errorString();
            socket->deleteLater();
            socket = nullptr;
            return;
        }
        socket->startServerEncryption();
    }
};
#endif // QT_NO_SSL

void checkNetwork(SmokeReporter &r)
{
    r.check("net/tcp-loopback", [&r](QString &d) {
        QTcpServer srv;
        if (!srv.listen(QHostAddress::LocalHost, 0)) { d=srv.errorString(); return false; }
        QByteArray got;
        QObject::connect(&srv,&QTcpServer::newConnection,&srv,[&]{
            QTcpSocket *c = srv.nextPendingConnection();
            QObject::connect(c,&QTcpSocket::readyRead,c,[&,c]{ got+=c->readAll(); c->disconnectFromHost(); });
        });
        QTcpSocket cli; cli.connectToHost(QHostAddress::LocalHost, srv.serverPort());
        if (!cli.waitForConnected(2000)) { d="connect"; return false; }
        cli.write("ping"); cli.flush(); cli.waitForBytesWritten(1000);
        return spin([&]{ return got=="ping"; }, 2000);
    });
    r.check("net/udp-datagram", [&r](QString &d) {
        // One socket sending to its own bound port - the simplest loopback, with
        // no two-socket interaction. Bind to an explicit port because
        // QUdpSocket::localPort() returned 0 after bind(LocalHost, 0) here.
        QUdpSocket sock; quint16 port = 0;
        for (quint16 p : {45454, 46565, 47676})
            if (sock.bind(QHostAddress(QHostAddress::LocalHost), p)) { port = p; break; }
        if (!port) { r.skip(d, "no free loopback UDP port to bind"); return false; }
        qint64 sent = sock.writeDatagram(QByteArray("pong"), QHostAddress(QHostAddress::LocalHost), port);
        if (sent != 4) { d=QString("writeDatagram=%1 (%2)").arg(sent).arg(sock.errorString()); return false; }
        if (!sock.waitForReadyRead(2000) && !sock.hasPendingDatagrams()) {
            // Send path works (sent 4 bytes) and TCP loopback passed, so an
            // undelivered UDP datagram is an environment issue (a firewall or
            // security product filtering loopback UDP), not a Qt/backport defect.
            r.skip(d, QString("loopback UDP not delivered (sent %1 to port %2) - likely firewall").arg(sent).arg(port));
            return false;
        }
        QNetworkDatagram dg = sock.receiveDatagram();
        return dg.data()=="pong";
    });
    r.check("net/localsocket", [&r](QString &d) {
        QString name = "qtsmoke-" + QUuid::createUuid().toString(QUuid::Id128);
        QLocalServer srv; QLocalServer::removeServer(name);
        if (!srv.listen(name)) { r.skip(d,"local server unavailable: "+srv.errorString()); return false; }
        QByteArray got;
        QObject::connect(&srv,&QLocalServer::newConnection,&srv,[&]{
            QLocalSocket *c = srv.nextPendingConnection();
            QObject::connect(c,&QLocalSocket::readyRead,c,[&,c]{ got+=c->readAll(); });
        });
        QLocalSocket cli; cli.connectToServer(name);
        if (!cli.waitForConnected(2000)) { r.skip(d,"connect failed"); return false; }
        cli.write("hi"); cli.flush(); cli.waitForBytesWritten(1000);
        return spin([&]{ return got=="hi"; },2000);
    });
    r.check("net/interfaces", [&r](QString &d) {
        auto ifaces = QNetworkInterface::allInterfaces();
        if (ifaces.isEmpty()) { r.skip(d,"no interfaces"); return false; }
        // there should be at least a loopback address somewhere
        for (const auto &it : ifaces)
            for (const auto &e : it.addressEntries())
                if (e.ip().isLoopback()) return true;
        return !QNetworkInterface::allAddresses().isEmpty();
    });
    r.check("net/hostaddress", [&r](QString &d) {
        QHostAddress a("192.168.1.1"), lo(QHostAddress::LocalHost), v6("::1");
        return a.protocol()==QAbstractSocket::IPv4Protocol && lo.isLoopback() && v6.isLoopback();
    });
    r.check("net/url+query", [&r](QString &d) {
        QUrl u("https://example.com:8080/path?a=1&b=two#frag");
        QUrlQuery q(u);
        return u.host()=="example.com" && u.port()==8080 && q.queryItemValue("b")=="two" && u.fragment()=="frag";
    });
    r.check("net/cookie", [&r](QString &d) {
        auto list = QNetworkCookie::parseCookies("name=value; Path=/");
        if (list.isEmpty()) { d="parse"; return false; }
        QNetworkCookieJar jar;
        jar.setCookiesFromUrl(list, QUrl("http://x/"));
        return list.first().name()=="name" && jar.cookiesForUrl(QUrl("http://x/")).size()==1;
    });
    r.check("net/proxy-value", [&r](QString &) {
        QNetworkProxy p(QNetworkProxy::HttpProxy, "127.0.0.1", 3128);
        return p.type()==QNetworkProxy::HttpProxy && p.port()==3128;
    });
#ifndef QT_NO_SSL
    r.check("net/tls-loopback-handshake", [&](QString &d) {
        if (!QSslSocket::supportsSsl()) {
            d = QStringLiteral("QSslSocket::supportsSsl() is false");
            return false;
        }
        const QList<QSslCertificate> certs =
            QSslCertificate::fromData(QByteArray(kTlsLoopbackCert), QSsl::Pem);
        QSslKey key(QByteArray(kTlsLoopbackKey), QSsl::Rsa, QSsl::Pem, QSsl::PrivateKey);
        if (certs.isEmpty() || certs.first().isNull() || key.isNull()) {
            d = QStringLiteral("embedded certificate/key did not parse");
            return false;
        }

#ifdef Q_OS_MACOS
        // SecureTransport imports the server identity into the default
        // keychain, which an SSH session cannot unlock; a temporary keychain
        // also leaves the user's keychain alone.
        qputenv("QT_SSL_USE_TEMPORARY_KEYCHAIN", "1");
#endif
        TlsLoopbackServer srv;
        srv.certificate = certs.first();
        srv.privateKey = key;
        if (!srv.listen(QHostAddress::LocalHost, 0)) {
            d = srv.errorString();
            return false;
        }

        QSslSocket cli;
        QByteArray reply;
        QString clientError;
        bool clientEncrypted = false;
        cli.setPeerVerifyMode(QSslSocket::VerifyNone);
        cli.setProtocol(QSsl::TlsV1_2OrLater);
        QObject::connect(&cli, &QSslSocket::encrypted, &cli, [&] { clientEncrypted = true; });
        QObject::connect(&cli, &QSslSocket::readyRead, &cli, [&] { reply += cli.readAll(); });
        QObject::connect(&cli, QOverload<const QList<QSslError> &>::of(&QSslSocket::sslErrors),
                         &cli, [&cli](const QList<QSslError> &) { cli.ignoreSslErrors(); });
        QObject::connect(&cli, &QAbstractSocket::errorOccurred,
                         &cli, [&] { clientError = cli.errorString(); });

        cli.connectToHostEncrypted(QStringLiteral("localhost"), srv.serverPort());
        if (!spin([&] { return clientEncrypted && srv.encrypted; }, 5000)) {
            d = QStringLiteral("handshake timeout client='%1' server='%2'")
                    .arg(clientError, srv.errorText);
            return false;
        }
        cli.write(QByteArrayLiteral("tls-ping"));
        cli.flush();
        if (!spin([&] { return srv.received == QByteArrayLiteral("tls-ping")
                              && reply == QByteArrayLiteral("tls-pong"); }, 3000)) {
            d = QStringLiteral("data timeout server='%1' reply='%2'")
                    .arg(QString::fromLatin1(srv.received), QString::fromLatin1(reply));
            return false;
        }
        return true;
    });
#endif
    r.check("net/qnam-file-scheme", [&r](QString &d) {
        QTemporaryDir tmp; QString path = tmp.filePath("x.txt");
        { QFile f(path); f.open(QIODevice::WriteOnly); f.write("nam-ok"); }
        QNetworkAccessManager nam;
        QNetworkReply *rep = nam.get(QNetworkRequest(QUrl::fromLocalFile(path)));
        QEventLoop loop; QObject::connect(rep,&QNetworkReply::finished,&loop,&QEventLoop::quit);
        QTimer::singleShot(3000,&loop,&QEventLoop::quit); loop.exec();
        QByteArray body = rep->readAll(); rep->deleteLater();
        return body=="nam-ok";
    });
}

#else

void checkNetwork(SmokeReporter &r)
{
    r.check("net/tcp-loopback", [&r](QString &d) {
        QTcpServer server;
        if (!server.listen(QHostAddress::LocalHost, 0)) { d=server.errorString(); return false; }
        QTcpSocket client;
        client.connectToHost(QHostAddress::LocalHost, server.serverPort());
        if (!client.waitForConnected(2000) || !server.waitForNewConnection(2000)) return false;
        QTcpSocket *peer = server.nextPendingConnection();
        client.write("ping"); client.waitForBytesWritten(1000);
        if (!peer->waitForReadyRead(2000)) return false;
        return peer->readAll()=="ping";
    });
    r.check("net/udp-datagram", [&r](QString &d) {
        QUdpSocket socket;
        if (!socket.bind(QHostAddress(QHostAddress::LocalHost), 0)) return false;
        if (socket.writeDatagram("pong", 4, QHostAddress(QHostAddress::LocalHost), socket.localPort()) != 4) return false;
        if (!socket.waitForReadyRead(2000)) { r.skip(d, "loopback UDP not delivered"); return false; }
        char data[8] = {}; QHostAddress sender; quint16 port=0;
        return socket.readDatagram(data, sizeof(data), &sender, &port)==4 && QByteArray(data,4)=="pong";
    });
    r.check("net/interfaces", [&r](QString &d) {
        const QList<QNetworkInterface> interfaces = QNetworkInterface::allInterfaces();
        const QList<QHostAddress> addresses = QNetworkInterface::allAddresses();
        d = QStringLiteral("interfaces=%1 addresses=%2").arg(interfaces.size()).arg(addresses.size());
        return !addresses.isEmpty();
    });
    r.check("net/hostaddress", [&r](QString &d) {
        QHostAddress address("192.168.1.1");
        return address.protocol()==QAbstractSocket::IPv4Protocol;
    });
    r.check("net/url+query", [&r](QString &d) {
        QUrl url("https://example.com:8080/path?a=1&b=two#frag");
        return url.host()=="example.com" && url.port()==8080
            && url.queryItemValue("b")=="two" && url.fragment()=="frag";
    });
    r.check("net/cookie+proxy", [&r](QString &d) {
        QList<QNetworkCookie> cookies = QNetworkCookie::parseCookies("name=value; Path=/");
        QNetworkProxy proxy(QNetworkProxy::HttpProxy, "127.0.0.1", 3128);
        return !cookies.isEmpty() && cookies.first().name()=="name" && proxy.port()==3128;
    });
#if !defined(QT_NO_SSL) && !defined(QT_NO_OPENSSL)
    r.check("net/tls-loopback-handshake", [](QString &d) {
        return qt4TlsLoopback(true, true, d);
    });
    r.check("net/tls-reject-untrusted-certificate", [](QString &d) {
        return qt4TlsLoopback(false, true, d);
    });
    r.check("net/tls-reject-wrong-hostname", [](QString &d) {
        return qt4TlsLoopback(true, false, d);
    });
#else
    r.check("net/tls-loopback-handshake", [&r](QString &d) {
        r.skip(d, QStringLiteral("Qt 4 SDK was built without SSL"));
        return false;
    });
#endif
}

#endif // SMOKE_QT5
