// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// The Qt 6 additions to QtCore, QtGui, QtNetwork and QtOpenGL that the suite
// inherited no reason to name, plus QtVirtualKeyboard - a module this kit
// builds into every Qt 6 SDK and had never pointed anything at.
//
// The two platform-specific ones are guarded on the platform whose API they
// are: QWindowsMimeConverter takes Windows COM types in its signatures and
// QX11Application is a native interface that only exists in an X11 build.
#include "../common/smokecheck.h"

#include <QList>
#include <QMap>
#include <QVariant>

#if QT_VERSION_MAJOR >= 6
#include <QAssociativeIterable>
#include <QSequentialIterable>
#include <QPageRanges>
#include <QPdfOutputIntent>
#include <QPointerEvent>
#include <QMouseEvent>
#include <QSslDiffieHellmanParameters>
#include <QAccessible>
#endif

#if defined(SMOKE_CONSOLE_HAVE_OPENGL) && SMOKE_QT5
#include <QOpenGLVersionProfile>
// SMOKE_CONSOLE_HAVE_OPENGL says the SDK has QtOpenGL, which Qt 5 has too - it
// cannot decide this include. The factory is Qt 6's; on Qt 5 the same job was a
// QOpenGLContext method, so the version has to be asked separately.
#if QT_VERSION_MAJOR >= 6
#include <QOpenGLVersionFunctionsFactory>
#endif
#endif

#if QT_VERSION_MAJOR >= 6

#ifdef Q_OS_WIN
#include <QWindowsMimeConverter>
#include <objidl.h>
#endif

#ifdef Q_OS_UNIX
#include <QtGui/qguiapplication_platform.h>
#endif
#endif

#ifdef SMOKE_HAVE_VIRTUALKEYBOARD
#include <QVirtualKeyboardAbstractInputMethod>
#include <QVirtualKeyboardDictionary>
#include <QVirtualKeyboardDictionaryManager>
#include <QVirtualKeyboardInputContext>
#include <QVirtualKeyboardInputEngine>
#include <QVirtualKeyboardObserver>
#include <QVirtualKeyboardSelectionListModel>
#include <QVirtualKeyboardTrace>
#endif

#if QT_VERSION_MAJOR >= 6 && defined(Q_OS_WIN)
namespace {

// The converter a Windows application registers to teach Qt about a clipboard
// format Qt does not know. Every method is pure virtual, so a subclass is the
// only form the class takes.
class SmokeWindowsMime : public QWindowsMimeConverter
{
public:
    bool canConvertFromMime(const FORMATETC &, const QMimeData *) const override { return false; }
    bool convertFromMime(const FORMATETC &, const QMimeData *, STGMEDIUM *) const override
    { return false; }
    QList<FORMATETC> formatsForMime(const QString &, const QMimeData *) const override
    { return {}; }
    bool canConvertToMime(const QString &, IDataObject *) const override { return false; }
    QVariant convertToMime(const QString &, IDataObject *, QMetaType) const override
    { return QVariant(); }
    QString mimeForFormat(const FORMATETC &) const override { return QString(); }
};

} // namespace
#endif

