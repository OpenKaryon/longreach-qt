// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// QTextDocument's structural/formatting classes (usable with no widget - a
// QTextDocument is a plain data structure, and even its layout classes work
// headlessly), the input validators (QtGui, not QtWidgets - no widget
// needed either), and QRegularExpression's match/iterator types.
#include "../common/smokecheck.h"

#include <QTextDocument>
#include <QTextCursor>
#include <QTextBlock>
#include <QTextFrame>
#include <QTextTable>
#include <QTextObject>
#include <QTextFormat>
#include <QTextLayout>
#include <QTextLine>
#include <QTextOption>
#if QT_VERSION_MAJOR < 6
#include <QTextCodec>
#endif
#if QT_VERSION_MAJOR < 6
#include <QTextDecoder>
#endif
#if QT_VERSION_MAJOR < 6
#include <QTextEncoder>
#endif
#include <QTextDocumentWriter>

#include <QIntValidator>
#include <QDoubleValidator>
#if QT_VERSION_MAJOR < 6
#include <QRegExpValidator>
#endif
#if SMOKE_QT5
#include <QRegularExpressionValidator>

#include <QRegularExpression>
#include <QRegularExpressionMatch>
#include <QRegularExpressionMatchIterator>
#endif

#include <QBuffer>

void checkTextDocumentStructure(SmokeReporter &r)
{
    r.check("textdoc/frame-table-block-format", [&](QString &d) {
        QTextDocument doc;
        QTextCursor cursor(&doc);
        QTextTableFormat tableFormat;
        tableFormat.setBorder(1);
        QTextTable *table = cursor.insertTable(2, 2, tableFormat);
        QTextTableCell cell = table->cellAt(0, 0);
        QTextBlockFormat blockFormat;
        blockFormat.setAlignment(Qt::AlignCenter);
        cursor.setBlockFormat(blockFormat);
        // QTextFrame/QTextObject: the table (and the document's root frame)
        // are reached through the real base every text "object" derives from.
        QTextObject *tableAsObject = table;
        QTextFrame *rootFrame = doc.rootFrame();
        return table->rows() == 2 && table->columns() == 2 && cell.row() == 0
            && cursor.blockFormat().alignment() == Qt::AlignCenter
            && tableAsObject != nullptr && rootFrame != nullptr;
    });
    r.check("textdoc/frameformat-imageformat-length", [&](QString &d) {
        QTextFrameFormat frameFormat;
        frameFormat.setBorder(2);
        QTextImageFormat imageFormat;
        imageFormat.setName(QStringLiteral("icon.png"));
        QTextLength length(QTextLength::PercentageLength, 50);
        QTextTableCellFormat cellFormat;
        cellFormat.setTopPadding(4);
        return frameFormat.border() == 2 && imageFormat.name() == QStringLiteral("icon.png")
            && length.type() == QTextLength::PercentageLength && cellFormat.topPadding() == 4;
    });
    r.check("textdoc/layout-line-option", [&](QString &d) {
        QTextLayout layout(QStringLiteral("hello world"));
        QTextOption option;
        option.setWrapMode(QTextOption::WordWrap);
        layout.setTextOption(option);
        layout.beginLayout();
        QTextLine line = layout.createLine();
        line.setLineWidth(1000);
        layout.endLayout();
        return line.isValid() && layout.textOption().wrapMode() == QTextOption::WordWrap;
    });
    r.check("textdoc/codec-decoder-encoder", [&](QString &d) {
#if QT_VERSION_MAJOR < 6
        QTextCodec *codec = QTextCodec::codecForName("UTF-8");
        if (!codec) { d = "no UTF-8 codec"; return false; }
        QTextDecoder decoder(codec);
        QTextEncoder encoder(codec);
#else
        QStringDecoder decoder(QStringConverter::Utf8);
        QStringEncoder encoder(QStringConverter::Utf8);
#endif
#if QT_VERSION_MAJOR < 6
        QString decoded = decoder.toUnicode(QByteArray("caf\xc3\xa9"));
        QByteArray encoded = encoder.fromUnicode(QStringLiteral("café"));
#else
        // QStringDecoder/QStringEncoder convert through operator().
        QString decoded = decoder(QByteArray("caf\xc3\xa9"));
        QByteArray encoded = encoder(QStringLiteral("café"));
#endif
        return decoded == QStringLiteral("café") && !encoded.isEmpty();
    });
    r.check("textdoc/document-writer", [&](QString &d) {
        QTextDocument doc;
        doc.setPlainText(QStringLiteral("plain text output"));
        QByteArray out;
        QBuffer buf(&out);
        buf.open(QIODevice::WriteOnly);
        QTextDocumentWriter writer(&buf, "plaintext");
        bool ok = writer.write(&doc);
        return ok && out.contains("plain text output");
    });
}

void checkValidatorsAndRegexMatch(SmokeReporter &r)
{
    r.check("validators/int-double-regexp-regularexpression", [&](QString &d) {
        QIntValidator intV(0, 100);
        QDoubleValidator doubleV(0.0, 1.0, 2);
#if QT_VERSION_MAJOR < 6
        QRegExpValidator rxV(QRegExp("[a-z]+"));
#else
        // QRegExp and its validator moved to Qt5Compat; the
        // QRegularExpression one below is the surviving equivalent.
        QRegularExpressionValidator rxV(QRegularExpression("[a-z]+"));
#endif
#if SMOKE_QT5
        QRegularExpressionValidator reV(QRegularExpression("[0-9]+"));
#endif
        QString s1 = "50"; int pos = 0;
        QString s2 = "abc";
        QString s3 = "123";
        return intV.validate(s1, pos) == QValidator::Acceptable
            && doubleV.decimals() == 2
            && rxV.validate(s2, pos) == QValidator::Acceptable
#if SMOKE_QT5
            && reV.validate(s3, pos) == QValidator::Acceptable;
#else
            ;
#endif
    });
    r.check("regex/match-and-iterator", [&](QString &d) {
#if SMOKE_QT5
        QRegularExpression re("\\d+");
        QRegularExpressionMatch match = re.match(QStringLiteral("a12b34"));
        if (!match.hasMatch()) { d = "no match"; return false; }
        QRegularExpressionMatchIterator it = re.globalMatch(QStringLiteral("a12b34"));
        int count = 0;
        while (it.hasNext()) { it.next(); ++count; }
        return match.captured() == QStringLiteral("12") && count == 2;
#else
        r.skip(d, QStringLiteral("QRegularExpression match/iterator arrived in Qt 5"));
        return false;
#endif
    });
}
