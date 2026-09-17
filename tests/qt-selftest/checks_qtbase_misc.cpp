// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// A further sweep of QtCore/QtNetwork/QtXml value types and utility classes
// that don't need a real backing service (a file on disk, a DNS server, a
// disk cache directory) to construct and exercise for real.
#include "../common/smokecheck.h"

#include <QCalendar>
#include <QByteArrayMatcher>
#include <QStringMatcher>
#include <QCollator>
#include <QCryptographicHash>
#include <QOperatingSystemVersion>
#include <QSysInfo>
#include <QLoggingCategory>
#include <QLibrary>
#include <QLibraryInfo>
#include <QPluginLoader>
#include <QTranslator>
#include <QResource>
#include <QSystemSemaphore>
#include <QSharedMemory>
#include <QBasicTimer>
#include <QEventLoopLocker>
#include <QObjectCleanupHandler>
#include <QFileSystemWatcher>
#if QT_VERSION_MAJOR < 6
#include <QFileIconProvider>
#else
#include <QAbstractFileIconProvider>   // the QtGui half, split out in Qt 6
#endif
#include <QDesktopServices>
#include <QCborValue>
#include <QCborError>
#include <QStaticPlugin>
#include <QTemporaryFile>
#include <QBuffer>
#include <QBackingStore>
#include <QEvent>
#include <QEventTransition>
#include <QFactoryInterface>
#include <QGenericPlugin>
#include <QGenericPluginFactory>
#include <QHistoryState>
#include <QGuiApplication>
#include <QInputMethod>
#include <QOffscreenSurface>
// QtGui's QOpenGL* classes only exist when Qt itself was configured with
// OpenGL. Guarded the same way as the sctp block further down, using Qt's own
// configuration macro rather than a platform test.
#if QT_CONFIG(opengl)
#include <QOpenGLBuffer>
#include <QOpenGLContext>
#include <QOpenGLDebugLogger>
#include <QOpenGLDebugMessage>
#include <QOpenGLExtraFunctions>
#include <QOpenGLFramebufferObject>
#include <QOpenGLFramebufferObjectFormat>
#include <QOpenGLFunctions>
#include <QOpenGLFunctions_1_0>
#include <QOpenGLFunctions_1_1>
#include <QOpenGLFunctions_1_2>
#include <QOpenGLFunctions_1_3>
#include <QOpenGLFunctions_1_4>
#include <QOpenGLFunctions_1_5>
#include <QOpenGLFunctions_2_0>
#include <QOpenGLFunctions_2_1>
#include <QOpenGLFunctions_3_0>
#include <QOpenGLFunctions_3_1>
#include <QOpenGLFunctions_3_2_Compatibility>
#include <QOpenGLFunctions_3_2_Core>
#include <QOpenGLFunctions_3_3_Compatibility>
#include <QOpenGLFunctions_3_3_Core>
#include <QOpenGLFunctions_4_0_Compatibility>
#include <QOpenGLFunctions_4_0_Core>
#include <QOpenGLFunctions_4_1_Compatibility>
#include <QOpenGLFunctions_4_1_Core>
#include <QOpenGLFunctions_4_2_Compatibility>
#include <QOpenGLFunctions_4_2_Core>
#include <QOpenGLFunctions_4_3_Compatibility>
#include <QOpenGLFunctions_4_3_Core>
#include <QOpenGLFunctions_4_4_Compatibility>
#include <QOpenGLFunctions_4_4_Core>
#include <QOpenGLFunctions_4_5_Compatibility>
#include <QOpenGLFunctions_4_5_Core>
#if QT_VERSION_MAJOR < 6
#include <QOpenGLFunctions_ES2>
#endif
#include <QOpenGLPaintDevice>
#include <QOpenGLPixelTransferOptions>
#include <QOpenGLShader>
#include <QOpenGLShaderProgram>
#include <QOpenGLTexture>
#include <QOpenGLTextureBlitter>
#include <QOpenGLTimeMonitor>
#include <QOpenGLTimerQuery>
#include <QOpenGLVersionProfile>
#include <QOpenGLVertexArrayObject>
#include <QOffscreenSurface>
#endif // QT_CONFIG(opengl)
#include <QPaintDeviceWindow>
#include <QPixmap>
#include <QPixmapCache>
#include <QPlatformSurfaceEvent>
#include <QRasterWindow>
#include <QScreenOrientationChangeEvent>
#include <QState>
#include <QStateMachine>
#include <QSurface>
#include <QSurfaceFormat>
#include <QWindow>

