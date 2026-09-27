// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Qt 4 counterpart to checks_qtbase_misc.cpp.  That file deliberately sweeps
// APIs accumulated throughout Qt 5 and Qt 6; keeping the Qt 4 spelling here
// makes the boundary visible without burying the modern checks in dozens of
// version guards.  These are the classes from the same four semantic groups
// that genuinely exist in Qt 4.8.7.
#include "../common/smokecheck.h"

#include <QByteArrayMatcher>
#include <QStringMatcher>
#include <QCryptographicHash>
#include <QSysInfo>
#include <QLibrary>
#include <QLibraryInfo>
#include <QPluginLoader>
#include <QTranslator>
#include <QResource>
#include <QSystemSemaphore>
#include <QSharedMemory>
#include <QBasicTimer>
#include <QObjectCleanupHandler>
#include <QFileSystemWatcher>
#include <QFileIconProvider>
#include <QDesktopServices>
#include <QTemporaryFile>

#include <QDomDocument>
#include <QDomImplementation>
#include <QXmlAttributes>
#include <QXmlStreamReader>

#include <QAbstractNetworkCache>
#include <QAuthenticator>
#include <QNetworkDiskCache>
#include <QNetworkCacheMetaData>
#include <QHttpMultiPart>
#include <QHostAddress>
#include <QNetworkProxy>
#include <QNetworkProxyFactory>
#include <QNetworkProxyQuery>
#include <QSslCertificate>
#include <QSslCipher>
#include <QSslConfiguration>
#include <QSslError>
#include <QSslKey>
#include <QSslSocket>

#include <QFactoryInterface>
#include <QPixmap>
#include <QPixmapCache>

#include <QEvent>
#include <QEventTransition>
#include <QHistoryState>
#include <QState>
#include <QStateMachine>

#include <QBuffer>
#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QUrl>

namespace {

class SmokeNetworkCache : public QAbstractNetworkCache
{
public:
    explicit SmokeNetworkCache(QObject *parent = 0) : QAbstractNetworkCache(parent) {}

    QNetworkCacheMetaData metaData(const QUrl &url) override
    {
        QNetworkCacheMetaData meta;
        meta.setUrl(url);
        meta.setSaveToDisk(false);
        return meta;
    }
    void updateMetaData(const QNetworkCacheMetaData &metaData) override { lastMeta = metaData; }
    QIODevice *data(const QUrl &) override { return 0; }
    bool remove(const QUrl &) override { return true; }
    qint64 cacheSize() const override { return 0; }
    QIODevice *prepare(const QNetworkCacheMetaData &) override { return new QBuffer; }
    void insert(QIODevice *device) override { delete device; }
    void clear() override { lastMeta = QNetworkCacheMetaData(); }

    QNetworkCacheMetaData lastMeta;
};

class SmokeProxyFactory : public QNetworkProxyFactory
{
public:
    QList<QNetworkProxy> queryProxy(const QNetworkProxyQuery &query = QNetworkProxyQuery()) override
    {
        Q_UNUSED(query);
        return QList<QNetworkProxy>() << QNetworkProxy::NoProxy;
    }
};

class SmokeFactoryInterface : public QFactoryInterface
{
public:
    QStringList keys() const override { return QStringList() << QStringLiteral("smoke"); }
};

class SmokeEntityResolver : public QXmlStreamEntityResolver
{
public:
    QString resolveUndeclaredEntity(const QString &name) override
    {
        return name == QStringLiteral("smoke") ? QStringLiteral("resolved") : QString();
    }
};

} // namespace

