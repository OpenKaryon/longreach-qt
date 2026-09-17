// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Lower-traffic modules that still ship in the backport and are cheap to
// smoke-test headlessly: QtLocation's value types (no network/GPS needed to
// construct and manipulate coordinates/shapes/places), QtScript (deprecated
// but still built - same idea as the QJSEngine checks in quick-qml), and
// QtXmlPatterns (XQuery/XPath evaluation over an in-memory string).
#include "../common/smokecheck.h"

#if SMOKE_QT5
#include <QGeoCoordinate>
#include <QGeoRectangle>
#include <QGeoCircle>
#include <QGeoPath>
#include <QGeoPolygon>
#include <QGeoLocation>
#include <QGeoAddress>
#include <QGeoPositionInfo>
#include <QGeoSatelliteInfo>

#include <QPlace>
#include <QPlaceAttribute>
#include <QPlaceCategory>
#include <QPlaceIcon>
#include <QPlaceRatings>
#include <QPlaceSupplier>
#include <QPlaceUser>
#if QT_VERSION_MAJOR < 6
#include <QPlaceEditorial>
#endif
#endif // SMOKE_QT5

#ifdef SMOKE_HAVE_SCRIPT
#include <QScriptEngine>
#endif
#ifdef SMOKE_HAVE_SCRIPT
#include <QScriptValue>
#endif
#ifdef SMOKE_HAVE_SCRIPT
#include <QScriptContext>
#endif
#ifdef SMOKE_HAVE_SCRIPT
#include <QScriptValueIterator>
#endif
#ifdef SMOKE_HAVE_SCRIPT
#include <QScriptable>
#endif

#ifdef SMOKE_HAVE_XMLPATTERNS
#include <QXmlQuery>
#endif
#ifdef SMOKE_HAVE_XMLPATTERNS
#include <QXmlName>
#endif
#ifdef SMOKE_HAVE_XMLPATTERNS
#include <QXmlNamePool>
#endif
#ifdef SMOKE_HAVE_XMLPATTERNS
#include <QSourceLocation>
#endif
#ifdef SMOKE_HAVE_XMLPATTERNS
#include <QXmlSchema>
#endif
#ifdef SMOKE_HAVE_XMLPATTERNS
#include <QXmlSchemaValidator>
#endif

#include <QVariantMap>

void checkLocation(SmokeReporter &r)
{
#if SMOKE_QT5
    r.check("location/coordinate", [&](QString &d) {
        QGeoCoordinate coord(55.75, 37.62);
        if (!coord.isValid()) { d = "invalid coordinate"; return false; }
        QGeoCoordinate other(56.0, 38.0);
        return coord.distanceTo(other) > 0;
    });
    r.check("location/shapes", [&](QString &d) {
        QGeoRectangle rect(QGeoCoordinate(10, 0), QGeoCoordinate(0, 10));
        QGeoCircle circle(QGeoCoordinate(5, 5), 1000.0);
        QGeoPath path;
        path.addCoordinate(QGeoCoordinate(0, 0));
        path.addCoordinate(QGeoCoordinate(1, 1));
        QGeoPolygon poly;
        poly.addCoordinate(QGeoCoordinate(0, 0));
        poly.addCoordinate(QGeoCoordinate(0, 1));
        poly.addCoordinate(QGeoCoordinate(1, 0));
        return rect.isValid() && circle.radius() == 1000.0 && path.size() == 2 && poly.size() == 3;
    });
    r.check("location/geolocation-address", [&](QString &d) {
        QGeoAddress addr;
        addr.setCity("Moscow");
        addr.setCountry("Russia");
        QGeoLocation loc;
        loc.setAddress(addr);
        loc.setCoordinate(QGeoCoordinate(55.75, 37.62));
        return loc.address().city() == "Moscow" && loc.coordinate().isValid();
    });
    r.check("location/positioninfo", [&](QString &d) {
        QGeoPositionInfo info(QGeoCoordinate(1, 2), QDateTime::currentDateTime());
        info.setAttribute(QGeoPositionInfo::HorizontalAccuracy, 5.0);
        QGeoSatelliteInfo sat;
        sat.setSatelliteIdentifier(12);
        sat.setSignalStrength(40);
        return info.isValid() && info.attribute(QGeoPositionInfo::HorizontalAccuracy) > 0
            && sat.satelliteIdentifier() == 12;
    });
    r.check("location/place-value-types", [&](QString &d) {
        QPlace place;
        place.setName("Cafe");
        QPlaceCategory cat; cat.setName("Food");
        place.setCategories({cat});
        QPlaceRatings ratings; ratings.setAverage(4.5); ratings.setCount(10);
        place.setRatings(ratings);
        QPlaceIcon icon;
        QPlaceSupplier supplier; supplier.setName("OSM");
        place.setSupplier(supplier);
        QPlaceAttribute attr; attr.setText("wifi: yes");
        QPlaceUser user; user.setName("reviewer");
#if QT_VERSION_MAJOR < 6
        QPlaceEditorial editorial; editorial.setText("Great coffee"); editorial.setAttribution(user.name());
#endif
        return place.name() == "Cafe" && place.categories().size() == 1
            && qFuzzyCompare(place.ratings().average(), 4.5) && place.supplier().name() == "OSM"
            && attr.text().contains("wifi")
#if QT_VERSION_MAJOR < 6
            && editorial.text().contains("coffee")
#endif
            ;
    });
#else
    r.check("location/module", [&](QString &d) {
        r.skip(d, QStringLiteral("QtLocation has no Qt 4 module in this SDK"));
        return false;
    });
#endif
}

