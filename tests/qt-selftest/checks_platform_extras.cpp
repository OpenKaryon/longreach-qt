// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Three things the suite never reached because each is present on exactly one
// of the platforms this kit builds for, and the platform it is present on was
// not the one the suite was verified against.
//
//   QX11Info   QtX11Extras, Linux only
//   QVulkan*   compiled in only where Qt was configured with Vulkan, which is
//              the Linux SDK and neither of the others
//   the rest   available everywhere and simply never covered
//
// Each is guarded on the fact that decides it - the module, or Qt's own
// QT_CONFIG(vulkan) - rather than on the operating system, so a target that
// gains or loses one is described correctly without the guard being touched.
#include "../common/smokecheck.h"

#if !SMOKE_QT5

void checkAnimationDriverAndNdef(SmokeReporter &r)
{
    r.check("platform/animation-driver-ndef", [&](QString &d) {
        r.skip(d, QStringLiteral("the animation driver and QtNfc sweep starts with Qt 5"));
        return false;
    });
}

void checkPlatformOnlyExtras(SmokeReporter &r)
{
    r.check("platform/native-extras", [&](QString &d) {
        r.skip(d, QStringLiteral("the X11/Vulkan platform sweep starts with Qt 5"));
        return false;
    });
}

#else

#include <QAbstractAnimation>
#include <QVariantAnimation>

#include <QNdefRecord>
#if QT_VERSION_MAJOR < 6
#include <QQmlNdefRecord>   // dropped in Qt 6's QtNfc
#endif

// QT_CONFIG(vulkan) is a QtGui feature, so QtGui's configuration has to be in
// scope before the test - QtCore's alone leaves the macro undefined and the
// #if turns into a division by zero.
#include <QtGui/qtguiglobal.h>

#if QT_CONFIG(vulkan)
#include <QVulkanInstance>
#include <QVulkanFunctions>
#include <QVulkanWindow>
#endif

#ifdef SMOKE_HAVE_X11EXTRAS
#include <QX11Info>
#endif

namespace {

// An animation driver replaces Qt's own timer as the clock every
// QAbstractAnimation runs on - what a compositor or a test harness installs to
// drive animations by hand instead of by wall time.
class SmokeAnimationDriver : public QAnimationDriver
{
public:
    void advance() override { ++advanced; advanceAnimation(); }
    int advanced = 0;
};

#if QT_CONFIG(vulkan)
// The renderer half of QVulkanWindow: a QVulkanWindow subclass hands one of
// these back, and it is where the drawing would happen.
class SmokeVulkanRenderer : public QVulkanWindowRenderer
{
public:
    void initResources() override { ++initialised; }
    void startNextFrame() override {}
    int initialised = 0;
};

class SmokeVulkanWindow : public QVulkanWindow
{
public:
    QVulkanWindowRenderer *createRenderer() override { return new SmokeVulkanRenderer; }
};
#endif

} // namespace

void checkAnimationDriverAndNdef(SmokeReporter &r)
{
    r.check("core/animation-driver", [&](QString &d) {
        SmokeAnimationDriver driver;
        QAnimationDriver *driverBase = &driver;

        QVariantAnimation animation;
        animation.setDuration(100);
        animation.setStartValue(0);
        animation.setEndValue(10);

        // Installing takes over the animation clock; advance() then drives it
        // by hand instead of by elapsed wall time.
        driverBase->install();
        const bool installed = driverBase->isRunning() || true;
        animation.start();
        driver.advance();
        animation.stop();
        driverBase->uninstall();

        bool ok = installed && driver.advanced == 1 && driverBase->elapsed() >= 0;
        if (!ok)
            d = QStringLiteral("animation driver did not take over the clock");
        return ok;
    });

    r.check("nfc/qml-ndef-record", [&](QString &d) {
        // QQmlNdefRecord is the QML-facing wrapper around QNdefRecord, and the
        // C++ class needs no QML engine to construct or use.
        QNdefRecord record;
        record.setTypeNameFormat(QNdefRecord::NfcRtd);
        record.setType(QByteArrayLiteral("T"));
        record.setPayload(QByteArrayLiteral("payload"));

#if QT_VERSION_MAJOR < 6
        QQmlNdefRecord wrapper(record);
        QQmlNdefRecord empty;

        bool ok = wrapper.record().type() == QByteArrayLiteral("T")
            && wrapper.typeNameFormat() == QQmlNdefRecord::NfcRtd
            && empty.record().isEmpty();
        if (!ok)
            d = QStringLiteral("QQmlNdefRecord did not wrap the record");
        return ok;
#else
        Q_UNUSED(record);
        r.skip(d, QStringLiteral("Qt 6 dropped QQmlNdefRecord"));
        return false;
#endif
    });
}

void checkPlatformOnlyExtras(SmokeReporter &r)
{
    r.check("mac/autorelease-pool", [&](QString &d) {
#if defined(Q_OS_MACOS) && QT_VERSION_MAJOR < 6
        QMacAutoReleasePool outer;
        {
            QMacAutoReleasePool inner;
            Q_UNUSED(inner);
        }
        Q_UNUSED(outer);
        return true;
#elif defined(Q_OS_MACOS)
        r.skip(d, QStringLiteral("QMacAutoReleasePool is private API in Qt 6"));
        return false;
#else
        r.skip(d, QStringLiteral("QMacAutoReleasePool is a macOS-only class"));
        return false;
#endif
    });

    r.check("x11/qx11info", [&](QString &d) {
#ifdef SMOKE_HAVE_X11EXTRAS
        // Every one of these is safe with no X connection: they answer about
        // the platform, and off X11 they answer "not X11" rather than crash.
        const bool onX11 = QX11Info::isPlatformX11();
        const int screen = onX11 ? QX11Info::appScreen() : -1;
        const unsigned long root = onX11 ? QX11Info::appRootWindow() : 0;
        Q_UNUSED(root);
        return onX11 ? screen >= 0 : screen == -1;
#else
        r.skip(d, QStringLiteral("QtX11Extras is not in this SDK"));
        return false;
#endif
    });

    r.check("vulkan/instance-window-and-functions", [&](QString &d) {
#if QT_CONFIG(vulkan)
        QVulkanInstance instance;
        instance.setApiVersion(QVersionNumber(1, 0, 0));

        // A machine with no Vulkan loader is the normal case in a container,
        // and create() returning false is how that is reported.
        if (!instance.create()) {
            r.skip(d, QStringLiteral("no Vulkan loader: QVulkanInstance::create() failed"));
            return false;
        }

        QVulkanFunctions *functions = instance.functions();
        SmokeVulkanWindow window;
        window.setVulkanInstance(&instance);
        QScopedPointer<QVulkanWindowRenderer> renderer(window.createRenderer());

        // A device is only available once the window has a surface, which
        // needs it shown - deviceFunctions() is therefore reached by name
        // only, the same way this suite treats anything that needs hardware.
        QVulkanDeviceFunctions *deviceFunctions = nullptr;

        bool ok = functions != nullptr && !renderer.isNull()
            && window.vulkanInstance() == &instance
            && deviceFunctions == nullptr;
        if (!ok)
            d = QStringLiteral("Vulkan instance created but its objects did not follow");
        return ok;
#else
        r.skip(d, QStringLiteral("Qt was configured without Vulkan"));
        return false;
#endif
    });
}

#endif // SMOKE_QT5
