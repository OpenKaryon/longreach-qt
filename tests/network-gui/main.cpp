// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// network-gui - local TCP/UDP/WebSocket/HTTP smoke app.
#include "../common/smokecheck.h"

#include <QApplication>
#include <QAbstractSocket>
#include <QHostAddress>
#include <QLabel>
#include <QLineEdit>
#include <QMainWindow>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QPushButton>
#include <QStatusBar>
#include <QTabWidget>
#include <QSslCertificate>
#include <QSslCipher>
#include <QSslConfiguration>
#include <QSslKey>
#include <QSslSocket>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTextEdit>
#include <QUdpSocket>
#include <QUrl>
#include <QVBoxLayout>
#if !SMOKE_QT5
#include "qt4_ui.h"
#endif
// QtWebSockets is Qt 5 and later. On Qt 4 the tab and its check are guarded
// out rather than the whole application being kept out of the build - the TCP,
// UDP and HTTP halves work identically on all three versions, and the check
// that goes missing says so under its own name.
#ifdef SMOKE_HAVE_WEBSOCKETS
#  include <QWebSocket>
#  include <QWebSocketProtocol>
#  include <QWebSocketServer>
#endif
#ifdef SMOKE_HAVE_HTTPSERVER
#  include <QHttpServer>
#  include <QHttpServerResponse>
#endif

// Qt 5 and Qt 6 use the compact lambda implementation below. Qt 4 presents
// the same tabs through qt4_ui.cpp, whose QObject slots are the period-correct
// spelling of the same signal flow.
#if SMOKE_QT5
static void logLine(QTextEdit *log, const QString &line)
{
    log->append(line);
}

static QWidget *makeTcpTab()
{
    auto *w = new QWidget;
    auto *layout = new QVBoxLayout(w);
    auto *log = new QTextEdit;
    log->setReadOnly(true);
    auto *server = new QTcpServer(w);
    auto *client = new QTcpSocket(w);
    auto *input = new QLineEdit("hello tcp");
    auto *start = new QPushButton("Start local echo server");
    auto *send = new QPushButton("Connect and send");
    layout->addWidget(start);
    layout->addWidget(input);
    layout->addWidget(send);
    layout->addWidget(log);

    QObject::connect(start, &QPushButton::clicked, w, [server, log] {
        if (server->isListening()) {
            logLine(log, "TCP server already listening");
            return;
        }
        if (server->listen(QHostAddress::LocalHost)) {
            logLine(log, QString("TCP server listening on %1").arg(server->serverPort()));
        } else {
            logLine(log, "TCP server failed: " + server->errorString());
        }
    });
    QObject::connect(server, &QTcpServer::newConnection, w, [server, log] {
        QTcpSocket *socket = server->nextPendingConnection();
        logLine(log, "TCP accepted");
        QObject::connect(socket, &QTcpSocket::readyRead, socket, [socket, log] {
            QByteArray data = socket->readAll();
            logLine(log, "TCP server read: " + QString::fromUtf8(data));
            socket->write("echo:" + data);
        });
        QObject::connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
    });
    QObject::connect(send, &QPushButton::clicked, w, [server, client, input, log] {
        if (!server->isListening()) {
            logLine(log, "Start TCP server first");
            return;
        }
        client->abort();
        client->connectToHost(QHostAddress::LocalHost, server->serverPort());
        if (client->waitForConnected(1000))
            client->write(input->text().toUtf8());
    });
    QObject::connect(client, &QTcpSocket::readyRead, w, [client, log] {
        logLine(log, "TCP client read: " + QString::fromUtf8(client->readAll()));
    });
    return w;
}

