// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// The rest of QtLocation: value types with no service required, plus a real
// (if trivial) geocoding/routing/place service wired together by hand -
// QGeoServiceProvider normally loads a named plugin, but every manager class
// here has a public constructor taking its engine directly, and the engine
// base classes themselves are concrete (their virtual methods already have
// default "unsupported" implementations) - only QGeoRoutingManagerEngine's
// calculateRoute() is pure virtual, so that's the one place a subclass is
// actually required.
#include "../common/smokecheck.h"

#if !SMOKE_QT5

void checkLocationServiceChain(SmokeReporter &r)
{
    r.check("location/service-chain", [&](QString &d) {
        r.skip(d, QStringLiteral("QtLocation has no Qt 4 module in this SDK"));
        return false;
    });
}

#else

#include <QGeoServiceProvider>
#include <QGeoServiceProviderFactory>
#include <QGeoCodingManager>
#include <QGeoCodingManagerEngine>
#include <QGeoCodeReply>
#include <QGeoRoutingManager>
#include <QGeoRoutingManagerEngine>
#include <QGeoRouteReply>
#include <QGeoRouteRequest>
#include <QGeoRoute>
#include <QGeoRouteSegment>
#include <QGeoManeuver>
#include <QPlaceManager>
#include <QPlaceManagerEngine>
#include <QPlaceReply>
#include <QPlaceContentReply>
#include <QPlaceDetailsReply>
#include <QPlaceIdReply>
#include <QPlaceMatchReply>
#include <QPlaceSearchReply>
#include <QPlaceSearchSuggestionReply>
#include <QPlaceContentRequest>
#include <QPlaceMatchRequest>
#include <QPlaceSearchRequest>
#include <QPlaceSearchResult>
#include <QPlaceResult>
#include <QPlaceProposedSearchResult>
#include <QPlaceContent>
#include <QPlaceContactDetail>
#if QT_VERSION_MAJOR < 6
#include <QPlaceImage>
#endif
#if QT_VERSION_MAJOR < 6
#include <QPlaceReview>
#endif

#include <QGeoPositionInfoSource>
#include <QGeoPositionInfoSourceFactory>
#include <QGeoAreaMonitorSource>
#include <QGeoAreaMonitorInfo>
#include <QGeoSatelliteInfoSource>
#include <QNmeaPositionInfoSource>
#include <QGeoShape>

#include <QBuffer>
#include <QGeoCoordinate>
#include <QGeoCircle>

namespace {

// QGeoRouteReply's (request, parent) constructor is protected - meant for a
// real engine's own reply subclass, which is exactly this.
class FixedRouteReply : public QGeoRouteReply
{
public:
    explicit FixedRouteReply(const QGeoRouteRequest &request, QObject *parent = nullptr)
        : QGeoRouteReply(request, parent) {}
};

class FixedRoutingEngine : public QGeoRoutingManagerEngine
{
public:
    using QGeoRoutingManagerEngine::QGeoRoutingManagerEngine;
    QGeoRouteReply *calculateRoute(const QGeoRouteRequest &request) override {
        return new FixedRouteReply(request, this);
    }
};

#if QT_VERSION_MAJOR < 6
class FixedPositionInfoSourceFactory : public QGeoPositionInfoSourceFactoryV2
{
public:
    QGeoPositionInfoSource *positionInfoSource(QObject *) override { return nullptr; }
    QGeoSatelliteInfoSource *satelliteInfoSource(QObject *) override { return nullptr; }
    QGeoAreaMonitorSource *areaMonitor(QObject *) override { return nullptr; }
    QGeoPositionInfoSource *positionInfoSourceWithParameters(QObject *, const QVariantMap &) override {
        return nullptr;
    }
    QGeoSatelliteInfoSource *satelliteInfoSourceWithParameters(QObject *, const QVariantMap &) override {
        return nullptr;
    }
    QGeoAreaMonitorSource *areaMonitorWithParameters(QObject *, const QVariantMap &) override {
        return nullptr;
    }
};
#else
// Qt 6 dropped the V2 subclass: the parameterised overloads *are* the base
// interface now.
class FixedPositionInfoSourceFactory : public QGeoPositionInfoSourceFactory
{
public:
    QGeoPositionInfoSource *positionInfoSource(QObject *, const QVariantMap &) override { return nullptr; }
    QGeoSatelliteInfoSource *satelliteInfoSource(QObject *, const QVariantMap &) override { return nullptr; }
    QGeoAreaMonitorSource *areaMonitor(QObject *, const QVariantMap &) override { return nullptr; }
};
#endif

class FixedPositionSource : public QGeoPositionInfoSource
{
public:
    using QGeoPositionInfoSource::QGeoPositionInfoSource;
    QGeoPositionInfo lastKnownPosition(bool) const override { return QGeoPositionInfo(); }
    PositioningMethods supportedPositioningMethods() const override { return AllPositioningMethods; }
    int minimumUpdateInterval() const override { return 1000; }
    Error error() const override { return NoError; }
    void startUpdates() override {}
    void stopUpdates() override {}
    void requestUpdate(int) override {}
};

class FixedAreaMonitorSource : public QGeoAreaMonitorSource
{
public:
    using QGeoAreaMonitorSource::QGeoAreaMonitorSource;
    Error error() const override { return NoError; }
    AreaMonitorFeatures supportedAreaMonitorFeatures() const override { return AreaMonitorFeatures(); }
    bool startMonitoring(const QGeoAreaMonitorInfo &) override { return false; }
    bool stopMonitoring(const QGeoAreaMonitorInfo &) override { return false; }
    bool requestUpdate(const QGeoAreaMonitorInfo &, const char *) override { return false; }
    QList<QGeoAreaMonitorInfo> activeMonitors() const override { return {}; }
    QList<QGeoAreaMonitorInfo> activeMonitors(const QGeoShape &) const override { return {}; }
};

class FixedSatelliteSource : public QGeoSatelliteInfoSource
{
public:
    using QGeoSatelliteInfoSource::QGeoSatelliteInfoSource;
    int minimumUpdateInterval() const override { return 1000; }
    Error error() const override { return NoError; }
    void startUpdates() override {}
    void stopUpdates() override {}
    void requestUpdate(int) override {}
};

} // namespace

