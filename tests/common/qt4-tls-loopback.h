// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Qt4 blocking TLS test. A separate server thread avoids Qt5-only signal APIs.
#ifndef QT4_TLS_LOOPBACK_H
#define QT4_TLS_LOOPBACK_H
#include <QThread>
#include <QMutex>
#include <QMutexLocker>
#include <QWaitCondition>
#include <QTcpServer>
#include <QSslSocket>
#include <QSslCertificate>
#include <QSslKey>
#include <QSslCipher>
#include "tls-loopback-fixture.h"

class Qt4TlsListener : public QTcpServer
{
public:
    int descriptor = -1;
protected:
    void incomingConnection(int value) override { descriptor = value; }
};

class Qt4TlsServer : public QThread
{
public:
    QMutex mutex;
    QWaitCondition ready;
    quint16 port = 0;
    bool listening = false;
    bool finishedSetup = false;
    bool exchanged = false;
    QString error;
    QSslCertificate certificate;
    QSslKey privateKey;

protected:
    void run() override
    {
        Qt4TlsListener listener;
        {
            QMutexLocker lock(&mutex);
            listening = listener.listen(QHostAddress::LocalHost, 0);
            port = listener.serverPort();
            finishedSetup = true;
            ready.wakeAll();
        }
        if (!listening) { error = listener.errorString(); return; }
        listener.waitForNewConnection(6000);
        if (listener.descriptor < 0) { error = "server accept timeout"; return; }
        QSslSocket socket;
        socket.setLocalCertificate(certificate);
        socket.setPrivateKey(privateKey);
        socket.setPeerVerifyMode(QSslSocket::VerifyNone); // No client certificate requested.
        socket.setProtocol(QSsl::SecureProtocols);
        // GCM requires TLS 1.2; Qt4's enum predates an explicit TLS 1.2 value.
        socket.setCiphers("AES128-GCM-SHA256");
        if (!socket.setSocketDescriptor(listener.descriptor)) { error = socket.errorString(); return; }
        socket.startServerEncryption();
        if (!socket.waitForEncrypted(6000)) { error = socket.errorString(); return; }
        if (socket.bytesAvailable() == 0 && !socket.waitForReadyRead(4000)) {
            error = socket.errorString(); return;
        }
        if (socket.readAll() != QByteArray("tls-ping")) { error = "unexpected request"; return; }
        socket.write("tls-pong");
        if (socket.bytesToWrite() == 0 || socket.waitForBytesWritten(4000)) exchanged = true;
        else error = socket.errorString();
        socket.disconnectFromHost();
        if (socket.state() != QAbstractSocket::UnconnectedState) socket.waitForDisconnected(1000);
    }
};

static bool qt4TlsLoopback(bool trustCertificate, bool correctHostname, QString &detail)
{
    if (!QSslSocket::supportsSsl()) { detail = "QSslSocket::supportsSsl() is false"; return false; }
    const QList<QSslCertificate> certificates = QSslCertificate::fromData(kTlsLoopbackCert);
    QSslKey key(QByteArray(kTlsLoopbackKey), QSsl::Rsa, QSsl::Pem, QSsl::PrivateKey);
    if (certificates.size() != 1 || key.isNull()) { detail = "certificate/key parsing failed"; return false; }
    Qt4TlsServer server;
    server.certificate = certificates.first();
    server.privateKey = key;
    server.start();
    quint16 port;
    {
        QMutexLocker lock(&server.mutex);
        while (!server.finishedSetup) server.ready.wait(&server.mutex);
        port = server.port;
    }
    if (!server.listening) { server.wait(); detail = server.error; return false; }
    QSslSocket client;
    client.setPeerVerifyMode(QSslSocket::VerifyPeer);
    client.setCaCertificates(trustCertificate ? certificates : QList<QSslCertificate>());
    client.setPeerVerifyName(correctHostname ? "localhost" : "wrong-host.example.test");
    client.setProtocol(QSsl::SecureProtocols);
    client.setCiphers("AES128-GCM-SHA256");
    if (client.ciphers().size() != 1 || client.ciphers().first().name() != "AES128-GCM-SHA256") {
        client.abort(); server.wait(); detail = "TLS 1.2 cipher selection was not honored"; return false;
    }
    client.connectToHostEncrypted("127.0.0.1", port);
    bool encrypted = client.waitForEncrypted(6000);
    bool accepted = trustCertificate && correctHostname;
    bool ok = false;
    if (accepted && encrypted) {
        client.write("tls-ping");
        client.waitForBytesWritten(4000);
        bool dataReady = client.bytesAvailable() > 0 || client.waitForReadyRead(4000);
        QString protocol = client.sessionCipher().protocolString();
        ok = dataReady && client.readAll() == QByteArray("tls-pong") && protocol == "TLSv1.2";
        detail = "protocol=" + protocol + " cipher=" + client.sessionCipher().name();
        std::printf("TLS: %s\n", qPrintable(detail));
    } else if (!accepted && !encrypted) {
        const QList<QSslError> errors = client.sslErrors();
        for (const QSslError &error : errors) {
            if ((!correctHostname && error.error() == QSslError::HostNameMismatch)
                    || (!trustCertificate && (error.error() == QSslError::SelfSignedCertificate
                        || error.error() == QSslError::SelfSignedCertificateInChain
                        || error.error() == QSslError::UnableToGetLocalIssuerCertificate))) ok = true;
        }
        detail = client.errorString();
    } else detail = client.errorString();
    client.abort();
    // Every blocking operation in run() has a timeout. Join before inspecting
    // shared results or destroying the QThread; never terminate its thread.
    server.wait();
    if (accepted) {
        ok = ok && server.exchanged;
        if (!server.exchanged) detail += " server=" + server.error;
    }
    return ok;
}
#endif