static QWidget *makeUdpTab()
{
    auto *w = new QWidget;
    auto *layout = new QVBoxLayout(w);
    auto *log = new QTextEdit;
    log->setReadOnly(true);
    auto *socket = new QUdpSocket(w);
    auto *send = new QPushButton("Bind and send UDP datagram");
    layout->addWidget(send);
    layout->addWidget(log);
    QObject::connect(send, &QPushButton::clicked, w, [socket, log] {
        if (socket->state() == QAbstractSocket::UnconnectedState)
            socket->bind(QHostAddress(QHostAddress::LocalHost), quint16(0));
        QByteArray payload("hello udp");
        socket->writeDatagram(payload, QHostAddress::LocalHost, socket->localPort());
        logLine(log, QString("UDP sent to %1").arg(socket->localPort()));
    });
    QObject::connect(socket, &QUdpSocket::readyRead, w, [socket, log] {
        while (socket->hasPendingDatagrams()) {
            QByteArray data;
            data.resize(int(socket->pendingDatagramSize()));
            socket->readDatagram(data.data(), data.size());
            logLine(log, "UDP read: " + QString::fromUtf8(data));
        }
    });
    return w;
}

#ifdef SMOKE_HAVE_WEBSOCKETS
static QWidget *makeWebSocketTab()
{
    auto *w = new QWidget;
    auto *layout = new QVBoxLayout(w);
    auto *log = new QTextEdit;
    log->setReadOnly(true);
    auto *server = new QWebSocketServer("qt-smoke", QWebSocketServer::NonSecureMode, w);
    auto *client = new QWebSocket(QString(), QWebSocketProtocol::VersionLatest, w);
    auto *start = new QPushButton("Start WebSocket echo");
    auto *send = new QPushButton("Connect and send");
    layout->addWidget(start);
    layout->addWidget(send);
    layout->addWidget(log);

    QObject::connect(start, &QPushButton::clicked, w, [server, log] {
        if (server->isListening()) {
            logLine(log, "WebSocket server already listening");
            return;
        }
        if (server->listen(QHostAddress::LocalHost)) {
            logLine(log, QString("WebSocket listening on %1").arg(server->serverPort()));
        } else {
            logLine(log, "WebSocket failed: " + server->errorString());
        }
    });
    QObject::connect(server, &QWebSocketServer::newConnection, w, [server, log] {
        QWebSocket *socket = server->nextPendingConnection();
        logLine(log, "WebSocket accepted");
        QObject::connect(socket, &QWebSocket::textMessageReceived, socket, [socket, log](const QString &msg) {
            logLine(log, "WebSocket server read: " + msg);
            socket->sendTextMessage("echo:" + msg);
        });
        QObject::connect(socket, &QWebSocket::disconnected, socket, &QObject::deleteLater);
    });
    QObject::connect(send, &QPushButton::clicked, w, [server, client, log] {
        if (!server->isListening()) {
            logLine(log, "Start WebSocket server first");
            return;
        }
        client->open(QUrl(QString("ws://127.0.0.1:%1").arg(server->serverPort())));
    });
    QObject::connect(client, &QWebSocket::connected, w, [client, log] {
        logLine(log, "WebSocket client connected");
        client->sendTextMessage("hello websocket");
    });
    QObject::connect(client, &QWebSocket::textMessageReceived, w, [log](const QString &msg) {
        logLine(log, "WebSocket client read: " + msg);
    });
    return w;
}

#endif // SMOKE_HAVE_WEBSOCKETS

