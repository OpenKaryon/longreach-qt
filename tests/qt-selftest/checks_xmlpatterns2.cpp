// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Remaining QtXmlPatterns classes not covered by checkXmlPatterns() in
// checks_extra.cpp: message/URI resolution hooks (both are abstract, one
// virtual method each - a trivial subclass is the real way an app customises
// query error reporting or relative-URI resolution), query result iteration,
// and serializing a query's result back to XML/indented XML.
#include "../common/smokecheck.h"
#include <QVector>

#ifdef SMOKE_HAVE_XMLPATTERNS
#include <QXmlQuery>
#endif
#ifdef SMOKE_HAVE_XMLPATTERNS
#include <QXmlResultItems>
#endif
#ifdef SMOKE_HAVE_XMLPATTERNS
#include <QXmlItem>
#endif
#ifdef SMOKE_HAVE_XMLPATTERNS
#include <QAbstractMessageHandler>
#endif
#ifdef SMOKE_HAVE_XMLPATTERNS
#include <QAbstractUriResolver>
#endif
#ifdef SMOKE_HAVE_XMLPATTERNS
#include <QXmlSerializer>
#endif
#ifdef SMOKE_HAVE_XMLPATTERNS
#include <QXmlFormatter>
#endif
#ifdef SMOKE_HAVE_XMLPATTERNS
#include <QAbstractXmlNodeModel>
#endif
#ifdef SMOKE_HAVE_XMLPATTERNS
#include <QSimpleXmlNodeModel>
#endif
#ifdef SMOKE_HAVE_XMLPATTERNS
#include <QAbstractXmlReceiver>
#endif
#include <QBuffer>

#if defined(SMOKE_HAVE_XMLPATTERNS)

namespace {

class CountingMessageHandler : public QAbstractMessageHandler
{
public:
    int messages = 0;
protected:
    void handleMessage(QtMsgType, const QString &, const QUrl &, const QSourceLocation &) override {
        ++messages;
    }
};

class FixedUriResolver : public QAbstractUriResolver
{
public:
    QUrl resolve(const QUrl &, const QUrl &) const override {
        return QUrl(QStringLiteral("https://example.com/resolved"));
    }
};

// A one-element node model: the documented way to expose non-XML data to
// XQuery, checked through the interface directly.
class SingleElementNodeModel : public QAbstractXmlNodeModel
{
public:
    explicit SingleElementNodeModel(const QXmlNamePool &pool) : m_pool(pool) {}

    QUrl baseUri(const QXmlNodeModelIndex &) const override { return QUrl(); }
    QUrl documentUri(const QXmlNodeModelIndex &) const override { return QUrl(); }
    QXmlNodeModelIndex::NodeKind kind(const QXmlNodeModelIndex &) const override {
        return QXmlNodeModelIndex::Element;
    }
    QXmlNodeModelIndex::DocumentOrder compareOrder(const QXmlNodeModelIndex &,
                                                   const QXmlNodeModelIndex &) const override {
        return QXmlNodeModelIndex::Is;
    }
    QXmlNodeModelIndex root(const QXmlNodeModelIndex &n) const override { return n; }
    QXmlName name(const QXmlNodeModelIndex &) const override {
        return QXmlName(m_pool, QStringLiteral("root"));
    }
    QString stringValue(const QXmlNodeModelIndex &) const override { return QStringLiteral("value"); }
    QVariant typedValue(const QXmlNodeModelIndex &n) const override { return stringValue(n); }
    QVector<QXmlName> namespaceBindings(const QXmlNodeModelIndex &) const override { return {}; }
    QXmlNodeModelIndex elementById(const QXmlName &) const override { return QXmlNodeModelIndex(); }
    QVector<QXmlNodeModelIndex> nodesByIdref(const QXmlName &) const override { return {}; }
    QXmlNodeModelIndex nextFromSimpleAxis(SimpleAxis, const QXmlNodeModelIndex &) const override {
        return QXmlNodeModelIndex();   // a single node has no parent/children/siblings
    }
    QVector<QXmlNodeModelIndex> attributes(const QXmlNodeModelIndex &) const override { return {}; }

    QXmlNodeModelIndex rootNode() const { return createIndex(qint64(1)); }

private:
    // QXmlName's constructor wants a non-const QXmlNamePool&; name() is const
    // (per the base's pure virtual signature), so the pool handle needs to be
    // mutable to hand it out from there.
    mutable QXmlNamePool m_pool;
};

// QSimpleXmlNodeModel already implements baseUri/namespaceBindings/
// stringValue/elementById/nodesByIdref - a subclass needs the rest.
class SingleElementSimpleModel : public QSimpleXmlNodeModel
{
public:
    explicit SingleElementSimpleModel(const QXmlNamePool &pool) : QSimpleXmlNodeModel(pool) {}

