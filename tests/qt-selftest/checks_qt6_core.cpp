// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// The Qt 6 additions to QtCore, QtNetwork and QtGui that the suite carried
// over from Qt 5 and therefore never had a reason to touch: the bindable
// property system, the type-erased container metatypes, and a handful of
// classes that simply did not exist before.
//
// Everything here is headless and needs no backend. QNetworkInformation is the
// one exception and it says so: loading a backend depends on the platform
// plugin being present, so a failure to load is reported as a SKIP.
#include "../common/smokecheck.h"

#include <QByteArray>
#include <QList>
#include <QMap>
#include <QMetaType>
#include <QObject>
#include <QVariant>

#if QT_VERSION_MAJOR >= 6
#include <QBindable>
#include <QByteArrayView>
#include <QAssociativeIterable>
#include <QMetaContainer>
#include <QMetaSequence>
#include <QSequentialIterable>
#include <QProperty>
#include <QRecursiveMutex>

#include <QNetworkAccessManager>
#include <QNetworkInformation>
#include <QRestAccessManager>
#include <QRestReply>
#include <QSslServer>
#endif

#if QT_VERSION_MAJOR >= 6 && QT_VERSION_MINOR >= 8
#include <QChronoTimer>
#endif

void checkQt6PropertySystem(SmokeReporter &r)
{
    r.check("core/bindable-property-system", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        // The Qt 6 property system: a QProperty holding a value, a second one
        // bound to an expression over the first, and the binding machinery
        // underneath both.
        QProperty<int> width(4);
        QProperty<int> area;
        area.setBinding([&]() { return width.value() * 2; });

        const int beforeChange = area.value();
        width = 10;
        const int afterChange = area.value();

        QUntypedPropertyBinding untypedBinding = area.binding();
        QPropertyBindingError bindingError;

        int observed = 0;
        QPropertyChangeHandler handler = area.onValueChanged([&observed]() { ++observed; });
        width = 20;

        QBindable<int> bindable(&area);

        // Every QObject carries one of these; it is what stores the bindings
        // of its Q_PROPERTY(... BINDABLE ...) members.
        QObject owner;
        const QBindingStorage *storage = owner.bindingStorage();

        QStringList misses;
        if (beforeChange != 8 || afterChange != 20) misses << QStringLiteral("binding");
        if (untypedBinding.isNull()) misses << QStringLiteral("untypedbinding");
        if (bindingError.type() != QPropertyBindingError::NoError)
            misses << QStringLiteral("bindingerror");
        if (observed != 1) misses << QStringLiteral("changehandler");
        if (!bindable.hasBinding()) misses << QStringLiteral("bindable");
        if (storage == nullptr) misses << QStringLiteral("bindingstorage");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("the bindable property system is Qt 6 only"));
        return false;
#endif
    });

    r.check("core/container-metatypes", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        // QMetaSequence and QMetaAssociation describe a container's shape to
        // code that has only a void* and a metatype - what QVariant and QML
        // use to iterate a container they were never compiled against.
        QList<int> numbers{ 1, 2, 3 };
        QMap<QString, int> lookup{ { QStringLiteral("a"), 1 } };

        QMetaSequence sequence = QMetaSequence::fromContainer<QList<int>>();
        QMetaAssociation association = QMetaAssociation::fromContainer<QMap<QString, int>>();
        const QMetaContainer *sequenceBase = &sequence;

        // Built straight from the container: going through QVariant needs a
        // registered converter for the exact type and gives an empty iterable
        // when there is none, which says nothing about the metatypes.
        QSequentialIterable sequenceIterable(&numbers);
        QAssociativeIterable associativeIterable(&lookup);

        int walked = 0;
        for (QSequentialConstIterator it = sequenceIterable.constBegin();
             it != sequenceIterable.constEnd(); ++it)
            walked += it->toInt();

        QStringList misses;
        if (!sequence.hasSize() || sequence.size(&numbers) != 3) misses << QStringLiteral("metasequence");
        if (!association.hasSize() || association.size(&lookup) != 1)
            misses << QStringLiteral("metaassociation");
        if (!sequenceBase->hasIterator()) misses << QStringLiteral("metacontainer");
        if (walked != 6) misses << QStringLiteral("iterate");
        if (associativeIterable.size() != 1) misses << QStringLiteral("associativeiterable");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("the container metatypes are Qt 6 only"));
        return false;
#endif
    });

    r.check("core/bytearrayview-recursivemutex-chronotimer", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        const QByteArray owned = QByteArrayLiteral("qt-smoke-view");
        QByteArrayView view(owned);

        // QRecursiveMutex was a QMutex mode in Qt 5 and is a class of its own
        // in Qt 6.
        QRecursiveMutex recursive;
        recursive.lock();
        recursive.lock();
        recursive.unlock();
        recursive.unlock();

        QStringList misses;
        if (view.size() != owned.size() || !view.startsWith("qt-smoke"))
            misses << QStringLiteral("bytearrayview");
        if (!recursive.tryLock()) {
            misses << QStringLiteral("recursivemutex");
        } else {
            recursive.unlock();
        }
#if QT_VERSION_MINOR >= 8
        // A timer that takes a std::chrono duration rather than milliseconds.
        // Never started: this app runs no event loop.
        QChronoTimer chronoTimer(std::chrono::milliseconds(250));
        if (chronoTimer.interval() != std::chrono::milliseconds(250) || chronoTimer.isActive())
            misses << QStringLiteral("chronotimer");
#endif
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QByteArrayView and QRecursiveMutex are Qt 6 only"));
        return false;
#endif
    });
}

void checkQt6Network(SmokeReporter &r)
{
    r.check("net/rest-access-manager-and-ssl-server", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        // Nothing is sent and nothing is listened on: the REST manager wraps a
        // QNetworkAccessManager that is never asked for a request, and the SSL
        // server is never told to listen.
        QNetworkAccessManager networkManager;
        QRestAccessManager restManager(&networkManager);
        QSslServer sslServer;

        QStringList misses;
        if (restManager.networkAccessManager() != &networkManager)
            misses << QStringLiteral("restmanager");
        if (sslServer.isListening()) misses << QStringLiteral("sslserver");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QRestAccessManager and QSslServer are Qt 6 only"));
        return false;
#endif
    });

    r.check("net/network-information-backend", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        // The one class here that needs something outside the process: a
        // platform backend plugin. Without one, instance() is null - which is
        // the environment missing, not the API misbehaving.
        if (!QNetworkInformation::loadDefaultBackend()) {
            r.skip(d, QStringLiteral("no QNetworkInformation backend on this system"));
            return false;
        }
        QNetworkInformation *info = QNetworkInformation::instance();
        if (!info) {
            r.skip(d, QStringLiteral("backend loaded but instance() is null"));
            return false;
        }
        // Any reachability value is legitimate; this only proves the query
        // path works and does not assert about the machine's network.
        const QNetworkInformation::Reachability reachability = info->reachability();
        return !info->backendName().isEmpty()
            && reachability >= QNetworkInformation::Reachability::Unknown;
#else
        r.skip(d, QStringLiteral("QNetworkInformation is Qt 6 only"));
        return false;
#endif
    });
}