static QWidget *makeHttpTab()
{
    auto *w = new QWidget;
    auto *layout = new QVBoxLayout(w);
    auto *log = new QTextEdit;
    log->setReadOnly(true);
    auto *tcpServer = new QTcpServer(w);
#ifdef SMOKE_HAVE_HTTPSERVER
    auto *server = new QHttpServer(w);
    server->route(QStringLiteral("/"), [log]() {
        logLine(log, "QHttpServer routed GET /");
        return QHttpServerResponse(QByteArrayLiteral("text/plain"),
                                   QByteArrayLiteral("hello http\n"));
    });
#else
    auto *server = tcpServer;
#endif
    auto *nam = new QNetworkAccessManager(w);
    auto *start = new QPushButton("Start local HTTP server");
    auto *get = new QPushButton("GET /");
    layout->addWidget(start);
    layout->addWidget(get);
    layout->addWidget(log);

    QObject::connect(start, &QPushButton::clicked, w, [server, tcpServer, log] {
#ifdef SMOKE_HAVE_HTTPSERVER
        if (server->property("smokePort").toUInt() != 0) {
            logLine(log, "QHttpServer already listening");
            return;
        }
        bool bound = tcpServer->listen(QHostAddress::LocalHost, 0);
        if (bound) {
#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
            bound = server->bind(tcpServer);
#else
            // The Qt 5 QtHttpServer snapshot's bind() returns void.
            server->bind(tcpServer);
            bound = tcpServer->isListening();
#endif
        }
        if (!bound) {
            tcpServer->close();
            logLine(log, "QHttpServer failed to listen");
            return;
        }
        const quint16 port = tcpServer->serverPort();
        server->setProperty("smokePort", port);
        logLine(log, QString("QHttpServer listening on %1").arg(port));
#else
        if (!server->isListening() && server->listen(QHostAddress::LocalHost))
            logLine(log, QString("HTTP server listening on %1").arg(server->serverPort()));
#endif
    });
#ifndef SMOKE_HAVE_HTTPSERVER
    QObject::connect(server, &QTcpServer::newConnection, w, [server, log] {
        QTcpSocket *socket = server->nextPendingConnection();
        QObject::connect(socket, &QTcpSocket::readyRead, socket, [socket, log] {
            socket->readAll();
            socket->write("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 11\r\n\r\nhello http\n");
            socket->disconnectFromHost();
            logLine(log, "HTTP response sent");
        });
        QObject::connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
    });
#endif
    QObject::connect(get, &QPushButton::clicked, w, [server, nam, log] {
#ifdef SMOKE_HAVE_HTTPSERVER
        const quint16 port = quint16(server->property("smokePort").toUInt());
#else
        const quint16 port = server->serverPort();
#endif
        if (!port) {
            logLine(log, "Start HTTP server first");
            return;
        }
        QNetworkReply *reply = nam->get(QNetworkRequest(QUrl(QString("http://127.0.0.1:%1/").arg(port))));
        QObject::connect(reply, &QNetworkReply::finished, reply, [reply, log] {
            logLine(log, "HTTP client read: " + QString::fromUtf8(reply->readAll()).trimmed());
            reply->deleteLater();
        });
    });
    return w;
}

static QWidget *buildUi()
{
    auto *tabs = new QTabWidget;
    tabs->addTab(makeTcpTab(), "TCP");
    tabs->addTab(makeUdpTab(), "UDP");
#ifdef SMOKE_HAVE_WEBSOCKETS
    tabs->addTab(makeWebSocketTab(), "WebSocket");
#endif
    tabs->addTab(makeHttpTab(), "HTTP");
    return tabs;
}

#endif // SMOKE_QT5

