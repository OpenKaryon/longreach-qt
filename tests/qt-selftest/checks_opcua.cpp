// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// QtOpcUa - a module that exists only in Qt 6, and one this kit was building
// into every Qt 6 SDK without a single check pointed at it.
//
// Almost all of it is value types: the OPC UA information model (nodes,
// references, browse paths, filters, history requests) expressed as
// copyable structs with plain setters. None of them need a server, a backend
// plugin or a network to construct and round-trip, which is exactly what makes
// them coverable from the headless battery. The classes that *do* need a
// backend - QOpcUaClient, QOpcUaNode and the generic struct handler - are
// reached the only honest way: by asking QOpcUaProvider for one and reporting a
// SKIP when no plugin answers. QOpcUaHistoryReadResponse cannot be reached even
// that far: its only constructor takes a private implementation pointer, so a
// client hands one back or nobody makes one at all.
#include "../common/smokecheck.h"

#include <type_traits>

#ifdef SMOKE_HAVE_OPCUA
#include <QOpcUaAddNodeItem>
#include <QOpcUaAddReferenceItem>
#include <QOpcUaApplicationDescription>
#include <QOpcUaApplicationIdentity>
#include <QOpcUaApplicationRecordDataType>
#include <QOpcUaArgument>
#include <QOpcUaAttributeOperand>
#include <QOpcUaAuthenticationInformation>
#include <QOpcUaAxisInformation>
#include <QOpcUaBinaryDataEncoding>
#include <QOpcUaBrowsePathTarget>
#include <QOpcUaBrowseRequest>
#include <QOpcUaClient>
#include <QOpcUaGenericStructHandler>
#include <QOpcUaHistoryReadResponse>
#include <QOpcUaComplexNumber>
#include <QOpcUaContentFilterElement>
#include <QOpcUaContentFilterElementResult>
#include <QOpcUaDataValue>
#include <QOpcUaDeleteReferenceItem>
#include <QOpcUaDoubleComplexNumber>
#include <QOpcUaEUInformation>
#include <QOpcUaElementOperand>
#include <QOpcUaEndpointDescription>
#include <QOpcUaErrorState>
#include <QOpcUaEventFilterResult>
#include <QOpcUaExpandedNodeId>
#include <QOpcUaExtensionObject>
#include <QOpcUaHistoryData>
#include <QOpcUaHistoryReadRawRequest>
#include <QOpcUaLiteralOperand>
#include <QOpcUaLocalizedText>
#include <QOpcUaMonitoringParameters>
#include <QOpcUaMultiDimensionalArray>
#include <QOpcUaNode>
#include <QOpcUaNodeCreationAttributes>
#include <QOpcUaPkiConfiguration>
#include <QOpcUaPlugin>
#include <QOpcUaProvider>
#include <QOpcUaQualifiedName>
#include <QOpcUaRange>
#include <QOpcUaReadItem>
#include <QOpcUaReadResult>
#include <QOpcUaReferenceDescription>
#include <QOpcUaRelativePathElement>
#include <QOpcUaSimpleAttributeOperand>
#include <QtOpcUa/qopcuatype.h>   // the QOpcUa namespace: enums, no camel-case header
#include <QOpcUaUserTokenPolicy>
#include <QOpcUaWriteItem>
#include <QOpcUaWriteResult>
#include <QOpcUaXValue>
#if __has_include(<QOpcUaGdsClient>) && __has_include(<QOpcUaKeyPair>) \
    && __has_include(<QOpcUaX509CertificateSigningRequest>) \
    && __has_include(<QOpcUaX509DistinguishedName>) \
    && __has_include(<QOpcUaX509Extension>) \
    && __has_include(<QOpcUaX509ExtensionBasicConstraints>) \
    && __has_include(<QOpcUaX509ExtensionExtendedKeyUsage>) \
    && __has_include(<QOpcUaX509ExtensionKeyUsage>) \
    && __has_include(<QOpcUaX509ExtensionSubjectAlternativeName>)
