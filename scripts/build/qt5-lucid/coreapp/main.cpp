// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Lucid QtCore probe: run on stock Ubuntu 10.04; every line must PASS.
#include <QtCore>
#include <QtNetwork>
#include <QtSql>
#include <QtConcurrent>
#include <QtXml>
#include <cstdio>

static int failures = 0;
static void check(const char *name, bool ok, const QString &detail = QString())
{
    std::printf("%s: %s %s\n", ok ? "PASS" : "FAIL", name, qPrintable(detail));
    if (!ok) ++failures;
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    check("regex", QRegularExpression("lu(c)id").match("lucid").captured(1) == "c");
    check("json", QJsonDocument::fromJson("{\"a\":[1,2]}").object().value("a").toArray().size() == 2);
    QThread worker; worker.setObjectName("lucid-worker"); worker.start();
    check("thread", worker.isRunning()); worker.quit(); worker.wait();
    check("concurrent", QtConcurrent::run([] { return 6 * 7; }).result() == 42);
    QElapsedTimer t; t.start(); QThread::msleep(30); check("timer", t.elapsed() >= 20, QString::number(t.elapsed()));
    check("random", QRandomGenerator::system()->generate() != QRandomGenerator::system()->generate());
    QProcess p; p.start("/bin/echo", {"lucid"}); p.waitForFinished(5000);
    check("process", p.readAllStandardOutput().trimmed() == "lucid");
    QSqlDatabase db = QSqlDatabase::addDatabase("QSQLITE"); db.setDatabaseName(":memory:");
    QSqlQuery q(db.open() ? db : QSqlDatabase());
    check("sqlite", q.exec("select 6*7") && q.next() && q.value(0).toInt() == 42);
    QDomDocument dom; check("xml", dom.setContent(QStringLiteral("<a><b/></a>")) && dom.documentElement().firstChildElement("b").isElement());
    QTcpServer server; check("tcp-listen", server.listen(QHostAddress::LocalHost));
    QTcpSocket client; client.connectToHost(QHostAddress::LocalHost, server.serverPort());
    check("tcp-connect", client.waitForConnected(3000) && server.waitForNewConnection(3000));
    QUdpSocket a, b; a.bind(QHostAddress(QHostAddress::LocalHost), 0); b.writeDatagram("lucid", QHostAddress::LocalHost, a.localPort());
    const qint64 sent = b.writeDatagram("lucid", QHostAddress::LocalHost, a.localPort());
    const bool ready = a.waitForReadyRead(3000);
    const QNetworkDatagram dg = a.receiveDatagram();
    char raw[16] = {0}; QHostAddress from; quint16 port = 0;
    a.writeDatagram("x", QHostAddress::LocalHost, a.localPort()); a.waitForReadyRead(1000);
    const qint64 plain = a.readDatagram(raw, sizeof raw, &from, &port);
    check("udp", ready && dg.data() == "lucid", QString("sent=%1 ready=%2 dg=%3 valid=%4 err=%5/%6 plainRead=%7 '%8'")
          .arg(sent).arg(ready).arg(QString::fromLatin1(dg.data())).arg(dg.isValid()).arg(a.errorString(), b.errorString()).arg(plain).arg(raw));
    QTemporaryFile tmp; check("file", tmp.open() && tmp.write("x") == 1);
    check("hostinfo", !QHostInfo::localHostName().isEmpty(), QHostInfo::localHostName());
    check("locale", QLocale(QLocale::German).toString(1234.5, 'f', 1) == QString::fromUtf8("1.234,5"));
    std::printf("%s\n", failures ? "CORE PROBE FAILED" : "CORE PROBE OK");
    return failures;
}
