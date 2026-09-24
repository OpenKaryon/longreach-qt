// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// QtCore5Compat - the Qt 5 classes Qt 6 kept in a compatibility module rather
// than dropping outright: the SAX reader family, QRegExp, QTextCodec and
// QLinkedList.
//
// This kit builds the module into every Qt 6 SDK, so it is part of what it
// ships and belongs under test. The checks elsewhere in the suite deliberately
// use the modern replacements on Qt 6 (QRegularExpression, QStringConverter,
// QXmlStreamReader) and report the Qt 5 spellings as SKIP; this file is the
// other half of that story - it covers the compatibility classes as
// themselves, and only where the module is actually present.
#include "../common/smokecheck.h"

#include <QBuffer>
#include <QByteArray>
#include <QString>

#ifdef SMOKE_HAVE_CORE5COMPAT
#include <QLinkedList>
#include <QRegExp>
#include <QStringRef>
#include <QTextCodec>
#include <QXmlDefaultHandler>
#include <QXmlInputSource>
#include <QXmlNamespaceSupport>
#include <QXmlSimpleReader>

namespace {

// The documented way to consume the SAX reader: subclass the default handler,
// which implements every one of the handler interfaces, and override what you
// care about.
class SmokeSaxHandler : public QXmlDefaultHandler
{
public:
    // The locator is valid only during a callback, so the line number is read in
    // startElement; the reader keeps ownership.
    void setDocumentLocator(QXmlLocator *locator) override
    {
        m_locator = locator;
        QXmlDefaultHandler::setDocumentLocator(locator);
    }

    bool startElement(const QString &, const QString &localName, const QString &,
                      const QXmlAttributes &atts) override
    {
        ++elements;
        if (m_locator && firstElementLine < 0) {
            firstElementLine = m_locator->lineNumber();
            firstElementColumn = m_locator->columnNumber();
        }
        if (localName == QLatin1String("item"))
            lastId = atts.value(QStringLiteral("id"));
        return true;
    }

    bool characters(const QString &text) override
    {
        collected += text.trimmed();
        return true;
    }

    bool fatalError(const QXmlParseException &exception) override
    {
        error = exception.message();
        return false;
    }

    int elements = 0;
    int firstElementLine = -1;
    int firstElementColumn = -1;
    QString lastId;
    QString collected;
    QString error;

private:
    QXmlLocator *m_locator = nullptr;
};

} // namespace
#endif

void checkCore5Compat(SmokeReporter &r)
{
    r.check("core5compat/sax-reader-and-handlers", [&](QString &d) {
#ifdef SMOKE_HAVE_CORE5COMPAT
        SmokeSaxHandler handler;
        QXmlSimpleReader reader;
        // The handler interfaces are set separately even though one object
        // implements them all - that separation is the point of the SAX API.
        QXmlContentHandler *contentHandler = &handler;
        QXmlErrorHandler *errorHandler = &handler;
        QXmlDTDHandler *dtdHandler = &handler;
        QXmlEntityResolver *entityResolver = &handler;
        QXmlDeclHandler *declHandler = &handler;
        QXmlLexicalHandler *lexicalHandler = &handler;
        reader.setContentHandler(contentHandler);
        reader.setErrorHandler(errorHandler);
        reader.setDTDHandler(dtdHandler);
        reader.setEntityResolver(entityResolver);
        reader.setDeclHandler(declHandler);
        reader.setLexicalHandler(lexicalHandler);

        QXmlReader *readerBase = &reader;

        QByteArray xml = QByteArrayLiteral(
            "<root xmlns:p=\"urn:test\"><item id=\"7\">hello</item></root>");
        QBuffer buffer(&xml);
        buffer.open(QIODevice::ReadOnly);
        QXmlInputSource source(&buffer);

        const bool parsed = readerBase->parse(&source);

        QXmlNamespaceSupport namespaces;
        namespaces.setPrefix(QStringLiteral("p"), QStringLiteral("urn:test"));

        QStringList misses;
        if (!parsed) misses << QStringLiteral("parse:") + handler.error;
        if (handler.elements != 2) misses << QStringLiteral("elements");
        if (handler.lastId != QStringLiteral("7")) misses << QStringLiteral("attributes");
        if (handler.collected != QStringLiteral("hello")) misses << QStringLiteral("characters");
        // One line of input, so the position is only interesting in its column,
        // and all that is asserted is that the locator tracked something.
        if (handler.firstElementLine != 1) misses << QStringLiteral("locator-line");
        if (handler.firstElementColumn < 1) misses << QStringLiteral("locator-column");
        if (namespaces.uri(QStringLiteral("p")) != QStringLiteral("urn:test"))
            misses << QStringLiteral("namespacesupport");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QtCore5Compat is not in this SDK"));
        return false;
#endif
    });

    r.check("core5compat/regexp-codec-linkedlist", [&](QString &d) {
#ifdef SMOKE_HAVE_CORE5COMPAT
        QRegExp rx(QStringLiteral("(\\w+)@(\\w+)"));
        const int matchedAt = rx.indexIn(QStringLiteral("a@b"));

        QTextCodec *codec = QTextCodec::codecForName("UTF-8");
        QLinkedList<int> linked;
        linked << 1 << 2 << 3;
        QLinkedListIterator<int> it(linked);
        int walked = 0;
        while (it.hasNext())
            walked += it.next();
        QMutableLinkedListIterator<int> mutableIt(linked);
        while (mutableIt.hasNext()) {
            if (mutableIt.next() == 2)
                mutableIt.remove();
        }

        const QString owned = QStringLiteral("qt-smoke");
        QStringRef ref(&owned, 3, 5);

        QStringList misses;
        if (matchedAt != 0 || rx.cap(2) != QStringLiteral("b")) misses << QStringLiteral("regexp");
        if (!codec || codec->name() != QByteArrayLiteral("UTF-8")) misses << QStringLiteral("codec");
        if (walked != 6) misses << QStringLiteral("linkedlist");
        if (linked.size() != 2) misses << QStringLiteral("mutableiterator");
        if (ref.toString() != QStringLiteral("smoke")) misses << QStringLiteral("stringref");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QtCore5Compat is not in this SDK"));
        return false;
#endif
    });
}
