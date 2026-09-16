// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// JSON, XML (stream + DOM), CBOR. Headless.
#include "../common/smokecheck.h"
#include "checks.h"

#if SMOKE_QT5
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QJsonValue>
#include <QJsonParseError>
#endif
#include <QXmlStreamReader>
#include <QXmlStreamWriter>
#include <QDomDocument>
#include <QDomElement>
#if SMOKE_QT5
#include <QCborValue>
#include <QCborMap>
#include <QCborArray>
#include <QCborStreamWriter>
#include <QCborStreamReader>
#endif
#include <QBuffer>

void checkSerialization(SmokeReporter &r)
{
#if SMOKE_QT5
    r.check("json/roundtrip", [&r](QString &d) {
        QJsonObject o; o["name"]="qt"; o["n"]=5; o["arr"]=QJsonArray{1,2,3}; o["nested"]=QJsonObject{{"k",true}};
        QByteArray j = QJsonDocument(o).toJson(QJsonDocument::Compact);
        QJsonParseError err; auto doc = QJsonDocument::fromJson(j, &err);
        if (err.error != QJsonParseError::NoError) { d=err.errorString(); return false; }
        auto ob = doc.object();
        return ob["n"].toInt()==5 && ob["arr"].toArray().size()==3 && ob["nested"].toObject()["k"].toBool();
    });
    r.check("json/parse-error", [&r](QString &d) {
        QJsonParseError err; QJsonDocument::fromJson("{bad", &err);
        return err.error != QJsonParseError::NoError;
    });
#else
    r.check("json/roundtrip", [&r](QString &d) {
        r.skip(d, QStringLiteral("Qt JSON classes arrived in Qt 5"));
        return false;
    });
#endif
    r.check("xml/stream-write-read", [&r](QString &d) {
        QByteArray out;
        { QXmlStreamWriter w(&out); w.setAutoFormatting(true);
          w.writeStartDocument(); w.writeStartElement("root");
          w.writeAttribute("v","1");
          for (int i=0;i<3;++i) w.writeTextElement("item", QString::number(i));
          w.writeEndElement(); w.writeEndDocument(); }
        QXmlStreamReader rd(out); int items=0; QString attr;
        while (!rd.atEnd()) {
            if (rd.readNext()==QXmlStreamReader::StartElement) {
                if (rd.name()==QLatin1String("root")) attr = rd.attributes().value("v").toString();
                if (rd.name()==QLatin1String("item")) ++items;
            }
        }
        if (rd.hasError()) { d=rd.errorString(); return false; }
        return items==3 && attr=="1";
    });
    r.check("xml/dom", [&r](QString &d) {
        QDomDocument doc("mydoc");
        QDomElement root = doc.createElement("catalog"); doc.appendChild(root);
        QDomElement e = doc.createElement("book"); e.setAttribute("id", 7);
        e.appendChild(doc.createTextNode("Qt")); root.appendChild(e);
        QByteArray xml = doc.toByteArray();
        QDomDocument doc2;
        if (!doc2.setContent(xml)) { d="reparse"; return false; }
        QDomElement b = doc2.documentElement().firstChildElement("book");
        return b.attribute("id").toInt()==7 && b.text()=="Qt";
    });
#if SMOKE_QT5
    r.check("cbor/value-roundtrip", [&r](QString &d) {
        QCborMap m; m[QLatin1String("k")]=42; m[QLatin1String("s")]="v";
        m[QLatin1String("a")]=QCborArray{1,2,3};
        QByteArray enc = m.toCborValue().toCbor();
        auto v = QCborValue::fromCbor(enc);
        if (!v.isMap()) { d="not map"; return false; }
        return v.toMap()[QLatin1String("k")].toInteger()==42
               && v.toMap()[QLatin1String("a")].toArray().size()==3;
    });
    r.check("cbor/stream", [&r](QString &d) {
        QByteArray buf;
        { QCborStreamWriter w(&buf); w.startArray(2); w.append(1); w.append(QLatin1String("x")); w.endArray(); }
        QCborStreamReader rd(buf);
        if (rd.type()!=QCborStreamReader::Array) { d="not array"; return false; }
        rd.enterContainer(); int first=0;
        if (rd.isInteger()) { first=int(rd.toInteger()); rd.next(); }
        return first==1;
    });
#else
    r.check("cbor/value-roundtrip", [&r](QString &d) {
        r.skip(d, QStringLiteral("CBOR support arrived in Qt 5"));
        return false;
    });
#endif
}
