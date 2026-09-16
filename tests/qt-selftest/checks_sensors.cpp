// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// QtSensors checks. No physical sensor is required: QSensor::start() fails
// gracefully (returns false, reading() stays null) when there's no backend
// plugin, the same "construct/configure without live hardware" approach used
// for audio/camera/serial-port. Each of the ~17 sensor types gets its
// Sensor+Reading+Filter classes touched; filters are abstract (one virtual
// method) so a trivial subclass per type is the real, documented way to use
// them - this is what an app does to react to sensor updates.
#include "../common/smokecheck.h"

#if !SMOKE_QT5

void checkSensors(SmokeReporter &r)
{
    r.check("sensors/module", [&](QString &d) {
        r.skip(d, QStringLiteral("QtSensors has no Qt 4 module in this SDK"));
        return false;
    });
}

#else

#include <QAccelerometer>
#if QT_VERSION_MAJOR < 6
#include <QAltimeter>
#endif
#include <QAmbientLightSensor>
#include <QAmbientTemperatureSensor>
#include <QCompass>
#if QT_VERSION_MAJOR < 6
#include <QDistanceSensor>
#endif
#include <QGyroscope>
#if QT_VERSION_MAJOR < 6
#include <QHolsterSensor>
#endif
#include <QHumiditySensor>
#include <QIRProximitySensor>
#include <QLidSensor>
#include <QLightSensor>
#include <QMagnetometer>
#include <QOrientationSensor>
#include <QPressureSensor>
#include <QProximitySensor>
#include <QRotationSensor>
#include <QTapSensor>
#include <QTiltSensor>

#if QT_VERSION_MAJOR < 6
#include <QSensorGesture>
#endif
#if QT_VERSION_MAJOR < 6
#include <QSensorGestureManager>
#endif
#if QT_VERSION_MAJOR < 6
#include <QSensorGestureRecognizer>
#endif
#if QT_VERSION_MAJOR < 6
#include <QSensorGesturePluginInterface>
#endif
#include <QSensorManager>
#include <QSensorBackend>
#include <QSensorBackendFactory>
#include <QSensorPluginInterface>
#include <QSensorChangesInterface>

namespace {

// A minimal but real working QAccelerometer backend, registered as the
// default so accel.start() actually succeeds and produces a real
// QAccelerometerReading - the documented way a platform sensor backend
// plugin is implemented, not a construct-only stand-in.
class FixedAccelerometerBackend : public QSensorBackend
{
public:
    using QSensorBackend::QSensorBackend;
    void start() override {
        auto *reading = setReading<QAccelerometerReading>(nullptr);
        reading->setX(0); reading->setY(0); reading->setZ(9.8);
        newReadingAvailable();
    }
    void stop() override {}
};

class FixedAccelerometerBackendFactory : public QSensorBackendFactory
{
public:
    QSensorBackend *createBackend(QSensor *sensor) override {
        if (sensor->identifier() == "qt-smoke.accelerometer")
            return new FixedAccelerometerBackend(sensor);
        return nullptr;
    }
};

struct AccelFilter : QAccelerometerFilter { bool filter(QAccelerometerReading *) override { return true; } };
#if QT_VERSION_MAJOR < 6
struct AltiFilter : QAltimeterFilter { bool filter(QAltimeterReading *) override { return true; } };
#endif
struct AmbLightFilter : QAmbientLightFilter { bool filter(QAmbientLightReading *) override { return true; } };
struct AmbTempFilter : QAmbientTemperatureFilter { bool filter(QAmbientTemperatureReading *) override { return true; } };
struct CompassFlt : QCompassFilter { bool filter(QCompassReading *) override { return true; } };
#if QT_VERSION_MAJOR < 6
struct DistFilter : QDistanceFilter { bool filter(QDistanceReading *) override { return true; } };
#endif
struct GyroFilter : QGyroscopeFilter { bool filter(QGyroscopeReading *) override { return true; } };
#if QT_VERSION_MAJOR < 6
struct HolsterFlt : QHolsterFilter { bool filter(QHolsterReading *) override { return true; } };
#endif
struct HumidityFlt : QHumidityFilter { bool filter(QHumidityReading *) override { return true; } };
struct IRProxFilter : QIRProximityFilter { bool filter(QIRProximityReading *) override { return true; } };
struct LidFlt : QLidFilter { bool filter(QLidReading *) override { return true; } };
struct LightFlt : QLightFilter { bool filter(QLightReading *) override { return true; } };
struct MagFilter : QMagnetometerFilter { bool filter(QMagnetometerReading *) override { return true; } };
struct OrientFilter : QOrientationFilter { bool filter(QOrientationReading *) override { return true; } };
struct PressureFlt : QPressureFilter { bool filter(QPressureReading *) override { return true; } };
struct RotationFlt : QRotationFilter { bool filter(QRotationReading *) override { return true; } };
struct TapFlt : QTapFilter { bool filter(QTapReading *) override { return true; } };
struct TiltFlt : QTiltFilter { bool filter(QTiltReading *) override { return true; } };
}