#define SMOKE_HAVE_OPCUA_SECURITY 1
#include <QOpcUaGdsClient>
#include <QOpcUaKeyPair>
#include <QOpcUaX509CertificateSigningRequest>
#include <QOpcUaX509DistinguishedName>
#include <QOpcUaX509Extension>
#include <QOpcUaX509ExtensionBasicConstraints>
#include <QOpcUaX509ExtensionExtendedKeyUsage>
#include <QOpcUaX509ExtensionKeyUsage>
#include <QOpcUaX509ExtensionSubjectAlternativeName>
#endif

#include <QDateTime>
#include <QScopedPointer>
#include <QVariant>
#endif

void checkOpcUaValueTypes(SmokeReporter &r)
{
    r.check("opcua/x509-key-csr-and-gds", [&](QString &d) {
#ifdef SMOKE_HAVE_OPCUA_SECURITY
        QOpcUaX509DistinguishedName subject;
        subject.setEntry(QOpcUaX509DistinguishedName::Type::CommonName,
                         QStringLiteral("qt-smoke"));
        subject.setEntry(QOpcUaX509DistinguishedName::Type::OrganizationName,
                         QStringLiteral("OpenKaryon"));

        QOpcUaX509CertificateSigningRequest request;
        request.setSubject(subject);
        request.setMessageDigest(QOpcUaX509CertificateSigningRequest::MessageDigest::SHA256);
        request.setEncoding(QOpcUaX509CertificateSigningRequest::Encoding::PEM);

        auto *basic = new QOpcUaX509ExtensionBasicConstraints;
        basic->setCritical(true);
        basic->setCa(false);
        basic->setPathLength(0);
        request.addExtension(basic);

        auto *usage = new QOpcUaX509ExtensionKeyUsage;
        usage->setKeyUsage(QOpcUaX509ExtensionKeyUsage::KeyUsage::DigitalSignature);
        usage->setKeyUsage(QOpcUaX509ExtensionKeyUsage::KeyUsage::KeyEncipherment);
        request.addExtension(usage);

        auto *extended = new QOpcUaX509ExtensionExtendedKeyUsage;
        extended->setKeyUsage(
            QOpcUaX509ExtensionExtendedKeyUsage::KeyUsage::TlsWebClientAuthentication);
        request.addExtension(extended);

        auto *alternative = new QOpcUaX509ExtensionSubjectAlternativeName;
        alternative->addEntry(QOpcUaX509ExtensionSubjectAlternativeName::Type::DNS,
                              QStringLiteral("localhost"));
        alternative->addEntry(QOpcUaX509ExtensionSubjectAlternativeName::Type::URI,
                              QStringLiteral("urn:qt-smoke"));
        request.addExtension(alternative);

        QOpcUaX509Extension *asExtension = basic;
        QOpcUaKeyPair key;
        key.generateRsaKey(QOpcUaKeyPair::RsaKeyStrength::Bits1024);
        const QByteArray csr = request.createRequest(key);

        QOpcUaGdsClient gds;
        gds.setBackend(QStringLiteral("open62541"));
        gds.setCertificateSigningRequestPresets(subject, QStringLiteral("localhost"));
        gds.setCertificateCheckInterval(1234);
        gds.setTrustListUpdateInterval(5678);

        d = QStringLiteral("key=%1-bit csr=%2 bytes state=%3")
                .arg(key.hasPrivateKey() ? 1024 : 0).arg(csr.size()).arg(int(gds.state()));
        return key.hasPrivateKey() && key.type() == QOpcUaKeyPair::KeyType::Rsa
            && csr.startsWith("-----BEGIN CERTIFICATE REQUEST-----")
            && request.subject().entry(QOpcUaX509DistinguishedName::Type::CommonName)
                   == QStringLiteral("qt-smoke")
            && asExtension->critical() && !basic->ca() && basic->pathLength() == 0
            && usage->keyUsage(QOpcUaX509ExtensionKeyUsage::KeyUsage::DigitalSignature)
            && extended->keyUsage(QOpcUaX509ExtensionExtendedKeyUsage::KeyUsage::TlsWebClientAuthentication)
            && alternative->entries().size() == 2
            && gds.backend() == QStringLiteral("open62541")
            && gds.dnsCertificateSigningRequestPreset() == QStringLiteral("localhost")
            && gds.certificateCheckInterval() == 1234
            && gds.trustListUpdateInterval() == 5678
            && gds.state() == QOpcUaGdsClient::State::Idle
            && gds.error() == QOpcUaGdsClient::Error::NoError;
#else
        r.skip(d, QStringLiteral("QtOpcUa security and GDS headers are not in this SDK"));
        return false;
#endif
    });

    r.check("opcua/scalar-value-types", [&](QString &d) {
#ifdef SMOKE_HAVE_OPCUA
        QOpcUaQualifiedName qualified(2, QStringLiteral("Temperature"));
        QOpcUaLocalizedText localized(QStringLiteral("en"), QStringLiteral("Boiler"));
        QOpcUaRange range(0.0, 100.0);
        QOpcUaComplexNumber complexNumber(1.5f, 2.5f);
        QOpcUaDoubleComplexNumber doubleComplex(1.5, 2.5);
        QOpcUaXValue xValue(3.0, 4.0f);
        QOpcUaExpandedNodeId expanded(QStringLiteral("urn:smoke"), QStringLiteral("ns=2;i=42"), 1);

        QOpcUaEUInformation euInfo;
        euInfo.setNamespaceUri(QStringLiteral("http://opcfoundation.org/UA/units"));
        euInfo.setUnitId(4408652);
        euInfo.setDisplayName(QOpcUaLocalizedText(QStringLiteral("en"), QStringLiteral("degC")));

        QOpcUaAxisInformation axis;
        axis.setEngineeringUnits(euInfo);
        axis.setEURange(range);
        axis.setTitle(localized);
        axis.setAxisScaleType(QOpcUa::AxisScale::Linear);

        QStringList misses;
        if (qualified.name() != QStringLiteral("Temperature") || qualified.namespaceIndex() != 2)
            misses << QStringLiteral("qualifiedname");
        if (localized.locale() != QStringLiteral("en")) misses << QStringLiteral("localizedtext");
        if (!qFuzzyCompare(range.high(), 100.0)) misses << QStringLiteral("range");
        if (!qFuzzyCompare(complexNumber.imaginary(), 2.5f)) misses << QStringLiteral("complex");
        if (!qFuzzyCompare(doubleComplex.imaginary(), 2.5)) misses << QStringLiteral("doublecomplex");
        if (!qFuzzyCompare(xValue.x(), 3.0)) misses << QStringLiteral("xvalue");
        if (expanded.serverIndex() != 1) misses << QStringLiteral("expandednodeid");
        if (euInfo.unitId() != 4408652) misses << QStringLiteral("euinformation");
        if (axis.axisScaleType() != QOpcUa::AxisScale::Linear) misses << QStringLiteral("axis");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QtOpcUa is not in this SDK (it has no Qt 5 counterpart)"));
        return false;
#endif
    });

    r.check("opcua/node-management-items", [&](QString &d) {
#ifdef SMOKE_HAVE_OPCUA
        const QOpcUaExpandedNodeId parent(QStringLiteral("ns=0;i=85"));
        const QOpcUaExpandedNodeId target(QStringLiteral("ns=2;i=42"));

        QOpcUaNodeCreationAttributes attributes;
        attributes.setDisplayName(QOpcUaLocalizedText(QStringLiteral("en"), QStringLiteral("Node")));
        attributes.setWriteMask(QOpcUa::WriteMaskBit::DisplayName);

        QOpcUaAddNodeItem addNode;
        addNode.setParentNodeId(parent);
        addNode.setRequestedNewNodeId(target);
        addNode.setBrowseName(QOpcUaQualifiedName(2, QStringLiteral("Node")));
        addNode.setNodeClass(QOpcUa::NodeClass::Variable);
        addNode.setNodeAttributes(attributes);

        QOpcUaAddReferenceItem addReference;
        addReference.setSourceNodeId(QStringLiteral("ns=0;i=85"));
        addReference.setReferenceTypeId(QStringLiteral("ns=0;i=35"));
        addReference.setIsForwardReference(true);
        addReference.setTargetNodeId(target);

        QOpcUaDeleteReferenceItem deleteReference;
        deleteReference.setSourceNodeId(QStringLiteral("ns=0;i=85"));
        deleteReference.setIsForwardReference(true);
        deleteReference.setTargetNodeId(target);

        QOpcUaReferenceDescription reference;
        reference.setRefTypeId(QStringLiteral("ns=0;i=35"));
        reference.setTargetNodeId(target);
        reference.setBrowseName(QOpcUaQualifiedName(2, QStringLiteral("Node")));
        reference.setDisplayName(QOpcUaLocalizedText(QStringLiteral("en"), QStringLiteral("Node")));

        QStringList misses;
        if (addNode.parentNodeId().nodeId() != parent.nodeId()) misses << QStringLiteral("addnode");
        if (addNode.nodeAttributes().displayName().text() != QStringLiteral("Node"))
            misses << QStringLiteral("attributes");
        if (!addReference.isForwardReference()) misses << QStringLiteral("addreference");
        if (deleteReference.targetNodeId().nodeId() != target.nodeId())
            misses << QStringLiteral("deletereference");
        if (reference.browseName().name() != QStringLiteral("Node"))
            misses << QStringLiteral("referencedescription");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QtOpcUa is not in this SDK"));
        return false;
#endif
    });

    r.check("opcua/read-write-and-browse-requests", [&](QString &d) {
#ifdef SMOKE_HAVE_OPCUA
        QOpcUaReadItem readItem(QStringLiteral("ns=2;i=42"));
        readItem.setAttribute(QOpcUa::NodeAttribute::Value);
        readItem.setIndexRange(QStringLiteral("0:3"));

        QOpcUaReadResult readResult;
        readResult.setNodeId(QStringLiteral("ns=2;i=42"));
        readResult.setStatusCode(QOpcUa::UaStatusCode::Good);
        readResult.setServerTimestamp(QDateTime::fromSecsSinceEpoch(0));

        QOpcUaWriteItem writeItem;
        writeItem.setNodeId(QStringLiteral("ns=2;i=42"));
        writeItem.setAttribute(QOpcUa::NodeAttribute::Value);
        writeItem.setValue(QVariant(7));

        QOpcUaWriteResult writeResult;
        writeResult.setNodeId(QStringLiteral("ns=2;i=42"));
        writeResult.setStatusCode(QOpcUa::UaStatusCode::Good);

        QOpcUaBrowseRequest browse;
        browse.setBrowseDirection(QOpcUaBrowseRequest::BrowseDirection::Forward);
        browse.setReferenceTypeId(QOpcUa::ReferenceTypeId::HierarchicalReferences);
        browse.setIncludeSubtypes(true);
        browse.setNodeClassMask(QOpcUa::NodeClass::Variable);

        QOpcUaRelativePathElement pathElement(QOpcUaQualifiedName(2, QStringLiteral("Node")),
                                              QOpcUa::ReferenceTypeId::HierarchicalReferences);
        QOpcUaBrowsePathTarget pathTarget;
        pathTarget.setTargetId(QOpcUaExpandedNodeId(QStringLiteral("ns=2;i=42")));
        pathTarget.setRemainingPathIndex((std::numeric_limits<quint32>::max)());

        QStringList misses;
        if (readItem.indexRange() != QStringLiteral("0:3")) misses << QStringLiteral("readitem");
        if (readResult.statusCode() != QOpcUa::UaStatusCode::Good) misses << QStringLiteral("readresult");
        if (writeItem.value().toInt() != 7) misses << QStringLiteral("writeitem");
        if (writeResult.nodeId() != QStringLiteral("ns=2;i=42")) misses << QStringLiteral("writeresult");
        if (!browse.includeSubtypes()) misses << QStringLiteral("browserequest");
        if (pathElement.targetName().name() != QStringLiteral("Node"))
            misses << QStringLiteral("relativepath");
        // A fully-resolved target is the documented meaning of a remaining
        // path index of UINT32_MAX.
        if (!pathTarget.isFullyResolved()) misses << QStringLiteral("browsepathtarget");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QtOpcUa is not in this SDK"));
        return false;
#endif
    });

    r.check("opcua/event-filter-operands", [&](QString &d) {
#ifdef SMOKE_HAVE_OPCUA
        QOpcUaLiteralOperand literal(QVariant(42), QOpcUa::Types::Int32);
        QOpcUaElementOperand element(1);

        QOpcUaAttributeOperand attributeOperand;
        attributeOperand.setNodeId(QStringLiteral("ns=0;i=2253"));
        attributeOperand.setAlias(QStringLiteral("server"));
        attributeOperand.setAttributeId(QOpcUa::NodeAttribute::Value);

        QOpcUaSimpleAttributeOperand simple;
        simple.setTypeId(QStringLiteral("ns=0;i=2041"));
        simple.setBrowsePath({ QOpcUaQualifiedName(0, QStringLiteral("Message")) });
        simple.setAttributeId(QOpcUa::NodeAttribute::Value);

        QOpcUaContentFilterElement filterElement;
        filterElement.setFilterOperator(QOpcUaContentFilterElement::FilterOperator::GreaterThan);
        filterElement.setFilterOperands({ QVariant::fromValue(literal),
                                          QVariant::fromValue(element) });

        QOpcUaContentFilterElementResult elementResult;
        elementResult.setStatusCode(QOpcUa::UaStatusCode::Good);
        elementResult.setOperandStatusCodes({ QOpcUa::UaStatusCode::Good });

        QOpcUaEventFilterResult filterResult;
        filterResult.setSelectClauseResults({ QOpcUa::UaStatusCode::Good });
        filterResult.setWhereClauseResults({ elementResult });

        QOpcUaMonitoringParameters monitoring(100.0);
        monitoring.setQueueSize(10);
        monitoring.setDiscardOldest(true);
        QOpcUaMonitoringParameters::DataChangeFilter dataChange;
        dataChange.setTrigger(QOpcUaMonitoringParameters::DataChangeFilter::DataChangeTrigger::StatusOrValue);
        dataChange.setDeadbandType(QOpcUaMonitoringParameters::DataChangeFilter::DeadbandType::Absolute);
        dataChange.setDeadbandValue(0.5);
        monitoring.setFilter(dataChange);
        QOpcUaMonitoringParameters::EventFilter eventFilter;
        eventFilter.setSelectClauses({ simple });
        eventFilter.setWhereClause({ filterElement });

        QStringList misses;
        if (literal.value().toInt() != 42) misses << QStringLiteral("literaloperand");
        if (element.index() != 1) misses << QStringLiteral("elementoperand");
        if (attributeOperand.alias() != QStringLiteral("server")) misses << QStringLiteral("attributeoperand");
        if (simple.browsePath().size() != 1) misses << QStringLiteral("simpleoperand");
        if (filterElement.filterOperands().size() != 2) misses << QStringLiteral("filterelement");
        if (!filterResult.isGood()) misses << QStringLiteral("filterresult");
        if (monitoring.queueSize() != 10) misses << QStringLiteral("monitoring");
        if (eventFilter.selectClauses().size() != 1) misses << QStringLiteral("eventfilter");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QtOpcUa is not in this SDK"));
        return false;
#endif
    });

    r.check("opcua/data-history-and-encoding", [&](QString &d) {
#ifdef SMOKE_HAVE_OPCUA
        QOpcUaDataValue dataValue;
        dataValue.setValue(QVariant(1.25));
        dataValue.setStatusCode(QOpcUa::UaStatusCode::Good);
        dataValue.setServerTimestamp(QDateTime::fromSecsSinceEpoch(1));
        dataValue.setSourceTimestamp(QDateTime::fromSecsSinceEpoch(2));

        QOpcUaHistoryData history(QStringLiteral("ns=2;i=42"));
        history.setStatusCode(QOpcUa::UaStatusCode::Good);

        QOpcUaHistoryReadRawRequest rawRequest;
        rawRequest.setStartTimestamp(QDateTime::fromSecsSinceEpoch(0));
        rawRequest.setEndTimestamp(QDateTime::fromSecsSinceEpoch(60));
        rawRequest.setNumValuesPerNode(10);
        rawRequest.setReturnBounds(true);
        rawRequest.addNodeToRead(QOpcUaReadItem(QStringLiteral("ns=2;i=42")));

        QOpcUaMultiDimensionalArray array(QVariantList{ 1, 2, 3, 4 }, QList<quint32>{ 2, 2 });

        QOpcUaExtensionObject extension;
        extension.setBinaryEncodedBody(QByteArrayLiteral("\x01\x02"), QStringLiteral("ns=0;i=1"));

        QByteArray buffer;
        QOpcUaBinaryDataEncoding encoding(&buffer);
        encoding.encode<quint32>(7u);

        QOpcUaArgument argument;
        argument.setName(QStringLiteral("input"));
        argument.setDataTypeId(QStringLiteral("ns=0;i=6"));
        argument.setValueRank(-1);

        QStringList misses;
        if (!qFuzzyCompare(dataValue.value().toDouble(), 1.25)) misses << QStringLiteral("datavalue");
        if (history.nodeId() != QStringLiteral("ns=2;i=42")) misses << QStringLiteral("historydata");
        if (rawRequest.numValuesPerNode() != 10 || rawRequest.nodesToRead().size() != 1)
            misses << QStringLiteral("historyrequest");
        if (!array.isValid() || array.arrayDimensions().size() != 2)
            misses << QStringLiteral("multidimensional");
        if (extension.encoding() != QOpcUaExtensionObject::Encoding::ByteString)
            misses << QStringLiteral("extensionobject");
        if (buffer.size() != 4) misses << QStringLiteral("binaryencoding");
        if (argument.valueRank() != -1) misses << QStringLiteral("argument");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QtOpcUa is not in this SDK"));
        return false;
#endif
    });

    r.check("opcua/application-and-security-descriptions", [&](QString &d) {
#ifdef SMOKE_HAVE_OPCUA
        QOpcUaApplicationDescription application;
        application.setApplicationUri(QStringLiteral("urn:qt-smoke:client"));
        application.setProductUri(QStringLiteral("urn:qt-smoke:product"));
        application.setApplicationName(QOpcUaLocalizedText(QStringLiteral("en"),
                                                           QStringLiteral("qt-smoke")));
        application.setApplicationType(QOpcUaApplicationDescription::ApplicationType::Client);

        QOpcUaApplicationIdentity identity;
        identity.setApplicationUri(QStringLiteral("urn:qt-smoke:client"));
        identity.setApplicationName(QStringLiteral("qt-smoke"));
        identity.setApplicationType(QOpcUaApplicationDescription::ApplicationType::Client);

        QOpcUaApplicationRecordDataType record;
        record.setApplicationUri(QStringLiteral("urn:qt-smoke:client"));
        record.setApplicationType(QOpcUaApplicationDescription::ApplicationType::Client);
        record.setDiscoveryUrls({ QStringLiteral("opc.tcp://localhost:4840") });

        QOpcUaUserTokenPolicy policy;
        policy.setPolicyId(QStringLiteral("open62541-anonymous-policy"));
        policy.setTokenType(QOpcUaUserTokenPolicy::TokenType::Anonymous);

        QOpcUaEndpointDescription endpoint;
        endpoint.setEndpointUrl(QStringLiteral("opc.tcp://localhost:4840"));
        endpoint.setServer(application);
        endpoint.setSecurityMode(QOpcUaEndpointDescription::MessageSecurityMode::None);
        endpoint.setUserIdentityTokens({ policy });

        QOpcUaPkiConfiguration pki;
        pki.setClientCertificateFile(QStringLiteral("/nonexistent/client.der"));
        pki.setPrivateKeyFile(QStringLiteral("/nonexistent/client.pem"));
        pki.setTrustListDirectory(QStringLiteral("/nonexistent/trusted"));

        QOpcUaAuthenticationInformation authentication;
        authentication.setAnonymousAuthentication();

        QOpcUaErrorState errorState;
        errorState.setConnectionStep(QOpcUaErrorState::ConnectionStep::OpenSecureChannel);
        errorState.setErrorCode(QOpcUa::UaStatusCode::BadInternalError);
        errorState.setClientSideError(true);

        QStringList misses;
        if (application.applicationType() != QOpcUaApplicationDescription::ApplicationType::Client)
            misses << QStringLiteral("applicationdescription");
        if (identity.applicationName() != QStringLiteral("qt-smoke"))
            misses << QStringLiteral("applicationidentity");
        if (record.discoveryUrls().size() != 1) misses << QStringLiteral("applicationrecord");
        if (endpoint.userIdentityTokens().size() != 1) misses << QStringLiteral("endpointdescription");
        if (policy.tokenType() != QOpcUaUserTokenPolicy::TokenType::Anonymous)
            misses << QStringLiteral("usertokenpolicy");
        if (pki.privateKeyFile().isEmpty()) misses << QStringLiteral("pkiconfiguration");
        if (authentication.authenticationType() != QOpcUaUserTokenPolicy::TokenType::Anonymous)
            misses << QStringLiteral("authenticationinformation");
        if (!errorState.isClientSideError()) misses << QStringLiteral("errorstate");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QtOpcUa is not in this SDK"));
        return false;
#endif
    });

    r.check("opcua/provider-client-and-node", [&](QString &d) {
#ifdef SMOKE_HAVE_OPCUA
        // QOpcUaPlugin is the backend interface; QOpcUaProvider is what loads
        // one. Neither needs a server, but a client only exists if a backend
        // plugin is present - and a static build with no backend configured
        // legitimately has none.
        QOpcUaProvider provider;
        const QStringList backends = QOpcUaProvider::availableBackends();
        if (backends.isEmpty()) {
            r.skip(d, QStringLiteral("no OPC UA backend plugin in this build"));
            return false;
        }
        QScopedPointer<QOpcUaClient> client(provider.createClient(backends.first()));
        if (client.isNull()) {
            r.skip(d, QStringLiteral("backend listed but createClient() returned null"));
            return false;
        }
        client->setApplicationIdentity(QOpcUaApplicationIdentity());
        QScopedPointer<QOpcUaNode> node(client->node(QStringLiteral("ns=0;i=84")));
        // Without a connection the node request cannot be served; a null node
        // is the correct outcome, not a failure.
        return client->state() == QOpcUaClient::ClientState::Disconnected
            && client->backend() == backends.first()
            && (node.isNull() || !node->nodeId().isEmpty());
#else
        r.skip(d, QStringLiteral("QtOpcUa is not in this SDK"));
        return false;
#endif
    });

    r.check("opcua/history-response-and-struct-handler", [&](QString &d) {
#ifdef SMOKE_HAVE_OPCUA
        // Two classes the value-type checks cannot reach. QOpcUaHistoryReadResponse
        // takes a private implementation type, so only a client reading history makes
        // one; its shape is checked.
        const bool responseIsQObject =
            std::is_base_of<QObject, QOpcUaHistoryReadResponse>::value;

        // The struct handler does have a public constructor, but it takes a
        // client, so it needs the same backend the check below needs.
        QOpcUaProvider provider;
        const QStringList backends = QOpcUaProvider::availableBackends();
        if (backends.isEmpty()) {
            r.skip(d, QStringLiteral("no OPC UA backend plugin in this build"));
            return false;
        }
        QScopedPointer<QOpcUaClient> client(provider.createClient(backends.first()));
        if (client.isNull()) {
            r.skip(d, QStringLiteral("backend listed but createClient() returned null"));
            return false;
        }
        QOpcUaGenericStructHandler handler(client.data());
        d = QStringLiteral("handler on the %1 backend, history response is a QObject: %2")
                .arg(backends.first()).arg(int(responseIsQObject));
        return responseIsQObject && handler.parent() == nullptr
            && handler.metaObject()->inherits(&QObject::staticMetaObject);
#else
        r.skip(d, QStringLiteral("QtOpcUa is not in this SDK"));
        return false;
#endif
    });
}