void checkMiscUtility(SmokeReporter &r)
{
    r.check("qtbase/matchers-crypto-sysinfo", [&](QString &d) {
        QByteArrayMatcher byteMatcher(QByteArray("needle"));
        QStringMatcher stringMatcher(QStringLiteral("needle"));
        const QByteArray sha1 = QCryptographicHash::hash("abc", QCryptographicHash::Sha1).toHex();
        const quint16 marker = 0x0102;
        const unsigned char first = *reinterpret_cast<const unsigned char *>(&marker);
        const QSysInfo::Endian nativeOrder = first == 0x01
            ? QSysInfo::BigEndian : QSysInfo::LittleEndian;
        if (QSysInfo::ByteOrder != nativeOrder) {
            d = QStringLiteral("QSysInfo byte order differs from native memory layout");
            return false;
        }
        return byteMatcher.indexIn(QByteArray("a needle in haystack")) == 2
            && stringMatcher.indexIn(QStringLiteral("a needle in haystack")) == 2
            && sha1 == QByteArray("a9993e364706816aba3e25717850c26c9cd0d89d");
    });

    r.check("qtbase/library-pluginloader-translator-resource", [&](QString &d) {
        QLibrary library(QStringLiteral("nonexistent-qt-smoke-lib"));
        QPluginLoader loader(QStringLiteral("nonexistent-qt-smoke-plugin"));
        QTranslator translator;
        QResource resource(QStringLiteral("nonexistent-resource"));
        const QString prefix = QLibraryInfo::location(QLibraryInfo::PrefixPath);
        Q_UNUSED(translator);
        return !library.load() && !loader.load() && !resource.isValid() && !prefix.isEmpty();
    });

    r.check("qtbase/ipc-primitives-construct", [&](QString &d) {
#ifndef QT_NO_SHAREDMEMORY
        QSharedMemory sharedMemory(QStringLiteral("qt-smoke-shm-test"));
#endif
#ifndef QT_NO_SYSTEMSEMAPHORE
        QSystemSemaphore semaphore(QStringLiteral("qt-smoke-sem-test"), 1);
#endif
        QBasicTimer timer;
        QObjectCleanupHandler cleanup;
        cleanup.add(new QObject);
#ifndef QT_NO_SYSTEMSEMAPHORE
        Q_UNUSED(semaphore);
#endif
        bool ok = !timer.isActive() && !cleanup.isEmpty();
#ifndef QT_NO_SHAREDMEMORY
        ok = ok && sharedMemory.key() == QStringLiteral("qt-smoke-shm-test");
#endif
        return ok;
    });

    r.check("qtbase/filesystemwatcher-iconprovider-desktopservices", [&](QString &d) {
        QTemporaryFile file;
        if (!file.open()) { d = QStringLiteral("temporary file did not open"); return false; }
        QFileSystemWatcher watcher;
        watcher.addPath(file.fileName());
        QFileIconProvider iconProvider;
        QDesktopServices::unsetUrlHandler(QStringLiteral("qt-smoke-scheme"));
        const bool watched = watcher.files().contains(file.fileName());
        const QString type = iconProvider.type(QFileInfo(file.fileName()));
        d = QStringLiteral("watched=%1 type=%2 path=%3").arg(watched).arg(type).arg(file.fileName());
        return watched && !type.isEmpty();
    });
}