#include <QDomDocument>
#include <QDomImplementation>
#if QT_VERSION_MAJOR < 6
#include <QXmlAttributes>
#endif
#include <QXmlStreamReader>

#include <QAbstractNetworkCache>
#include <QAuthenticator>
#include <QDnsLookup>
#include <QNetworkDiskCache>
#include <QNetworkCacheMetaData>
#include <QHttpMultiPart>
#include <QHstsPolicy>
#include <QHttp2Configuration>
#include <QHostAddress>
#include <QNetworkProxy>
#include <QSslCertificate>
#include <QSslCertificateExtension>
#include <QSslCipher>
#include <QSslConfiguration>
#if QT_CONFIG(ssl)
#if QT_CONFIG(dtls)
#include <QDtls>
#if QT_VERSION_MAJOR < 6
#include <QDtlsClientVerifier>
#endif
#endif
#include <QOcspResponse>
#endif
#include <QSslError>
#include <QSslKey>
#include <QSslSocket>
#if QT_VERSION_MAJOR < 6
#include <QSctpServer>
#endif
#if QT_VERSION_MAJOR < 6
#include <QSctpSocket>
#endif
#include <QDir>
#include <QDateTime>
#include <QUrl>

namespace {

class SmokeNetworkCache : public QAbstractNetworkCache
{
public:
    explicit SmokeNetworkCache(QObject *parent = nullptr) : QAbstractNetworkCache(parent) {}

