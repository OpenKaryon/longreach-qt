// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Item models & proxies (no view), and rich-text document/cursor/layout.
// Headless.
#include "../common/smokecheck.h"
#include "checks.h"

#include <QStandardItemModel>
#include <QStandardItem>
#include <QStringListModel>
#include <QSortFilterProxyModel>
#include <QRegExp>
#include <QIdentityProxyModel>
#include <QItemSelectionModel>
#include <QItemSelection>
#include <QModelIndex>
#include <QPersistentModelIndex>
#if SMOKE_QT5
#include <QTransposeProxyModel>
#endif

#include <QTextDocument>
#include <QTextCursor>
#include <QTextBlock>
#include <QTextCharFormat>
#include <QTextTable>
#include <QTextList>
#include <QTextDocumentFragment>

void checkItemModels(SmokeReporter &r)
{
    r.check("model/standarditemmodel", [&r](QString &d) {
        QStandardItemModel m(0,2);
        m.setHorizontalHeaderLabels(QStringList() << "name" << "value");
        for (int i=0;i<5;++i)
            m.appendRow(QList<QStandardItem *>()
                        << new QStandardItem(QString("row%1").arg(i))
                        << new QStandardItem(QString::number(i*10)));
        if (m.rowCount()!=5 || m.columnCount()!=2) { d="dims"; return false; }
        QModelIndex idx = m.index(2,1);
        return m.data(idx).toString()=="20" && m.item(0,0)->text()=="row0";
    });
    r.check("model/stringlistmodel", [&r](QString &d) {
        QStringListModel m; m.setStringList(QStringList() << "c" << "a" << "b");
        return m.rowCount()==3 && m.data(m.index(0), Qt::DisplayRole).toString()=="c";
    });
    r.check("model/sortfilterproxy", [&r](QString &d) {
        QStringListModel src; src.setStringList(QStringList() << "apple" << "banana" << "cherry" << "avocado");
        QSortFilterProxyModel proxy; proxy.setSourceModel(&src);
#if SMOKE_QT5
        proxy.setFilterRegularExpression("^a");   // only items starting with a
#else
        proxy.setFilterRegExp(QRegExp("^a"));
#endif
        proxy.sort(0);
        if (proxy.rowCount()!=2) { d=QString("rows=%1").arg(proxy.rowCount()); return false; }
        return proxy.data(proxy.index(0,0)).toString()=="apple"; // sorted
    });
    r.check("model/identityproxy", [&r](QString &d) {
        QStringListModel src; src.setStringList(QStringList() << "x" << "y");
        QIdentityProxyModel id; id.setSourceModel(&src);
        return id.rowCount()==2 && id.data(id.index(1,0)).toString()=="y";
    });
    r.check("model/selection", [&r](QString &d) {
        QStandardItemModel m(4,1);
        QItemSelectionModel sel(&m);
        sel.select(QItemSelection(m.index(0,0), m.index(2,0)), QItemSelectionModel::Select);
        return sel.selectedIndexes().size()==3 && sel.isSelected(m.index(1,0));
    });
    r.check("model/persistent-transpose", [&](QString &d) {
        QStandardItemModel model(2, 3);
        model.setData(model.index(1, 2), QStringLiteral("cell"));
        QPersistentModelIndex persistent(model.index(1, 2));
#if SMOKE_QT5
        QTransposeProxyModel transpose;
        transpose.setSourceModel(&model);
        QModelIndex transposed = transpose.index(2, 1);
        return persistent.isValid()
            && persistent.data().toString() == QStringLiteral("cell")
            && transposed.data().toString() == QStringLiteral("cell");
#else
        r.skip(d, QStringLiteral("QTransposeProxyModel arrived in Qt 5"));
        return false;
#endif
    });
}

void checkText(SmokeReporter &r)
{
    r.check("text/document+cursor", [&r](QString &d) {
        QTextDocument doc;
        QTextCursor cur(&doc);
        cur.insertText("Hello ");
        QTextCharFormat bold; bold.setFontWeight(QFont::Bold);
        cur.insertText("world", bold);
        if (doc.toPlainText()!="Hello world") { d="text"; return false; }
        return doc.characterCount() >= 11 && doc.blockCount()==1;
    });
    r.check("text/list", [&r](QString &d) {
        QTextDocument doc; QTextCursor cur(&doc);
        QTextList *list = cur.insertList(QTextListFormat::ListDisc);
        cur.insertText("one"); cur.insertBlock(); cur.insertText("two");
        return list->count()==2;
    });
    r.check("text/table", [&r](QString &d) {
        QTextDocument doc; QTextCursor cur(&doc);
        QTextTable *t = cur.insertTable(2,3);
        return t->rows()==2 && t->columns()==3;
    });
    r.check("text/html-fragment", [&r](QString &d) {
        QTextDocument doc;
        doc.setHtml("<b>bold</b> and <i>italic</i>");
        QString plain = doc.toPlainText();
        return plain.contains("bold") && plain.contains("italic");
    });
    r.check("text/find", [&r](QString &d) {
        QTextDocument doc; doc.setPlainText("the quick brown fox");
        QTextCursor c = doc.find("brown");
        return !c.isNull() && c.selectedText()=="brown";
    });
}