void checkDomExtras(SmokeReporter &r)
{
    r.check("dom/create-node-catalogue", [&](QString &d) {
        QDomDocument doc;
        QDomElement root = doc.createElement(QStringLiteral("root"));
        doc.appendChild(root);
        QDomText text = doc.createTextNode(QStringLiteral("hi"));
        QDomComment comment = doc.createComment(QStringLiteral("a comment"));
        QDomCDATASection cdata = doc.createCDATASection(QStringLiteral("<raw/>"));
        QDomProcessingInstruction pi = doc.createProcessingInstruction(
            QStringLiteral("xml-stylesheet"), QStringLiteral("type=\"text/xsl\""));
        QDomAttr attr = doc.createAttribute(QStringLiteral("id"));
        attr.setValue(QStringLiteral("1"));
        root.setAttributeNode(attr);
        QDomDocumentFragment fragment = doc.createDocumentFragment();
        fragment.appendChild(doc.createElement(QStringLiteral("child")));
        root.appendChild(fragment);
        QDomEntityReference entityRef = doc.createEntityReference(QStringLiteral("nbsp"));
        root.appendChild(entityRef);
        root.appendChild(text);
        root.appendChild(comment);
        root.appendChild(cdata);
        QDomNode node = root;
        QDomNodeList nodes = doc.elementsByTagName(QStringLiteral("child"));
        QDomNamedNodeMap attributes = root.attributes();
        QDomCharacterData characterData = text.toCharacterData();
        QDomImplementation implementation = doc.implementation();
        // A document built through the DOM API has no doctype, so both maps are empty
        // and both conversions yield a null node, on Qt 4 as on Qt 5 and 6.
        QDomDocumentType doctype = doc.doctype();
        QDomEntity entity = doctype.entities().namedItem(QStringLiteral("none")).toEntity();
        QDomNotation notation = doctype.notations().namedItem(QStringLiteral("none")).toNotation();
        return doc.documentElement() == root && text.data() == QStringLiteral("hi")
            && comment.data() == QStringLiteral("a comment") && !cdata.data().isEmpty()
            && pi.target() == QStringLiteral("xml-stylesheet")
            && nodes.count() == 1 && attributes.contains(QStringLiteral("id"))
            && characterData.data() == QStringLiteral("hi")
            && node.isElement() && entityRef.isEntityReference()
            && entity.isNull() && notation.isNull()
            && implementation.hasFeature(QStringLiteral("XML"), QStringLiteral("1.0"));
    });

    r.check("xml/stream-value-catalogue", [&](QString &d) {
        QXmlAttributes saxAttributes;
        saxAttributes.append(QStringLiteral("id"), QString(), QStringLiteral("id"), QStringLiteral("7"));
        QXmlStreamAttributes streamAttributes;
        streamAttributes.append(QStringLiteral("urn:test"), QStringLiteral("id"), QStringLiteral("7"));
        QXmlStreamAttribute attribute = streamAttributes.at(0);
        QXmlStreamStringRef nameRef(QStringLiteral("node"));
        QXmlStreamNamespaceDeclaration declaration(QStringLiteral("p"), QStringLiteral("urn:test"));
        QXmlStreamEntityDeclaration entityDeclaration;
        QXmlStreamNotationDeclaration notationDeclaration;
        SmokeEntityResolver resolver;
        // The resolver is exercised through the reader as well as directly:
        // &smoke; is undeclared, so QXmlStreamReader has to call into it to
        // produce any text at all.  Qt 4.4 added this hook and the signature
        // has not moved since.
        QXmlStreamReader reader(QStringLiteral("<root p:id=\"7\" xmlns:p=\"urn:test\">&smoke;</root>"));
        reader.setEntityResolver(&resolver);
        reader.addExtraNamespaceDeclaration(declaration);
        bool sawRoot = false;
        while (!reader.atEnd()) {
            reader.readNext();
            if (reader.isStartElement() && reader.name().toString() == QStringLiteral("root"))
                sawRoot = reader.attributes().hasAttribute(QStringLiteral("urn:test"),
                                                           QStringLiteral("id"));
        }
        return saxAttributes.length() == 1 && nameRef.size() == 4
            && streamAttributes.hasAttribute(QStringLiteral("urn:test"), QStringLiteral("id"))
            && attribute.value() == QStringLiteral("7")
            && declaration.prefix() == QStringLiteral("p")
            && entityDeclaration.name().isEmpty()
            && notationDeclaration.name().isEmpty()
            && resolver.resolveUndeclaredEntity(QStringLiteral("smoke"))
                   == QStringLiteral("resolved")
            && sawRoot;
    });
}

