// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef LONGREACH_COMPASS_HEADING_H
#define LONGREACH_COMPASS_HEADING_H

// Explicit Qt5 Android extended/full diagnostic. The host must apply and
// read back the chosen nonzero native sensor vectors before launching it.
#include "../common/smokecheck.h"
#include <QAccelerometer>
#include <QCompass>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QMagnetometer>
#include <QThread>
#include <cmath>

namespace SmokeCompassHeading {

inline int run(const QString &direction)
{
    bool valid = false;
    const int expected = direction.toInt(&valid);
    if (!valid || !QStringList({"0", "45", "90", "180", "270"}).contains(direction))
        return 2;

    // Constant fixtures, independent of the backend's rotation-matrix code.
    // Acceleration is (0,0,9.81)m/s^2. Magnetic values here are in microteslas;
    // QMagnetometerReading exposes teslas. All five fields are nonzero vectors.
    double magneticX = 0.0, magneticY = 20.0;
    if (expected == 45) magneticX = -20.0;
    if (expected == 90) { magneticX = -20.0; magneticY = 0.0; }
    if (expected == 180) magneticY = -20.0;
    if (expected == 270) { magneticX = 20.0; magneticY = 0.0; }

    SmokeReporter r("compass-heading");
    r.check("compass/native-backends", [&](QString &detail) {
        const bool found = QSensor::sensorsForType(QAccelerometer::type).contains("1")
                && QSensor::sensorsForType(QMagnetometer::type).contains("2")
                && QSensor::sensorsForType(QCompass::type).contains("android.synthetic.compass");
        detail = QStringLiteral("Requires native acceleration1, magnetic2 and Android synthetic compass");
        return found;
    });
    if (r.failed()) return r.summary();

    QAccelerometer acceleration;
    QMagnetometer magnetic;
    QCompass compass;
    acceleration.setIdentifier("1");
    magnetic.setIdentifier("2");
    compass.setIdentifier("android.synthetic.compass");
    for (QSensor *sensor : {static_cast<QSensor *>(&acceleration),
                           static_cast<QSensor *>(&magnetic), static_cast<QSensor *>(&compass)}) {
        sensor->setDataRate(50);
        sensor->setSkipDuplicates(false);
    }
    int accelerationSamples = 0, magneticSamples = 0, compassSamples = 0;
    QStringList accepted;
    QElapsedTimer clock;
    clock.start();
    QObject::connect(&acceleration, &QSensor::readingChanged, &acceleration,
                     [&] { ++accelerationSamples; });
    QObject::connect(&magnetic, &QSensor::readingChanged, &magnetic,
                     [&] { ++magneticSamples; });
    QObject::connect(&compass, &QSensor::readingChanged, &compass, [&] {
        ++compassSamples;
        if (accepted.size() >= 5) return;
        const auto a = acceleration.reading();
        const auto m = magnetic.reading();
        const auto c = compass.reading();
        if (!accelerationSamples || !magneticSamples || !a || !m || !c) return;
        const auto near = [](double actual, double wanted, double tolerance) {
            return std::isfinite(actual) && std::abs(actual - wanted) <= tolerance;
        };
        const bool vectors = near(a->x(), 0.0, 0.2) && near(a->y(), 0.0, 0.2)
                && near(a->z(), 9.81, 0.2) && near(m->x(), magneticX * 1e-6, 0.2e-6)
                && near(m->y(), magneticY * 1e-6, 0.2e-6) && near(m->z(), -40e-6, 0.2e-6);
        // Compare directions modulo a turn. Preserve the raw azimuth below;
        // this does not establish a particular raw-angle output range.
        const double error = std::abs(std::remainder(double(c->azimuth()) - expected, 360.0));
        const bool heading = std::isfinite(c->azimuth()) && std::isfinite(error) && error <= 2.0;
        const bool calibration = std::isfinite(c->calibrationLevel())
                && c->calibrationLevel() >= 0.0 && c->calibrationLevel() <= 1.0;
        if (!vectors || !heading || !calibration) { accepted.clear(); return; }
        accepted << QStringLiteral("expected=%1 azimuth=%2 calibration=%3 accel=%4:%5:%6 magnetic=%7:%8:%9 elapsed_ms=%10 native_stamp=%11")
                .arg(expected).arg(c->azimuth(), 0, 'g', 12).arg(c->calibrationLevel(), 0, 'g', 12)
                .arg(a->x(), 0, 'g', 12).arg(a->y(), 0, 'g', 12).arg(a->z(), 0, 'g', 12)
                .arg(m->x(), 0, 'g', 12).arg(m->y(), 0, 'g', 12).arg(m->z(), 0, 'g', 12)
                .arg(clock.elapsed()).arg(c->timestamp());
    });

    bool started = false;
    r.check("compass/native-streams", [&](QString &detail) {
        const bool a = acceleration.start(), m = magnetic.start(), c = compass.start();
        started = a && m && c && acceleration.isActive() && magnetic.isActive() && compass.isActive();
        detail = QStringLiteral("start=%1:%2:%3 errors=%4:%5:%6")
                .arg(a).arg(m).arg(c).arg(acceleration.error()).arg(magnetic.error()).arg(compass.error());
        r.observe("compass/streams", detail);
        return started;
    });
    r.check("compass/known-heading", [&](QString &detail) {
        QElapsedTimer deadline;
        deadline.start();
        while (started && accepted.size() < 5 && deadline.elapsed() < 12000) {
            QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
            QThread::msleep(5);
        }
        detail = QStringLiteral("expected=%1 acceleration_samples=%2 magnetic_samples=%3 compass_samples=%4 consecutive=%5")
                .arg(expected).arg(accelerationSamples).arg(magneticSamples).arg(compassSamples).arg(accepted.size());
        r.observe("compass/counts", detail);
        for (const auto &sample : accepted) r.observe("compass/sample", sample);
        if (const auto a = acceleration.reading())
            r.observe("compass/last-acceleration", QStringLiteral("%1:%2:%3").arg(a->x(),0,'g',12).arg(a->y(),0,'g',12).arg(a->z(),0,'g',12));
        if (const auto m = magnetic.reading())
            r.observe("compass/last-magnetic", QStringLiteral("%1:%2:%3").arg(m->x(),0,'g',12).arg(m->y(),0,'g',12).arg(m->z(),0,'g',12));
        if (const auto c = compass.reading())
            r.observe("compass/last-heading", QStringLiteral("azimuth=%1 calibration=%2 native_stamp=%3")
                      .arg(c->azimuth(),0,'g',12).arg(c->calibrationLevel(),0,'g',12).arg(c->timestamp()));
        return started && accepted.size() == 5;
    });
    r.check("compass/stop", [&](QString &) {
        compass.stop(); magnetic.stop(); acceleration.stop();
        return !compass.isActive() && !magnetic.isActive() && !acceleration.isActive();
    });
    return r.summary();
}

} // namespace SmokeCompassHeading
#endif
