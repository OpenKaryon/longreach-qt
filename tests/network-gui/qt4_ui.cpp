// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

#include "qt4_ui.h"
#include "../common/qtcompat.h"

#include <QAbstractSocket>
#include <QHostAddress>
#include <QLabel>
#include <QLineEdit>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QPushButton>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTabWidget>
#include <QTextEdit>
#include <QUdpSocket>
#include <QUrl>
#include <QVBoxLayout>
#include <QWidget>

class TcpTabQt4 : public QWidget
{
    Q_OBJECT
public:
    TcpTabQt4() : m_server(new QTcpServer(this)), m_client(new QTcpSocket(this)),
                  m_input(new QLineEdit(QStringLiteral("hello tcp"))), m_log(new QTextEdit)
    {
        QVBoxLayout *layout = new QVBoxLayout(this);
        QPushButton *start = new QPushButton(QStringLiteral("Start local echo server"));
        QPushButton *send = new QPushButton(QStringLiteral("Connect and send"));
        m_log->setReadOnly(true);
        layout->addWidget(start); layout->addWidget(m_input); layout->addWidget(send); layout->addWidget(m_log);
        connect(start, SIGNAL(clicked()), this, SLOT(startServer()));
        connect(send, SIGNAL(clicked()), this, SLOT(sendMessage()));
        connect(m_server, SIGNAL(newConnection()), this, SLOT(acceptConnection()));
        connect(m_client, SIGNAL(readyRead()), this, SLOT(readClient()));
    }
private slots:
    void startServer() {
        if (m_server->isListening()) { m_log->append(QStringLiteral("TCP server already listening")); return; }
        m_log->append(m_server->listen(QHostAddress::LocalHost)
            ? QStringLiteral("TCP server listening on %1").arg(m_server->serverPort())
            : QStringLiteral("TCP server failed: ") + m_server->errorString());
    }
    void sendMessage() {
        if (!m_server->isListening()) { m_log->append(QStringLiteral("Start TCP server first")); return; }
        m_client->abort(); m_client->connectToHost(QHostAddress::LocalHost, m_server->serverPort());
        if (m_client->waitForConnected(1000)) m_client->write(m_input->text().toUtf8());
    }
    void acceptConnection() {
        QTcpSocket *socket = m_server->nextPendingConnection();
        m_log->append(QStringLiteral("TCP accepted"));
        connect(socket, SIGNAL(readyRead()), this, SLOT(readServer()));
        connect(socket, SIGNAL(disconnected()), socket, SLOT(deleteLater()));
    }
    void readServer() {
        QTcpSocket *socket = qobject_cast<QTcpSocket *>(sender()); if (!socket) return;
        const QByteArray data = socket->readAll();
        m_log->append(QStringLiteral("TCP server read: ") + QString::fromUtf8(data)); socket->write("echo:" + data);
    }
    void readClient() { m_log->append(QStringLiteral("TCP client read: ") + QString::fromUtf8(m_client->readAll())); }
private:
    QTcpServer *m_server; QTcpSocket *m_client; QLineEdit *m_input; QTextEdit *m_log;
};

class UdpTabQt4 : public QWidget
{
    Q_OBJECT
public:
    UdpTabQt4() : m_socket(new QUdpSocket(this)), m_log(new QTextEdit) {
        QVBoxLayout *layout = new QVBoxLayout(this); QPushButton *send = new QPushButton(QStringLiteral("Bind and send UDP datagram"));
        m_log->setReadOnly(true); layout->addWidget(send); layout->addWidget(m_log);
        connect(send, SIGNAL(clicked()), this, SLOT(sendDatagram())); connect(m_socket, SIGNAL(readyRead()), this, SLOT(readDatagrams()));
    }
private slots:
    void sendDatagram() {
        if (m_socket->state() == QAbstractSocket::UnconnectedState) m_socket->bind(QHostAddress(QHostAddress::LocalHost), quint16(0));
        m_socket->writeDatagram("hello udp", QHostAddress::LocalHost, m_socket->localPort());
        m_log->append(QStringLiteral("UDP sent to %1").arg(m_socket->localPort()));
    }
    void readDatagrams() {
        while (m_socket->hasPendingDatagrams()) { QByteArray data(int(m_socket->pendingDatagramSize()), 0); m_socket->readDatagram(data.data(), data.size()); m_log->append(QStringLiteral("UDP read: ") + QString::fromUtf8(data)); }
    }
private: QUdpSocket *m_socket; QTextEdit *m_log;
};

class HttpTabQt4 : public QWidget
{
    Q_OBJECT
public:
    HttpTabQt4() : m_server(new QTcpServer(this)), m_nam(new QNetworkAccessManager(this)), m_log(new QTextEdit) {
        QVBoxLayout *layout = new QVBoxLayout(this); QPushButton *start = new QPushButton(QStringLiteral("Start local HTTP server")); QPushButton *get = new QPushButton(QStringLiteral("GET /"));
        m_log->setReadOnly(true); layout->addWidget(start); layout->addWidget(get); layout->addWidget(m_log);
        connect(start, SIGNAL(clicked()), this, SLOT(startServer())); connect(get, SIGNAL(clicked()), this, SLOT(sendGet())); connect(m_server, SIGNAL(newConnection()), this, SLOT(acceptConnection()));
    }
private slots:
    void startServer() { if (!m_server->isListening() && m_server->listen(QHostAddress::LocalHost)) m_log->append(QStringLiteral("HTTP server listening on %1").arg(m_server->serverPort())); }
    void sendGet() { if (!m_server->isListening()) { m_log->append(QStringLiteral("Start HTTP server first")); return; } QNetworkReply *reply=m_nam->get(QNetworkRequest(QUrl(QStringLiteral("http://127.0.0.1:%1/").arg(m_server->serverPort())))); connect(reply,SIGNAL(finished()),this,SLOT(readReply())); }
    void acceptConnection() { QTcpSocket *socket=m_server->nextPendingConnection(); connect(socket,SIGNAL(readyRead()),this,SLOT(answerRequest())); connect(socket,SIGNAL(disconnected()),socket,SLOT(deleteLater())); }
    void answerRequest() { QTcpSocket *socket=qobject_cast<QTcpSocket *>(sender()); if (!socket) return; socket->readAll(); socket->write("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 11\r\n\r\nhello http\n"); socket->disconnectFromHost(); m_log->append(QStringLiteral("HTTP response sent")); }
    void readReply() { QNetworkReply *reply=qobject_cast<QNetworkReply *>(sender()); if (!reply) return; m_log->append(QStringLiteral("HTTP client read: ")+QString::fromUtf8(reply->readAll()).trimmed()); reply->deleteLater(); }
private: QTcpServer *m_server; QNetworkAccessManager *m_nam; QTextEdit *m_log;
};

QWidget *buildQt4NetworkUi()
{
    QTabWidget *tabs = new QTabWidget;
    tabs->addTab(new TcpTabQt4, QStringLiteral("TCP"));
    tabs->addTab(new UdpTabQt4, QStringLiteral("UDP"));
    QWidget *websocket = new QWidget; QVBoxLayout *wsLayout = new QVBoxLayout(websocket);
    QLabel *notice = new QLabel(QStringLiteral("QtWebSockets arrived after Qt 4.8.7.\nTCP, UDP and HTTP are fully interactive in this build.")); notice->setWordWrap(true); wsLayout->addWidget(notice); wsLayout->addStretch();
    tabs->addTab(websocket, QStringLiteral("WebSocket"));
    tabs->addTab(new HttpTabQt4, QStringLiteral("HTTP"));
    return tabs;
}

#include "qt4_ui.moc"