void checkQt6QtBaseAdditions(SmokeReporter &r)
{
    r.check("core/mutable-container-iterators", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        // The const iterators are covered elsewhere; these are the mutable
        // ones, which is what a QVariant-based editor writes through.
        QList<int> numbers{ 1, 2, 3 };
        QMap<QString, int> lookup{ { QStringLiteral("a"), 1 } };

        QSequentialIterable sequence(&numbers);
        QAssociativeIterable association(&lookup);

        int walked = 0;
        // A mutable iterator dereferences to a QVariantRef proxy, which
        // converts to QVariant rather than being one.
        for (QSequentialIterator it = sequence.mutableBegin(); it != sequence.mutableEnd(); ++it)
            walked += QVariant(*it).toInt();

        int pairs = 0;
        for (QAssociativeIterator it = association.mutableBegin();
             it != association.mutableEnd(); ++it)
            ++pairs;

        int constPairs = 0;
        for (QAssociativeConstIterator it = association.constBegin();
             it != association.constEnd(); ++it)
            ++constPairs;

        QStringList misses;
        if (walked != 6) misses << QStringLiteral("sequentialiterator");
        if (pairs != 1) misses << QStringLiteral("associativeiterator");
        if (constPairs != 1) misses << QStringLiteral("associativeconstiterator");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("the container iterators are Qt 6 only"));
        return false;
#endif
    });

    r.check("gui/page-ranges-pdf-intent-and-pointer-events", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        QPageRanges ranges;
        ranges.addPage(1);
        ranges.addRange(3, 5);

        QPdfOutputIntent intent;
        intent.setOutputConditionIdentifier(QStringLiteral("sRGB"));
        intent.setOutputCondition(QStringLiteral("qt-smoke"));

        // Every mouse, tablet and touch event in Qt 6 is a QPointerEvent, and
        // the single-point ones a QSinglePointEvent - two bases Qt 5 did not
        // have and that the existing event checks therefore never named.
        QMouseEvent mouse(QEvent::MouseButtonPress, QPointF(3, 4), QPointF(3, 4),
                          Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        QSinglePointEvent *singlePoint = &mouse;
        QPointerEvent *pointer = &mouse;

        QObject announcer;
        QAccessibleAnnouncementEvent announcement(&announcer, QStringLiteral("ready"));

        QStringList misses;
        if (!ranges.contains(4) || ranges.firstPage() != 1) misses << QStringLiteral("pageranges");
        if (ranges.toString() != QStringLiteral("1,3-5")) misses << QStringLiteral("ranges-string");
        if (intent.outputConditionIdentifier() != QStringLiteral("sRGB"))
            misses << QStringLiteral("pdfoutputintent");
        if (singlePoint->button() != Qt::LeftButton) misses << QStringLiteral("singlepointevent");
        if (pointer->pointCount() != 1) misses << QStringLiteral("pointerevent");
        if (announcement.message() != QStringLiteral("ready"))
            misses << QStringLiteral("announcement");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("these classes are Qt 6 only"));
        return false;
#endif
    });

    r.check("net/diffie-hellman-parameters", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        const QSslDiffieHellmanParameters defaults =
            QSslDiffieHellmanParameters::defaultParameters();
        QSslDiffieHellmanParameters empty;
        const QSslDiffieHellmanParameters bad =
            QSslDiffieHellmanParameters::fromEncoded(QByteArrayLiteral("not-a-dh-parameter"));

        Q_UNUSED(defaults);
        if (!empty.isEmpty()) {
            d = QStringLiteral("a default-constructed parameter set was not empty");
            return false;
        }
        // Schannel has no Diffie-Hellman parameter support at all, so it
        // rejects the garbage by ignoring it rather than by reporting an
        // error. That is the backend, not the API.
        if (bad.error() == QSslDiffieHellmanParameters::NoError) {
            r.skip(d, QStringLiteral("this TLS backend does not support DH parameters"));
            return false;
        }
        bool ok = !bad.isValid();
        if (!ok)
            d = QStringLiteral("garbage DH parameters were accepted");
        return ok;
#else
        r.skip(d, QStringLiteral("QSslDiffieHellmanParameters is covered on Qt 6 here"));
        return false;
#endif
    });

    r.check("opengl/version-functions-factory", [&](QString &d) {
#if defined(SMOKE_CONSOLE_HAVE_OPENGL) && SMOKE_QT5
        // The profile a caller asks for; it exists in both versions.
        QOpenGLVersionProfile profile;
        profile.setVersion(2, 0);
        if (profile.version().first != 2) {
            d = QStringLiteral("the version profile did not keep its version");
            return false;
        }
#if QT_VERSION_MAJOR >= 6
        // The factory that hands out a QOpenGLFunctions_N_M for a profile. It
        // needs a current context, and this app has none - a null result is
        // the documented answer, not a failure.
        QAbstractOpenGLFunctions *functions =
            QOpenGLVersionFunctionsFactory::get(profile, nullptr);
        if (functions) {
            d = QStringLiteral("got functions with no current context");
            return false;
        }
#endif
        return true;
#else
        r.skip(d, QStringLiteral("QtOpenGL is not in this SDK"));
        return false;
#endif
    });

    r.check("platform/native-mime-and-application-interfaces", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6 && defined(Q_OS_WIN)
        SmokeWindowsMime converter;
        QWindowsMimeConverter *converterBase = &converter;
        bool ok = !converterBase->canConvertToMime(QStringLiteral("text/plain"), nullptr)
            && converterBase->formatsForMime(QStringLiteral("text/plain"), nullptr).isEmpty();
        if (!ok)
            d = QStringLiteral("the Windows MIME converter answered unexpectedly");
        return ok;
#elif QT_VERSION_MAJOR >= 6 && defined(Q_OS_UNIX)
        // QX11Application exists only in an X11 build and works only under the xcb
        // plugin: under offscreen it is handed out with a null display and connection.
        auto *x11 = qGuiApp->nativeInterface<QNativeInterface::QX11Application>();
        if (!x11 || (x11->display() == nullptr && x11->connection() == nullptr)) {
            r.skip(d, QStringLiteral("not running on the xcb platform plugin"));
            return false;
        }
        return x11->display() != nullptr || x11->connection() != nullptr;
#else
        r.skip(d, QStringLiteral("no native application interface on this platform"));
        return false;
#endif
    });

    r.check("virtualkeyboard/input-context-engine-and-dictionaries", [&](QString &d) {
#ifdef SMOKE_HAVE_VIRTUALKEYBOARD
        // The C++ side of QtVirtualKeyboard needs no QML engine to construct;
        // what needs one is the keyboard UI, which is not what these are.
        QVirtualKeyboardInputContext inputContext;
        QVirtualKeyboardInputEngine *engine = inputContext.inputEngine();
        QVirtualKeyboardObserver observer;

        QVirtualKeyboardDictionaryManager *dictionaries =
            QVirtualKeyboardDictionaryManager::instance();
        QVirtualKeyboardDictionary *dictionary =
            dictionaries ? dictionaries->createDictionary(QStringLiteral("qt-smoke")) : nullptr;
        if (dictionary)
            dictionary->setContents({ QStringLiteral("qt"), QStringLiteral("smoke") });

        QVirtualKeyboardTrace trace;
        trace.setChannels({ QStringLiteral("t") });
        trace.addPoint(QPointF(1, 2));

        QStringList misses;
        if (inputContext.isShiftActive()) misses << QStringLiteral("inputcontext");
        if (engine == nullptr) misses << QStringLiteral("inputengine");
        if (observer.layout().isValid() && observer.layout().isNull())
            misses << QStringLiteral("observer");
        if (dictionaries == nullptr) misses << QStringLiteral("dictionarymanager");
        if (dictionary && dictionary->contents().size() != 2)
            misses << QStringLiteral("dictionary");
        if (trace.length() != 1) misses << QStringLiteral("trace");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("no QtVirtualKeyboard with the Qt 6 class names here"));
        return false;
#endif
    });
}