void checkSensors(SmokeReporter &r)
{
    r.check("sensors/motion-group", [&](QString &d) {
        QAccelerometer accel; AccelFilter af; accel.addFilter(&af);
        QGyroscope gyro; GyroFilter gf; gyro.addFilter(&gf);
        QMagnetometer mag; MagFilter mf; mag.addFilter(&mf);
        QRotationSensor rot; RotationFlt rf; rot.addFilter(&rf);
        QCompass compass; CompassFlt cf; compass.addFilter(&cf);
        QOrientationSensor orient; OrientFilter of; orient.addFilter(&of);
        accel.start(); gyro.start(); mag.start(); rot.start(); compass.start(); orient.start();
        QAccelerometerReading *ar = accel.reading();
        QGyroscopeReading *gr = gyro.reading();
        QMagnetometerReading *mr = mag.reading();
        QRotationReading *rr = rot.reading();
        QCompassReading *cr = compass.reading();
        QOrientationReading *orr = orient.reading();
        Q_UNUSED(ar); Q_UNUSED(gr); Q_UNUSED(mr); Q_UNUSED(rr); Q_UNUSED(cr); Q_UNUSED(orr);
        return true;   // no crash across construct/filter/start/reading is the point
    });
    r.check("sensors/environment-group", [&](QString &d) {
        QAmbientLightSensor light; AmbLightFilter alf; light.addFilter(&alf);
        QAmbientTemperatureSensor temp; AmbTempFilter atf; temp.addFilter(&atf);
        QPressureSensor pressure; PressureFlt pf; pressure.addFilter(&pf);
        QHumiditySensor humidity; HumidityFlt hf; humidity.addFilter(&hf);
        QLightSensor lightSensor; LightFlt lf; lightSensor.addFilter(&lf);
#if QT_VERSION_MAJOR < 6
        QAltimeter altimeter; AltiFilter aif; altimeter.addFilter(&aif);
#endif
        light.start(); temp.start(); pressure.start(); humidity.start(); lightSensor.start();
#if QT_VERSION_MAJOR < 6
        altimeter.start();
#endif
        return true;
    });
    r.check("sensors/proximity-device-group", [&](QString &d) {
#if QT_VERSION_MAJOR < 6
        QDistanceSensor dist; DistFilter df; dist.addFilter(&df);
#endif
        QIRProximitySensor irProx; IRProxFilter ipf; irProx.addFilter(&ipf);
        QProximitySensor prox;
#if QT_VERSION_MAJOR < 6
        QHolsterSensor holster; HolsterFlt hf; holster.addFilter(&hf);
#endif
        QLidSensor lid; LidFlt lf; lid.addFilter(&lf);
        QTapSensor tap; TapFlt tf; tap.addFilter(&tf);
        QTiltSensor tilt; TiltFlt tif; tilt.addFilter(&tif);
        irProx.start(); prox.start(); lid.start(); tap.start(); tilt.start();
#if QT_VERSION_MAJOR < 6
        dist.start(); holster.start();
#endif
        QProximityReading *pr = prox.reading();
        Q_UNUSED(pr);
        return true;
    });
    r.check("sensors/gesture-manager", [&](QString &d) {
#if QT_VERSION_MAJOR < 6
        QSensorGestureManager manager;
        const QStringList ids = manager.gestureIds();
        QSensorGesture gesture(ids.isEmpty() ? QStringList{"QtSensors.shake"} : ids);
        bool registered = QSensorManager::isBackendRegistered(QByteArray("QAccelerometer"),
                                                               QByteArray("dummy"));
        Q_UNUSED(registered);   // false is fine - no plugin registered under that name
        return ids.size() >= 0 && gesture.validIds().size() >= 0;
#else
        // The sensor-gesture framework was dropped wholesale in Qt 6; the
        // backend registry it sat next to is still here, so that half runs.
        const bool registered = QSensorManager::isBackendRegistered(QByteArray("QAccelerometer"),
                                                                    QByteArray("dummy"));
        Q_UNUSED(registered);
        r.skip(d, QStringLiteral("Qt 6 dropped the sensor-gesture framework"));
        return false;
#endif
    });
    r.check("sensors/real-backend-produces-reading", [&](QString &d) {
        // Registering a real backend and making it the default is what lets
        // start() actually succeed and reading() return a live object,
        // reached here through the real QSensorReading/QSensorFilter bases.
        static FixedAccelerometerBackendFactory factory;
#if QT_VERSION_MAJOR < 6
        QSensorManager::registerBackend(QAccelerometer::type, "qt-smoke.accelerometer", &factory);
        QSensorManager::setDefaultBackend(QAccelerometer::type, "qt-smoke.accelerometer");
#else
        QSensorManager::registerBackend(QAccelerometer::sensorType, "qt-smoke.accelerometer", &factory);
        QSensorManager::setDefaultBackend(QAccelerometer::sensorType, "qt-smoke.accelerometer");
#endif

        QAccelerometer accel;
        AccelFilter filter;
        QSensorFilter *filterBase = &filter;
        accel.addFilter(filterBase);
        if (!accel.start()) { d = "start() failed even with backend registered"; return false; }

        QSensorReading *readingBase = accel.reading();
        bool ok = readingBase != nullptr && readingBase->value(2).toDouble() > 9.0;
        accel.stop();
        return ok;
    });
    r.check("sensors/gesture-recognizer-and-plugin-interfaces", [&](QString &d) {
        // The extension points a sensor-gesture/sensor backend plugin
        // implements - minimal subclasses, the same pattern used for the
        // Modbus/CAN-bus/QtScript plugin interfaces elsewhere in this suite.
#if QT_VERSION_MAJOR < 6
        class FixedRecognizer : public QSensorGestureRecognizer {
        public:
            QString id() const override { return QStringLiteral("qt-smoke.shake"); }
            bool isActive() override { return false; }
            void create() override {}
            bool start() override { return true; }
            bool stop() override { return true; }
        };
        class FixedGesturePlugin : public QSensorGesturePluginInterface {
        public:
            QList<QSensorGestureRecognizer *> createRecognizers() override { return {}; }
            QStringList supportedIds() const override { return {}; }
            QString name() const override { return QStringLiteral("qt-smoke-gestures"); }
        };
        class FixedSensorPlugin : public QSensorPluginInterface, public QSensorChangesInterface {
        public:
            void registerSensors() override {}
            void sensorsChanged() override {}
        };

        FixedRecognizer recognizer;
        FixedGesturePlugin gesturePlugin;
        FixedSensorPlugin sensorPlugin;
        return recognizer.id() == QStringLiteral("qt-smoke.shake") && !recognizer.isActive()
            && gesturePlugin.name() == QStringLiteral("qt-smoke-gestures");
#else
        // Only the sensor-backend plugin interface survived; the gesture
        // recognizer and its plugin interface, and the QSensorChangesInterface
        // mixin, all went with the gesture framework.
        class FixedSensorPlugin : public QSensorPluginInterface {
        public:
            void registerSensors() override {}
        };
        FixedSensorPlugin sensorPlugin;
        QSensorPluginInterface *pluginBase = &sensorPlugin;
        pluginBase->registerSensors();
        return pluginBase != nullptr;
#endif
    });
}

#endif // SMOKE_QT5