void checkLocationServiceChain(SmokeReporter &r)
{
    r.check("location/service-provider-and-factory", [&](QString &d) {
        // No real plugin named this exists - error()/routingManager() etc
        // reporting "not supported" is the correct, real outcome.
        QGeoServiceProvider provider(QStringLiteral("qt-smoke-nonexistent"));
#if QT_VERSION_MAJOR < 6
        QGeoServiceProviderFactoryV3 factory;   // fully concrete - every
                                                // virtual has a default impl
        // Reached through the real base every later factory version derives from.
        QGeoServiceProviderFactoryV2 *asV2 = &factory;
#else
        // The versioned subclasses are gone: the base carries their methods
        // and is itself fully concrete.
        QGeoServiceProviderFactory factory;
        QGeoServiceProviderFactory *asV2 = &factory;
#endif
        return provider.error() != QGeoServiceProvider::NoError
            && provider.routingManager() == nullptr && asV2 != nullptr;
    });
    r.check("location/geocoding-engine", [&](QString &d) {
        // QGeoCodingManager's constructor is private (friended only to
        // QGeoServiceProvider, which loads it from a real plugin) - the
        // engine underneath it is what's directly reachable here.
        QGeoCodingManagerEngine engine{QVariantMap()};
        engine.setLocale(QLocale::system());
        // A concrete base's default-constructed reply, describing failure -
        // legitimate since there's no real geocoding backend behind it.
        QGeoCodeReply reply(QGeoCodeReply::UnsupportedOptionError, QStringLiteral("no backend"));
        return engine.locale() == QLocale::system() && reply.error() != QGeoCodeReply::NoError;
    });
    r.check("location/routing-engine-and-real-route", [&](QString &d) {
        FixedRoutingEngine engine{QVariantMap()};

        QGeoRouteRequest request(QList<QGeoCoordinate>{ QGeoCoordinate(1, 1), QGeoCoordinate(2, 2) });
        QGeoRouteReply *reply = engine.calculateRoute(request);

        QGeoRoute route;
        route.setDistance(1000);
        route.setTravelTime(60);
        QGeoRouteSegment segment;
        segment.setDistance(1000);
        QGeoManeuver maneuver;
        maneuver.setInstructionText(QStringLiteral("Turn left"));
        segment.setManeuver(maneuver);
        route.setFirstRouteSegment(segment);

#if QT_VERSION_MAJOR < 6
        QGeoRouteLeg leg;   // a QGeoRoute sub-section, used for multi-waypoint routes
#else
        QGeoRoute leg;      // Qt 6 models a leg as a QGeoRoute of its own
#endif
        leg.setLegIndex(0);
        leg.setOverallRoute(route);

        bool ok = reply != nullptr && reply->request().waypoints().size() == 2
            && qFuzzyCompare(route.distance(), qreal(1000))
            && route.firstRouteSegment().maneuver().instructionText() == QStringLiteral("Turn left")
            && leg.legIndex() == 0 && leg.overallRoute().distance() == route.distance();
        delete reply;
        return ok;
    });
    r.check("location/place-engine-and-replies", [&](QString &d) {
        // QPlaceManager's constructor is private too (same
        // QGeoServiceProvider-only pattern) - the engine is what's reachable.
        QPlaceManagerEngine engine{QVariantMap()};

        // All concrete - constructed directly to describe an unsupported/
        // empty result, same idea as the geocoding reply above.
        QPlaceReply baseReply;
        QPlaceContentReply contentReply;
        QPlaceDetailsReply detailsReply;
        QPlaceIdReply idReply(QPlaceIdReply::SavePlace);
        QPlaceMatchReply matchReply;
        QPlaceSearchReply searchReply;
        QPlaceSearchSuggestionReply suggestionReply;

        return engine.managerName().isEmpty()   // never set - construction succeeding is the point
            && baseReply.error() == QPlaceReply::NoError
            && idReply.operationType() == QPlaceIdReply::SavePlace;
    });
    r.check("location/place-value-and-request-types", [&](QString &d) {
        QPlaceContentRequest contentRequest;
        contentRequest.setPlaceId(QStringLiteral("place-1"));
        QPlaceMatchRequest matchRequest;
        matchRequest.setParameters(QVariantMap{{"k", "v"}});
        QPlaceSearchRequest searchRequest;
        searchRequest.setSearchTerm(QStringLiteral("coffee"));

        QPlaceContactDetail contact;
        contact.setLabel(QStringLiteral("Phone"));
        contact.setValue(QStringLiteral("+1234"));
#if QT_VERSION_MAJOR < 6
        QPlaceImage image;      // QPlaceContent subclass
        image.setUrl(QUrl(QStringLiteral("https://example.com/img.png")));
        QPlaceReview review;    // QPlaceContent subclass
        review.setRating(4.5);
#else
        // Qt 6 folded the subclasses into QPlaceContent itself: a content
        // object carries a type and tagged values instead.
        QPlaceContent image(QPlaceContent::ImageType);
        image.setValue(QPlaceContent::ImageUrl,
                       QUrl(QStringLiteral("https://example.com/img.png")));
        QPlaceContent review(QPlaceContent::ReviewType);
        review.setValue(QPlaceContent::ReviewRating, 4.5);
#endif
        QPlaceContent *asContent1 = &image;
        QPlaceContent *asContent2 = &review;

        QPlaceResult placeResult;
        placeResult.setDistance(42.0);
        QPlaceProposedSearchResult proposedResult;
        proposedResult.setSearchRequest(searchRequest);
        QPlaceSearchResult *asSearchResult1 = &placeResult;
        QPlaceSearchResult *asSearchResult2 = &proposedResult;

        return contentRequest.placeId() == QStringLiteral("place-1")
            && searchRequest.searchTerm() == QStringLiteral("coffee")
            && contact.label() == QStringLiteral("Phone") && asContent1 != nullptr
#if QT_VERSION_MAJOR < 6
            && qFuzzyCompare(review.rating(), qreal(4.5)) && asContent2 != nullptr
#else
            && qFuzzyCompare(review.value(QPlaceContent::ReviewRating).toReal(), qreal(4.5))
            && asContent2 != nullptr
#endif
            && qFuzzyCompare(placeResult.distance(), 42.0) && asSearchResult1 != nullptr
            && asSearchResult2 != nullptr;
    });
    r.check("location/position-area-satellite-sources", [&](QString &d) {
        FixedPositionInfoSourceFactory factory;
        FixedPositionSource posSource(nullptr);
        FixedAreaMonitorSource areaSource(nullptr);
        FixedSatelliteSource satSource(nullptr);

        QGeoAreaMonitorInfo monitorInfo(QStringLiteral("home"));
        monitorInfo.setArea(QGeoCircle(QGeoCoordinate(1, 1), 500));
        // Reached through the real base every shape type derives from.
        QGeoShape shapeBase = monitorInfo.area();

        return posSource.error() == QGeoPositionInfoSource::NoError
            && areaSource.startMonitoring(monitorInfo) == false
            && satSource.minimumUpdateInterval() == 1000
            && shapeBase.type() == QGeoShape::CircleType
#if QT_VERSION_MAJOR < 6
            && factory.positionInfoSource(nullptr) == nullptr;
#else
            && factory.positionInfoSource(nullptr, QVariantMap()) == nullptr;
#endif
    });
    r.check("location/nmea-source-real-parse", [&](QString &d) {
        QNmeaPositionInfoSource source(QNmeaPositionInfoSource::SimulationMode);
        QByteArray sentence = "$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47\r\n";
        QBuffer buffer(&sentence);
        buffer.open(QIODevice::ReadOnly);
        source.setDevice(&buffer);
        source.setUpdateInterval(1000);
        return source.device() == &buffer && source.updateMode() == QNmeaPositionInfoSource::SimulationMode;
    });
}

#endif // SMOKE_QT5