void checkScript(SmokeReporter &r)
{
#ifdef SMOKE_HAVE_SCRIPT
    r.check("script/engine-eval", [&](QString &d) {
        QScriptEngine engine;
        QScriptValue result = engine.evaluate("2 + 3 * 4");
        if (engine.hasUncaughtException()) { d = "uncaught exception"; return false; }
        return result.toInt32() == 14;
    });
    r.check("script/value-object-props", [&](QString &d) {
        QScriptEngine engine;
        QScriptValue obj = engine.newObject();
        obj.setProperty("a", QScriptValue(&engine, 5));
        obj.setProperty("b", QScriptValue(&engine, QString("hi")));
        int count = 0;
        QScriptValueIterator it(obj);
        while (it.hasNext()) { it.next(); ++count; }
        return obj.property("a").toInt32() == 5 && obj.property("b").toString() == "hi" && count == 2;
    });
    r.check("script/function-call-context", [&](QString &d) {
        QScriptEngine engine;
        engine.evaluate("function add(a, b) { return a + b; }");
        QScriptValue fn = engine.globalObject().property("add");
        QScriptValueList args; args << 3 << 4;
        QScriptValue res = fn.call(QScriptValue(), args);
        Q_UNUSED(d);
        return res.toInt32() == 7;
    });
#else
    r.check("script/engine-eval", [&](QString &d) {
        r.skip(d, QStringLiteral("QtScript is not in this SDK (Qt 6 dropped it; QJSEngine is the successor)"));
        return false;
    });
#endif
}

void checkXmlPatterns(SmokeReporter &r)
{
#ifdef SMOKE_HAVE_XMLPATTERNS
    r.check("xmlpatterns/xquery-eval", [&](QString &d) {
        QXmlQuery query;
        query.setQuery(QStringLiteral("<result>{1 + 2}</result>"));
        QString out;
        if (!query.evaluateTo(&out)) { d = "evaluateTo failed"; return false; }
        return bool(out.contains("3"));
    });
    r.check("xmlpatterns/xquery-string-join", [&](QString &d) {
        QXmlQuery query;
        query.setQuery(QStringLiteral(
            "let $x := <root><item>a</item><item>b</item></root> "
            "return string-join($x/item, ',')"));
        QString out;
        bool ok = query.evaluateTo(&out);
        return ok && out.trimmed() == "a,b";
    });
    r.check("xmlpatterns/name-pool-and-source-location", [&](QString &d) {
        QXmlNamePool pool;
        QXmlName name(pool, QStringLiteral("item"));
        QSourceLocation loc(QUrl("file:///test.xml"), 3, 5);
        return name.localName(pool) == "item" && loc.line() == 3 && loc.column() == 5;
    });
    r.check("xmlpatterns/schema-validator-construct", [&](QString &d) {
        QXmlSchema schema;
        QXmlSchemaValidator validator(schema);
        // No schema loaded - constructing the pair without validating anything
        // is enough to exercise the classes; isValid() reflects the empty schema.
        return !schema.isValid() ? true : validator.schema().isValid();
    });
#else
    r.check("xmlpatterns/xquery-eval", [&](QString &d) {
        r.skip(d, QStringLiteral("QtXmlPatterns is not in this SDK (Qt 6 dropped XQuery/XSLT/XML Schema)"));
        return false;
    });
#endif
}