static int runSelfTest()
{
    SmokeReporter r("network-gui");
    r.check("network/tcp-server-construct", [](QString &) {
        QTcpServer server;
        return server.listen(QHostAddress::LocalHost) && server.serverPort() > 0;
    });
    r.check("network/udp-bind-construct", [](QString &) {
        QUdpSocket socket;
        return socket.bind(QHostAddress(QHostAddress::LocalHost), quint16(0));
    });
    r.check("network/websocket-server-construct", [&](QString &d) {
#ifdef SMOKE_HAVE_WEBSOCKETS
        QWebSocketServer server("qt-smoke", QWebSocketServer::NonSecureMode);
        return server.listen(QHostAddress::LocalHost);
#else
        r.skip(d, "QtWebSockets is Qt 5 and later");
        return true;
#endif
    });

    // SSL, reading a real certificate back: on Qt 4 this checks the port of Qt's
    // SSL backend to the OpenSSL 1.1 API. The certificate is self-signed, has no
    // private key here, expires in 2126, and is X.509 v3 (a v1 certificate reads
    // as version 0 either way).
    static const char *const kSelfTestCertificate =
        "-----BEGIN CERTIFICATE-----\n"
        "MIIDLDCCAhSgAwIBAgICExcwDQYJKoZIhvcNAQELBQAwNjEfMB0GA1UEAwwWcXQ0\n"
        "LWJ1aWxkLWtpdC1zZWxmdGVzdDETMBEGA1UECgwKT3BlbkthcnlvbjAgFw0yNjA4\n"
        "MTEwOTEyMjRaGA8yMTI2MDcxODA5MTIyNFowNjEfMB0GA1UEAwwWcXQ0LWJ1aWxk\n"
        "LWtpdC1zZWxmdGVzdDETMBEGA1UECgwKT3BlbkthcnlvbjCCASIwDQYJKoZIhvcN\n"
        "AQEBBQADggEPADCCAQoCggEBAKziBXAKvf3Q8K8G2WfbaXw1TLm+I+C3kyuTEmql\n"
        "g/XBb6h/koHRIDbTCzHUSPS3oNOaorFx/pwa3F+socoFJGhQNL298JF/HWmC1ARn\n"
        "zbuaCY7Ffwr/jsN/peJIC1JPio2m99B2ohh+GFJsdBSQvkzQczbtRmbTki9ns9OS\n"
        "8gL7+2cAJncaV4YeZl5CxzDETil/kcywE1K7uxzN/86hZ71O+60nSGRUQSonDlg2\n"
        "J7q/WbUicBPxX5ua9tHtptzROplekW0jmyY9TkXPGyTP5KG+TT43lQYqpDH4wSa1\n"
        "UM8bhqoFhLnHNGLtMFuORLMWGqLMi7P5Igjofv6Nwj0RFZsCAwEAAaNCMEAwDwYD\n"
        "VR0TAQH/BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAoQwHQYDVR0OBBYEFON0i4pVLVv6\n"
        "k3rATPFPo/7xDncjMA0GCSqGSIb3DQEBCwUAA4IBAQBxvhtj+BwDiwmZy2BuB6e1\n"
        "CcXHD0CpyZ2C7Q0P3kEbE+hP+mY9R7Lw4YFxtIrmn6wDjcDWozkTUltnZ/fUvwZx\n"
        "PVOMmyYXjIoqTTPuVoH5z4GGQQG1i56IQIky4utSM7D+bUDZdwpNYlZGof1Ofjh5\n"
        "5qocSRVP0vEfAradc/muaSe/thJqFJC4ytu9ycoDSskPG2l81fW+v+dcnlIg8bXD\n"
        "OieQ04ysUS0asDjYX4S7tVyn8DLPCcuVJgSZKBfTTnzpEYr0sHPvaVGgCdPQBgxS\n"
        "exn5AWy7TvJB1Zu0MaN6LvGxelY9138cIL4ZZOzJVdQNoItO2ArgBaM79C6c/y49\n"
        "-----END CERTIFICATE-----\n";

#ifndef QT_NO_SSL
    r.check("ssl/supported", [&](QString &d) {
        if (!QSslSocket::supportsSsl()) {
            r.skip(d, "this SDK was built without SSL");
            return true;
        }
        return true;
    });

    r.check("ssl/ciphers", [&](QString &d) {
        if (!QSslSocket::supportsSsl()) {
            r.skip(d, "no SSL backend");
            return true;
        }
        // A key size from every cipher proves SSL_CIPHER_get_bits() on the Qt 4 port.
        // Qt 6 has the list only on QSslConfiguration; Qt 4 only on QSslSocket.
#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
        const QList<QSslCipher> ciphers = QSslConfiguration::supportedCiphers();
#else
        const QList<QSslCipher> ciphers = QSslSocket::supportedCiphers();
#endif
        // eNULL ciphers encrypt nothing and must report 0 bits (Qt 6 on OpenSSL 3
        // lists six); every other cipher must report some.
        int encrypting = 0;
        QStringList wrong;
        for (int i = 0; i < ciphers.count(); ++i) {
            const QSslCipher c = ciphers.at(i);
            const QString name = c.name();
            const bool isNull = name.contains(QLatin1String("NULL"));
            if (name.isEmpty()) {
                wrong.append(QLatin1String("<unnamed>"));
            } else if (isNull && c.usedBits() != 0) {
                wrong.append(name + QLatin1String(" (null cipher claims ")
                             + QString::number(c.usedBits()) + QLatin1String(" bits)"));
            } else if (!isNull && c.usedBits() <= 0) {
                wrong.append(name + QLatin1String(" (no key size)"));
            } else if (!isNull) {
                ++encrypting;
            }
        }
        d = QString::fromLatin1("%1 of %2 ciphers encrypt and report a key size")
                .arg(encrypting).arg(ciphers.count());
        if (!wrong.isEmpty())
            d += QLatin1String("; inconsistent: ") + wrong.join(QLatin1String(", "));
        return !ciphers.isEmpty() && encrypting > 0 && wrong.isEmpty();
    });

    r.check("ssl/certificate", [&](QString &d) {
        if (!QSslSocket::supportsSsl()) {
            r.skip(d, "no SSL backend");
            return true;
        }
        const QList<QSslCertificate> certs =
            QSslCertificate::fromData(QByteArray(kSelfTestCertificate), QSsl::Pem);
        if (certs.isEmpty()) {
            d = QString::fromLatin1("the embedded certificate did not parse");
            return false;
        }
        const QSslCertificate cert = certs.first();
        const QString version = QString::fromLatin1(cert.version());
        const QString serial = QString::fromLatin1(cert.serialNumber());
#if SMOKE_QT5
        const QString cn = cert.subjectInfo(QSslCertificate::CommonName).value(0);
#else
        const QString cn = cert.subjectInfo(QSslCertificate::CommonName);
#endif
        // Qt spells a serial decimal when it fits in four bytes and
        // colon-separated hex otherwise; 0x1317 fits, so reading it as hex
        // would give 18567 and fail a build that is working perfectly.
        QString digits = serial;
        const bool isHex = digits.contains(QLatin1Char(':'));
        digits.remove(QLatin1Char(':'));
        const int serialValue = digits.toInt(0, isHex ? 16 : 10);
        d = QString::fromLatin1("v%1 serial %2 cn %3").arg(version, serial, cn);
        return version == QLatin1String("3") && serialValue == 4887
            && cn == QLatin1String("qt4-build-kit-selftest");
    });

    r.check("ssl/public-key", [&](QString &d) {
        if (!QSslSocket::supportsSsl()) {
            r.skip(d, "no SSL backend");
            return true;
        }
        // X509_get_X509_PUBKEY, EVP_PKEY_base_id and RSA_bits in one call - the
        // three riskiest accessor rewrites in the Qt 4 OpenSSL port.
        const QList<QSslCertificate> certs =
            QSslCertificate::fromData(QByteArray(kSelfTestCertificate), QSsl::Pem);
        if (certs.isEmpty())
            return false;
        const QSslKey key = certs.first().publicKey();
        d = QString::fromLatin1("length %1").arg(key.length());
        return !key.isNull() && key.algorithm() == QSsl::Rsa && key.length() == 2048;
    });
#else
    Q_UNUSED(kSelfTestCertificate);
    r.check("ssl/supported", [&](QString &d) {
        r.skip(d, "this SDK was built without SSL");
        return true;
    });
#endif

    return r.summary();
}

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    if (app.arguments().contains("--selftest"))
        return runSelfTest();

#if !SMOKE_QT5
    QMainWindow win;
    win.setWindowTitle("Qt Network GUI - " QT_VERSION_STR);
    win.setCentralWidget(buildQt4NetworkUi());
    win.statusBar()->showMessage("Network GUI - local TCP/UDP/HTTP smoke; WebSocket unavailable in Qt 4");
    win.resize(800, 580);
    win.show();
    return app.exec();
#else
    QMainWindow win;
    win.setWindowTitle("Qt Network GUI - " QT_VERSION_STR);
    win.setCentralWidget(buildUi());
    win.statusBar()->showMessage("Network GUI - local TCP/UDP/WebSocket/HTTP smoke");
    win.resize(800, 580);
    win.show();
    return app.exec();
#endif
}