void checkNetworkExtras(SmokeReporter &r)
{
    r.check("network/diskcache-http-multipart", [&](QString &d) {
        QNetworkDiskCache cache;
        cache.setCacheDirectory(QDir::tempPath());
        QHttpMultiPart multiPart(QHttpMultiPart::FormDataType);
        QHttpPart part;
        part.setBody(QByteArray("field-value"));
        multiPart.append(part);
        return !cache.cacheDirectory().isEmpty() && !multiPart.boundary().isEmpty();
    });

    r.check("network/ipv6-address-proxy", [&](QString &d) {
        QIPv6Address emptyAddress = {};
        QHostAddress localhost(QStringLiteral("::1"));
        const bool converted = localhost.toIPv6Address().c[15] == 1;
        QNetworkProxy proxy(QNetworkProxy::HttpProxy, QStringLiteral("proxy.example.com"), 8080);
        return converted && proxy.hostName() == QStringLiteral("proxy.example.com")
            && emptyAddress.c[0] == 0;
    });

    r.check("network/authenticator-cache-proxyfactory", [&](QString &d) {
        QAuthenticator authenticator;
        authenticator.setUser(QStringLiteral("user"));
        authenticator.setPassword(QStringLiteral("pass"));
        authenticator.setOption(QStringLiteral("realm"), QStringLiteral("smoke"));

        QNetworkCacheMetaData meta;
        meta.setUrl(QUrl(QStringLiteral("http://example.test/cache")));
        meta.setSaveToDisk(false);
        meta.setRawHeaders(QNetworkCacheMetaData::RawHeaderList()
                           << qMakePair(QByteArray("x-smoke"), QByteArray("1")));
        SmokeNetworkCache cache;
        cache.updateMetaData(meta);
        QIODevice *device = cache.prepare(meta);
        cache.insert(device);

        QNetworkProxyQuery query(QStringLiteral("example.test"), 443,
                                 QStringLiteral("https"), QNetworkProxyQuery::TcpSocket);
        SmokeProxyFactory factory;
        const QList<QNetworkProxy> proxies = factory.queryProxy(query);
        return authenticator.user() == QStringLiteral("user")
            && authenticator.password() == QStringLiteral("pass")
            && authenticator.option(QStringLiteral("realm")).toString() == QStringLiteral("smoke")
            && cache.metaData(meta.url()).url() == meta.url()
            && cache.lastMeta.rawHeaders().first().first == QByteArray("x-smoke")
            && query.peerHostName() == QStringLiteral("example.test")
            && query.peerPort() == 443 && proxies.size() == 1
            && proxies.first().type() == QNetworkProxy::NoProxy;
    });

#if !defined(QT_NO_SSL) && !defined(QT_NO_OPENSSL)
    r.check("network/ssl-value-types", [&](QString &d) {
        QSslCertificate certificate;
        QSslCipher cipher;
        QSslConfiguration configuration = QSslConfiguration::defaultConfiguration();
        configuration.setPeerVerifyMode(QSslSocket::VerifyNone);
        QSslError sslError(QSslError::NoError, certificate);
        QSslKey key;
        QSslSocket socket;
        socket.setSslConfiguration(configuration);
        return certificate.isNull() && cipher.isNull()
            && configuration.peerVerifyMode() == QSslSocket::VerifyNone
            && sslError.error() == QSslError::NoError && key.isNull()
            && socket.mode() == QSslSocket::UnencryptedMode;
    });
#else
    r.check("network/ssl-value-types", [&](QString &d) {
        r.skip(d, QStringLiteral("Qt 4 SDK was built without SSL"));
        return false;
    });
#endif

    r.check("qtbase/factory-interface-pixmap-cache", [&](QString &d) {
        SmokeFactoryInterface factoryInterface;
        QPixmap pixmap(4, 4);
        pixmap.fill(Qt::red);
        QPixmapCache::Key cacheKey = QPixmapCache::insert(pixmap);
        QPixmap foundPixmap;
        const bool found = QPixmapCache::find(cacheKey, &foundPixmap);
        QPixmapCache::remove(cacheKey);
        const bool ok = factoryInterface.keys().contains(QStringLiteral("smoke"))
            && found && !foundPixmap.isNull();
        return ok;
    });
}

void checkStateMachineTail(SmokeReporter &r)
{
    r.check("qtbase/statemachine-tail", [&](QString &d) {
        QStateMachine machine;
        QState source(&machine);
        QState target(&machine);
        QHistoryState history(QHistoryState::DeepHistory, &source);
        QObject eventSource;
        QEventTransition transition(&eventSource, QEvent::User, &source);
        transition.setTargetState(&target);
        QAbstractState *abstractState = &history;
        QAbstractTransition *abstractTransition = &transition;
        return abstractState->parentState() == &source
            && history.historyType() == QHistoryState::DeepHistory
            && transition.eventSource() == &eventSource
            && transition.eventType() == QEvent::User
            && abstractTransition->targetState() == &target;
    });
}