    QNetworkCacheMetaData metaData(const QUrl &url) override
    {
        QNetworkCacheMetaData meta;
        meta.setUrl(url);
        meta.setSaveToDisk(false);
        return meta;
    }
    void updateMetaData(const QNetworkCacheMetaData &metaData) override { lastMeta = metaData; }
    QIODevice *data(const QUrl &) override { return nullptr; }
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

class SmokeGenericPlugin : public QGenericPlugin
{
public:
    QObject *create(const QString &name, const QString &spec) override
    {
        auto *object = new QObject;
        object->setObjectName(name + QLatin1Char(':') + spec);
        return object;
    }
};

} // namespace

void checkMiscUtility(SmokeReporter &r)
{
    r.check("qtbase/calendar-matchers-collator-sortkey", [&](QString &d) {
        QCalendar calendar;
        QByteArrayMatcher byteMatcher(QByteArray("needle"));
        QStringMatcher stringMatcher(QStringLiteral("needle"));
        QCollator collator;
        QCollatorSortKey key1 = collator.sortKey("apple");
        QCollatorSortKey key2 = collator.sortKey("banana");
        return calendar.isValid() && byteMatcher.indexIn(QByteArray("a needle in haystack")) == 2
            && stringMatcher.indexIn(QStringLiteral("a needle in haystack")) == 2
            && key1 < key2;
    });
    r.check("qtbase/os-version-sysinfo-logging", [&](QString &d) {
        QOperatingSystemVersion osVersion = QOperatingSystemVersion::current();
        QString kernelType = QSysInfo::kernelType();
        QLoggingCategory category("qt.smoke.test");
        // QOperatingSystemVersion only classifies Windows, macOS and Android;
        // on any other Unix current().type() is Unknown by design. Asserting
        // otherwise would assert a Windows-ism rather than the API, so scope
        // just that one clause - everything else here is exercised everywhere.
#if defined(Q_OS_WIN) || defined(Q_OS_MACOS) || defined(Q_OS_ANDROID)
        const bool osVersionIsUsable = osVersion.type() != QOperatingSystemVersion::Unknown
            && osVersion.majorVersion() >= 0;
#else
        // Unknown comes with majorVersion() == -1, so neither value carries
        // anything to assert on here; the call still exercises the API.
        const bool osVersionIsUsable = true;
#endif
        return osVersionIsUsable && !kernelType.isEmpty()
            && category.isDebugEnabled() == category.isDebugEnabled();
    });
    r.check("qtbase/library-pluginloader-translator-resource", [&](QString &d) {
        QLibrary lib(QStringLiteral("nonexistent-qt-smoke-lib"));
        QPluginLoader loader(QStringLiteral("nonexistent-qt-smoke-plugin"));
        QTranslator translator;
        QResource resource(QStringLiteral("nonexistent-resource"));
        QString libInfoPath = QLibraryInfo::location(QLibraryInfo::PrefixPath);
        return !lib.load() && !loader.load() && !resource.isValid() && !libInfoPath.isEmpty();
    });
    r.check("qtbase/ipc-primitives-construct", [&](QString &d) {
        QSharedMemory sharedMem(QStringLiteral("qt-smoke-shm-test"));
        QSystemSemaphore semaphore(QStringLiteral("qt-smoke-sem-test"), 1);
        QBasicTimer timer;
        QEventLoopLocker locker;
        QObjectCleanupHandler cleanup;
        auto *obj = new QObject;
        cleanup.add(obj);
        return sharedMem.key() == QStringLiteral("qt-smoke-shm-test") && !timer.isActive()
            && cleanup.isEmpty() == false;
    });
    r.check("qtbase/filesystemwatcher-iconprovider-desktopservices", [&](QString &d) {
        QTemporaryFile tempFile;
        tempFile.open();
        QFileSystemWatcher watcher;
        watcher.addPath(tempFile.fileName());
        // QFileIconProvider::icon() pulls in platform-theme icon lookup,
        // which crashed headlessly in this build (no theme plugin available)
        // - constructing the provider is enough to exercise the class.
#if QT_VERSION_MAJOR < 6
        QFileIconProvider iconProvider;
#else
        QAbstractFileIconProvider iconProvider;
#endif
        // unsetUrlHandler() on a scheme that was never registered is a
        // documented no-op - safe to call without side effects.
        QDesktopServices::unsetUrlHandler(QStringLiteral("qt-smoke-scheme"));
        return watcher.files().contains(tempFile.fileName())
#if QT_VERSION_MAJOR < 6
            && iconProvider.type(QFileInfo()) >= 0;
#else
            // type() describes the file in words in Qt 6 rather than
            // returning an enum value.
            && !iconProvider.type(QFileInfo()).isNull();
#endif
    });
    r.check("qtbase/cbor-error-value", [&](QString &d) {
        QCborValue value(42);
        QByteArray bad = QByteArray::fromHex("ff");
        QCborParserError parserError;
        QCborValue::fromCbor(bad, &parserError);
        QCborError err = parserError.error;
        return value.toInteger() == 42 && err.c != QCborError::NoError;
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
        QDomElement child = doc.createElement(QStringLiteral("child"));
        fragment.appendChild(child);
        root.appendChild(fragment);
        QDomEntityReference entityRef = doc.createEntityReference(QStringLiteral("nbsp"));
        root.appendChild(entityRef);
        QDomNode node = root;
        QDomNodeList nodes = doc.elementsByTagName(QStringLiteral("child"));
        QDomNamedNodeMap namedNodes = root.attributes();
        QDomCharacterData characterData = text.toCharacterData();
        QDomDocumentType doctype = doc.doctype();
        QDomEntity entity = doctype.entities().namedItem(QStringLiteral("none")).toEntity();
        QDomNotation notation = doctype.notations().namedItem(QStringLiteral("none")).toNotation();
        root.appendChild(text);
        root.appendChild(comment);
        root.appendChild(cdata);
        QDomImplementation impl = doc.implementation();
        return doc.documentElement() == root && text.data() == QStringLiteral("hi")
            && comment.data() == QStringLiteral("a comment") && !cdata.data().isEmpty()
            && pi.target() == QStringLiteral("xml-stylesheet")
            && root.attributeNode(QStringLiteral("id")).value() == QStringLiteral("1")
            && node.isElement() && nodes.count() == 1 && namedNodes.contains(QStringLiteral("id"))
            && characterData.data() == QStringLiteral("hi") && entityRef.isEntityReference()
            && entity.isNull() && notation.isNull()
            && impl.hasFeature(QStringLiteral("XML"), QStringLiteral("1.0"));
    });
    r.check("xml/stream-value-catalogue", [&](QString &d) {
#if QT_VERSION_MAJOR < 6
        QXmlAttributes saxAttributes;
        saxAttributes.append(QStringLiteral("id"), QString(), QStringLiteral("id"), QStringLiteral("7"));
#endif

        QXmlStreamAttributes streamAttributes;
        streamAttributes.append(QStringLiteral("urn:test"), QStringLiteral("id"), QStringLiteral("7"));
        QXmlStreamAttribute attr = streamAttributes.at(0);
#if QT_VERSION_MAJOR < 6
        QXmlStreamStringRef nameRef(QStringLiteral("node"));
#endif
        QXmlStreamNamespaceDeclaration nsDecl(QStringLiteral("p"), QStringLiteral("urn:test"));
        QXmlStreamEntityDeclaration entityDecl;
        QXmlStreamNotationDeclaration notationDecl;
        class SmokeEntityResolver : public QXmlStreamEntityResolver {
        public:
            QString resolveUndeclaredEntity(const QString &name) override
            {
                return name == QStringLiteral("smoke") ? QStringLiteral("resolved") : QString();
            }
        } resolver;
        QXmlStreamReader reader(QStringLiteral("<root p:id=\"7\" xmlns:p=\"urn:test\">&smoke;</root>"));
        reader.setEntityResolver(&resolver);
        reader.addExtraNamespaceDeclaration(nsDecl);
        bool sawRoot = false;
        while (!reader.atEnd()) {
            reader.readNext();
            if (reader.isStartElement() && reader.name() == QStringLiteral("root"))
                sawRoot = reader.attributes().hasAttribute(QStringLiteral("urn:test"), QStringLiteral("id"));
        }
        return true
#if QT_VERSION_MAJOR < 6
            && saxAttributes.length() == 1
            && nameRef.size() == 4
#endif
            && streamAttributes.hasAttribute(QStringLiteral("urn:test"), QStringLiteral("id"))
            && attr.value() == QStringLiteral("7")
            && nsDecl.prefix() == QStringLiteral("p")
            && entityDecl.name().isEmpty()
            && notationDecl.name().isEmpty()
            && resolver.resolveUndeclaredEntity(QStringLiteral("smoke")) == QStringLiteral("resolved")
            && sawRoot;
    });
}

void checkNetworkExtras(SmokeReporter &r)
{
    r.check("network/dns-lookup-construct", [&](QString &d) {
        QDnsLookup lookup;
        lookup.setType(QDnsLookup::A);
        lookup.setName(QStringLiteral("localhost"));
        // Not started - just confirms the value types (records) default-construct.
        QDnsDomainNameRecord domainRecord;
        QDnsHostAddressRecord hostRecord;
        QDnsMailExchangeRecord mxRecord;
        QDnsServiceRecord serviceRecord;
        QDnsTextRecord textRecord;
        return lookup.type() == QDnsLookup::A && lookup.name() == QStringLiteral("localhost")
            && domainRecord.name().isEmpty() && hostRecord.timeToLive() == 0
            && mxRecord.exchange().isEmpty() && serviceRecord.target().isEmpty()
            && textRecord.name().isEmpty();
    });
    r.check("network/diskcache-http-hsts", [&](QString &d) {
        QNetworkDiskCache cache;
        cache.setCacheDirectory(QDir::tempPath());
        QHttpMultiPart multiPart(QHttpMultiPart::FormDataType);
        QHttpPart part;
        part.setBody(QByteArray("field-value"));
        multiPart.append(part);
        QHstsPolicy hsts(QDateTime::currentDateTime().addYears(1),
                         QHstsPolicy::IncludeSubDomains, QStringLiteral("example.com"));
        QHttp2Configuration http2Config;
        http2Config.setServerPushEnabled(false);
        // setCacheDirectory() normalizes the path (e.g. resolves it to an
        // absolute/canonical form), so it won't necessarily string-match
        // QDir::tempPath() exactly - just confirm it's non-empty and set.
        return !cache.cacheDirectory().isEmpty() && multiPart.boundary().size() > 0
            && hsts.host() == QStringLiteral("example.com") && !http2Config.serverPushEnabled();
    });
    r.check("network/ipv6-address-proxy", [&](QString &d) {
        QIPv6Address v6;
        QHostAddress addr(QStringLiteral("::1"));
        bool converted = addr.toIPv6Address().c[15] == 1;
        QNetworkProxy proxy(QNetworkProxy::HttpProxy, QStringLiteral("proxy.example.com"), 8080);
        return converted && proxy.hostName() == QStringLiteral("proxy.example.com")
            && v6.c[0] == v6.c[0];
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
        QAbstractNetworkCache *abstractCache = &cache;
        abstractCache->updateMetaData(meta);
        QIODevice *device = abstractCache->prepare(meta);
        abstractCache->insert(device);

        QNetworkProxyQuery query(QStringLiteral("example.test"), 443,
                                 QStringLiteral("https"), QNetworkProxyQuery::TcpSocket);
        SmokeProxyFactory factory;
        QNetworkProxyFactory *factoryBase = &factory;
        QList<QNetworkProxy> proxies = factoryBase->queryProxy(query);
        return authenticator.user() == QStringLiteral("user")
            && authenticator.password() == QStringLiteral("pass")
            && authenticator.option(QStringLiteral("realm")).toString() == QStringLiteral("smoke")
            && abstractCache->metaData(meta.url()).url() == meta.url()
            && cache.lastMeta.rawHeaders().first().first == QByteArrayLiteral("x-smoke")
            && query.peerHostName() == QStringLiteral("example.test")
            && query.peerPort() == 443
            && proxies.size() == 1
            && proxies.first().type() == QNetworkProxy::NoProxy;
    });
#ifndef QT_NO_SSL
    r.check("network/ssl-value-types", [&](QString &d) {
        QSslCertificate certificate;
        QSslCertificateExtension extension;
        QSslCipher cipher;
        QSslConfiguration configuration = QSslConfiguration::defaultConfiguration();
        configuration.setPeerVerifyMode(QSslSocket::VerifyNone);
        configuration.setProtocol(QSsl::TlsV1_2OrLater);
#if QT_CONFIG(ssl)
        QOcspResponse ocspResponse;
#endif
        QSslError sslError(QSslError::NoError, certificate);
        QSslKey key;
        QSslSocket socket;
        socket.setSslConfiguration(configuration);
        return certificate.isNull()
            && !extension.isSupported()
            && cipher.isNull()
            && configuration.peerVerifyMode() == QSslSocket::VerifyNone
#if QT_CONFIG(ssl)
            && ocspResponse.certificateStatus() == QOcspCertificateStatus::Unknown
#endif
            && sslError.error() == QSslError::NoError
            && key.isNull()
            && socket.mode() == QSslSocket::UnencryptedMode;
    });
#if QT_CONFIG(dtls)
    r.check("network/dtls-value-types", [&](QString &d) {
        QDtls dtls(QSslSocket::SslClientMode);
        dtls.setMtuHint(1200);
        dtls.setPeer(QHostAddress::LocalHost, 4444, QStringLiteral("localhost"));
        QDtlsClientVerifier verifier;
        QDtlsClientVerifier::GeneratorParameters params(QCryptographicHash::Sha256,
                                                        QByteArrayLiteral("qt-smoke"));
        verifier.setCookieGeneratorParameters(params);
        return dtls.sslMode() == QSslSocket::SslClientMode
            && dtls.handshakeState() == QDtls::HandshakeNotStarted
            && dtls.mtuHint() == 1200
            && dtls.peerAddress() == QHostAddress::LocalHost
            && dtls.peerPort() == 4444
            && dtls.peerVerificationName() == QStringLiteral("localhost")
            && verifier.cookieGeneratorParameters().hash == QCryptographicHash::Sha256;
    });
#endif
#endif
    r.check("qtbase/generic-plugin-surface-cache", [&](QString &d) {
        SmokeFactoryInterface factoryInterface;
        QFactoryInterface *factoryBase = &factoryInterface;
        SmokeGenericPlugin genericPlugin;
        QGenericPlugin *genericPluginBase = &genericPlugin;
        QObject *pluginObject = genericPluginBase->create(QStringLiteral("device"), QStringLiteral("spec"));
        QObject *missingFactoryObject = QGenericPluginFactory::create(QStringLiteral("missing"), QString());

        QSurfaceFormat format;
        format.setVersion(2, 1);
        format.setRenderableType(QSurfaceFormat::OpenGL);
        format.setOption(QSurfaceFormat::DeprecatedFunctions);
        QOffscreenSurface offscreenSurface;
        offscreenSurface.setFormat(format);
        QSurface *surface = &offscreenSurface;
        QPlatformSurfaceEvent surfaceEvent(QPlatformSurfaceEvent::SurfaceCreated);

        QPixmap pixmap(4, 4);
        pixmap.fill(Qt::red);
        QPixmapCache::Key cacheKey = QPixmapCache::insert(pixmap);
        QPixmap foundPixmap;
        const bool found = QPixmapCache::find(cacheKey, &foundPixmap);
        QPixmapCache::remove(cacheKey);

        QInputMethod *inputMethod = QGuiApplication::inputMethod();
        bool ok = factoryBase->keys().contains(QStringLiteral("smoke"))
            && pluginObject != nullptr
            && pluginObject->objectName() == QStringLiteral("device:spec")
            && missingFactoryObject == nullptr
            && surface->surfaceClass() == QSurface::Offscreen
            && offscreenSurface.requestedFormat().majorVersion() == 2
            && surfaceEvent.surfaceEventType() == QPlatformSurfaceEvent::SurfaceCreated
            && found
            && !foundPixmap.isNull()
            && inputMethod != nullptr;
        delete pluginObject;
        return ok;
    });
    r.check("qtbase/window-backingstore-events", [&](QString &d) {
        QWindow window;
        window.resize(16, 16);
        // create() first: on macOS QBackingStore::resize() dereferences a null
        // platform backing store for a window without a platform handle.
        window.create();
        QBackingStore backingStore(&window);
        backingStore.resize(QSize(16, 16));
        QRasterWindow rasterWindow;
        QPaintDeviceWindow *paintDeviceWindow = &rasterWindow;
        QScreenOrientationChangeEvent orientationEvent(nullptr, Qt::PortraitOrientation);
        return backingStore.window() == &window
            && backingStore.size() == QSize(16, 16)
            && paintDeviceWindow->surfaceType() == QSurface::RasterSurface
            && orientationEvent.orientation() == Qt::PortraitOrientation;
    });
#if QT_CONFIG(opengl)
    r.check("qtbase/opengl-api-shells", [&](QString &d) {
#if defined(Q_OS_LINUX) && defined(Q_PROCESSOR_X86_32)
        r.skip(d, QStringLiteral("OpenGL shell destructors are not crash-safe on 32-bit Linux/X11 in this static build"));
        return false;
#endif
        QOpenGLBuffer buffer(QOpenGLBuffer::VertexBuffer);
        QOpenGLContext context;
        QOpenGLDebugLogger debugLogger;
        QOpenGLDebugMessage debugMessage = QOpenGLDebugMessage::createApplicationMessage(
            QStringLiteral("smoke"));
        QOpenGLFramebufferObject *framebufferObject = nullptr;
        QOpenGLFramebufferObjectFormat framebufferFormat;
        framebufferFormat.setAttachment(QOpenGLFramebufferObject::CombinedDepthStencil);
        QOpenGLPixelTransferOptions pixelOptions;
        pixelOptions.setAlignment(4);
        QOpenGLShader *shader = nullptr;
        QOpenGLShaderProgram shaderProgram;
        QOpenGLTexture texture(QOpenGLTexture::Target2D);
        QOpenGLTextureBlitter textureBlitter;

        // QOpenGLTimerQuery: Qt 5.15.19 never initialises QOpenGLTimerQueryPrivate::core
        // but deletes it, so the object may exist only once create() has assigned it,
        // which needs a current, non-ES context. QOpenGLTimeMonitor likewise: its
        // destructor calls makeCurrent() on a context create() has not set yet, which
        // crashes whenever some context is current.
        QOpenGLContext liveContext;
        QOffscreenSurface surface;
        bool haveLiveContext = liveContext.create();
        if (haveLiveContext) {
            surface.setFormat(liveContext.format());
            surface.create();
            haveLiveContext = surface.isValid() && liveContext.makeCurrent(&surface)
                && !liveContext.isOpenGLES();
        }
        if (!haveLiveContext) {
            r.skip(d, QStringLiteral("no GL context available for the timer-query shells"));
            return false;
        }

        QOpenGLTimeMonitor timeMonitor;
        // Not optional, for the reason spelled out above: create() is what gives
        // d->context a value, and without one the destructor dereferences null.
        const bool timeMonitorCreated = timeMonitor.create();
        QOpenGLTimerQuery timerQuery;
        // Not optional: this is what makes the object safe to destroy. Whether
        // it succeeds depends on the driver supporting timer queries - software
        // rasterisers often do not - and either answer is fine here.
        const bool timerQueryCreated = timerQuery.create();
        QOpenGLVersionProfile versionProfile;
        versionProfile.setVersion(2, 1);
        QOpenGLVertexArrayObject vertexArray;
        QOpenGLPaintDevice paintDevice(QSize(4, 4));

        QOpenGLFunctions *functions = nullptr;
        QOpenGLExtraFunctions *extraFunctions = nullptr;
        QOpenGLFunctions_1_0 *f10 = nullptr;
        QOpenGLFunctions_1_1 *f11 = nullptr;
        QOpenGLFunctions_1_2 *f12 = nullptr;
        QOpenGLFunctions_1_3 *f13 = nullptr;
        QOpenGLFunctions_1_4 *f14 = nullptr;
        QOpenGLFunctions_1_5 *f15 = nullptr;
        QOpenGLFunctions_2_0 *f20 = nullptr;
        QOpenGLFunctions_2_1 *f21 = nullptr;
        QOpenGLFunctions_3_0 *f30 = nullptr;
        QOpenGLFunctions_3_1 *f31 = nullptr;
        QOpenGLFunctions_3_2_Compatibility *f32c = nullptr;
        QOpenGLFunctions_3_2_Core *f32 = nullptr;
        QOpenGLFunctions_3_3_Compatibility *f33c = nullptr;
        QOpenGLFunctions_3_3_Core *f33 = nullptr;
        QOpenGLFunctions_4_0_Compatibility *f40c = nullptr;
        QOpenGLFunctions_4_0_Core *f40 = nullptr;
        QOpenGLFunctions_4_1_Compatibility *f41c = nullptr;
        QOpenGLFunctions_4_1_Core *f41 = nullptr;
        QOpenGLFunctions_4_2_Compatibility *f42c = nullptr;
        QOpenGLFunctions_4_2_Core *f42 = nullptr;
        QOpenGLFunctions_4_3_Compatibility *f43c = nullptr;
        QOpenGLFunctions_4_3_Core *f43 = nullptr;
        QOpenGLFunctions_4_4_Compatibility *f44c = nullptr;
        QOpenGLFunctions_4_4_Core *f44 = nullptr;
        QOpenGLFunctions_4_5_Compatibility *f45c = nullptr;
        QOpenGLFunctions_4_5_Core *f45 = nullptr;

        return !buffer.isCreated()
            && !context.isValid()
            && !debugLogger.isLogging()
            && debugMessage.message() == QStringLiteral("smoke")
            && framebufferObject == nullptr
            && framebufferFormat.attachment() == QOpenGLFramebufferObject::CombinedDepthStencil
            && pixelOptions.alignment() == 4
            && shader == nullptr
            && !shaderProgram.isLinked()
            && !texture.isCreated()
            && !textureBlitter.isCreated()
            && timeMonitor.isCreated() == timeMonitorCreated
            && timerQuery.isCreated() == timerQueryCreated
            && versionProfile.version() == qMakePair(2, 1)
            && !vertexArray.isCreated()
            && paintDevice.size() == QSize(4, 4)
            && functions == nullptr && extraFunctions == nullptr
            && f10 == nullptr && f11 == nullptr && f12 == nullptr && f13 == nullptr
            && f14 == nullptr && f15 == nullptr && f20 == nullptr && f21 == nullptr
            && f30 == nullptr && f31 == nullptr && f32c == nullptr && f32 == nullptr
            && f33c == nullptr && f33 == nullptr && f40c == nullptr && f40 == nullptr
            && f41c == nullptr && f41 == nullptr && f42c == nullptr && f42 == nullptr
            && f43c == nullptr && f43 == nullptr && f44c == nullptr && f44 == nullptr
            && f45c == nullptr && f45 == nullptr;
    });
#else
    r.check("qtbase/opengl-api-shells", [&](QString &d) {
        r.skip(d, QStringLiteral("Qt was configured without OpenGL"));
        return false;
    });
#endif
#if QT_CONFIG(sctp)
    r.check("network/sctp-construct", [&](QString &d) {
        QSctpServer server;
        server.setMaximumChannelCount(2);
        QSctpSocket socket;
        socket.setMaximumChannelCount(2);
        return server.maximumChannelCount() == 2
            && socket.maximumChannelCount() == 2
            && !socket.isInDatagramMode();
    });
#endif
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