    QUrl documentUri(const QXmlNodeModelIndex &) const override { return QUrl(); }
    QXmlNodeModelIndex::NodeKind kind(const QXmlNodeModelIndex &) const override {
        return QXmlNodeModelIndex::Element;
    }
    QXmlNodeModelIndex::DocumentOrder compareOrder(const QXmlNodeModelIndex &,
                                                   const QXmlNodeModelIndex &) const override {
        return QXmlNodeModelIndex::Is;
    }
    QXmlNodeModelIndex root(const QXmlNodeModelIndex &n) const override { return n; }
    QXmlName name(const QXmlNodeModelIndex &) const override {
        return QXmlName(namePool(), QStringLiteral("root"));
    }
    QVariant typedValue(const QXmlNodeModelIndex &n) const override { return stringValue(n); }
    QXmlNodeModelIndex nextFromSimpleAxis(SimpleAxis, const QXmlNodeModelIndex &) const override {
        return QXmlNodeModelIndex();
    }
    QVector<QXmlNodeModelIndex> attributes(const QXmlNodeModelIndex &) const override { return {}; }

    QXmlNodeModelIndex rootNode() const { return createIndex(qint64(1)); }
};

// QAbstractXmlReceiver is what QXmlQuery::evaluateTo() drives; a counting
// receiver exercises it.
class CountingReceiver : public QAbstractXmlReceiver
{
public:
    int elements = 0, characters_ = 0;
    void startElement(const QXmlName &) override { ++elements; }
    void endElement() override {}
    void attribute(const QXmlName &, const QStringRef &) override {}
    void comment(const QString &) override {}
    void characters(const QStringRef &) override { ++characters_; }
    void startDocument() override {}
    void endDocument() override {}
    void processingInstruction(const QXmlName &, const QString &) override {}
    void atomicValue(const QVariant &) override {}
    void namespaceBinding(const QXmlName &) override {}
    void startOfSequence() override {}
    void endOfSequence() override {}
};

} // namespace

void checkXmlPatternsExtras(SmokeReporter &r)
{
    r.check("xmlpatterns/message-handler-and-uri-resolver", [&](QString &d) {
        CountingMessageHandler handler;
        FixedUriResolver resolver;
        QXmlQuery query;
        query.setMessageHandler(&handler);
        query.setUriResolver(&resolver);
        // An invalid query triggers a compile-error message through the handler.
        query.setQuery(QStringLiteral("this is not xquery"));
        return handler.messages > 0 && resolver.resolve(QUrl(), QUrl()).toString().contains("resolved");
    });
    r.check("xmlpatterns/result-items-and-xmlitem", [&](QString &d) {
        QXmlQuery query;
        query.setQuery(QStringLiteral("(1, 2, 3)"));
        QXmlResultItems items;
        query.evaluateTo(&items);
        int count = 0;
        QXmlItem item = items.next();
        while (!item.isNull()) {
            ++count;
            item = items.next();
        }
        return count == 3 && !items.hasError();
    });
    r.check("xmlpatterns/serializer-and-formatter", [&](QString &d) {
        QXmlQuery query;
        query.setQuery(QStringLiteral("<root><item>a</item></root>"));

        QByteArray plain;
        QBuffer plainBuf(&plain);
        plainBuf.open(QIODevice::WriteOnly);
        QXmlSerializer serializer(query, &plainBuf);
        if (!query.evaluateTo(&serializer)) { d = "serializer evaluateTo failed"; return false; }

        QByteArray formatted;
        QBuffer formattedBuf(&formatted);
        formattedBuf.open(QIODevice::WriteOnly);
        QXmlFormatter formatter(query, &formattedBuf);
        if (!query.evaluateTo(&formatter)) { d = "formatter evaluateTo failed"; return false; }

        return plain.contains("<root>") && formatted.contains("<root>")
            && formatted.size() >= plain.size();   // formatter adds indentation/newlines
    });
    r.check("xmlpatterns/nodemodelindex-value-type", [&](QString &d) {
        QXmlNodeModelIndex index;
        return index.isNull();
    });
    r.check("xmlpatterns/custom-node-model", [&](QString &d) {
        QXmlNamePool pool;
        SingleElementNodeModel model(pool);
        QXmlNodeModelIndex idx = model.rootNode();
        return model.kind(idx) == QXmlNodeModelIndex::Element
            && model.name(idx).localName(pool) == QStringLiteral("root")
            && model.stringValue(idx) == QStringLiteral("value")
            && model.root(idx) == idx && model.attributes(idx).isEmpty();
    });
    r.check("xmlpatterns/custom-receiver", [&](QString &d) {
        QXmlQuery query;
        query.setQuery(QStringLiteral("<root><item>a</item><item>b</item></root>"));
        CountingReceiver receiver;
        if (!query.evaluateTo(&receiver)) { d = "evaluateTo failed"; return false; }
        return receiver.elements >= 2;   // root + at least one item
    });
    r.check("xmlpatterns/custom-simple-node-model", [&](QString &d) {
        QXmlNamePool pool;
        SingleElementSimpleModel model(pool);
        QXmlNodeModelIndex idx = model.rootNode();
        return model.kind(idx) == QXmlNodeModelIndex::Element
            && model.name(idx).localName(pool) == QStringLiteral("root")
            && model.baseUri(idx).isEmpty() && model.root(idx) == idx;
    });
}

#else   // the checks above have no counterpart to run against

void checkXmlPatternsExtras(SmokeReporter &r)
{
    r.check("xmlpatterns/extras", [&](QString &d) {
        r.skip(d, QStringLiteral("QtXmlPatterns is not in this SDK (Qt 6 dropped XQuery/XSLT/XML Schema)"));
        return false;
    });
}

#endif
