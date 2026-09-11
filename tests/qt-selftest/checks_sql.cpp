// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// SQLite: driver, queries, prepared statements, records, and the model classes
// (QSqlQueryModel / QSqlTableModel). Headless, in-memory database.
#include "../common/smokecheck.h"
#include "checks.h"

#include <QtSql/QSqlDatabase>
#include <QtSql/QSqlQuery>
#include <QtSql/QSqlError>
#include <QtSql/QSqlRecord>
#include <QtSql/QSqlField>
#include <QtSql/QSqlQueryModel>
#include <QtSql/QSqlTableModel>
#include <QtSql/QSqlRelationalTableModel>
#include <QtSql/QSqlDriver>
#include <QtSql/QSqlDriverPlugin>
#include <QtSql/QSqlIndex>
#include <QtSql/QSqlResult>
#include <QVariant>

namespace {

class SmokeSqlDriverCreator : public QSqlDriverCreatorBase
{
public:
    QSqlDriver *createObject() const override { return nullptr; }
};

class SmokeSqlDriverPlugin : public QSqlDriverPlugin
{
public:
    QSqlDriver *create(const QString &) override { return nullptr; }
#if !SMOKE_QT5
    QStringList keys() const override { return QStringList() << QStringLiteral("smoke"); }
#endif
};

class SmokeSqlResult : public QSqlResult
{
public:
    explicit SmokeSqlResult(const QSqlDriver *driver) : QSqlResult(driver) {}

    using QSqlResult::isActive;
    using QSqlResult::isSelect;
    using QSqlResult::setActive;
    using QSqlResult::setSelect;

    QVariant data(int) override { return QVariant(); }
    bool isNull(int) override { return true; }
    bool reset(const QString &) override { return true; }
    bool fetch(int) override { return false; }
    bool fetchFirst() override { return false; }
    bool fetchLast() override { return false; }
    int size() override { return 0; }
    int numRowsAffected() override { return 0; }
};

} // namespace

void checkSql(SmokeReporter &r)
{
    const bool haveSqlite = QSqlDatabase::isDriverAvailable("QSQLITE");

    r.check("sql/driver-available", [&](QString &d) {
        d = "drivers: " + QSqlDatabase::drivers().join(",");
        if (!haveSqlite) { r.skip(d, "QSQLITE not built"); return false; }
        return true;
    });
    if (!haveSqlite)
        return;

    // Each check keeps its QSqlQuery/model inside an inner scope so they are
    // destroyed before removeDatabase() - otherwise Qt warns "connection still
    // in use".
    r.check("sql/crud+prepared", [&r](QString &d) {
        bool ok=true; int rows=0, sumAge=0, cols=0; QString firstField; QString err;
        {
            QSqlDatabase db = QSqlDatabase::addDatabase("QSQLITE", "smoke_crud");
            db.setDatabaseName(":memory:");
            if (!db.open()) { d=db.lastError().text(); return false; }
            QSqlQuery q(db);
            ok &= q.exec("CREATE TABLE person (id INTEGER PRIMARY KEY, name TEXT, age INT)");
            q.prepare("INSERT INTO person (name, age) VALUES (?, ?)");
            for (auto pr : {qMakePair(QString("alice"),30), qMakePair(QString("bob"),25)}) {
                q.addBindValue(pr.first); q.addBindValue(pr.second); ok &= q.exec();
            }
            if (ok && q.exec("SELECT name, age FROM person ORDER BY age"))
                while (q.next()) { ++rows; sumAge += q.value(1).toInt(); }
            QSqlRecord rec = q.record(); cols = rec.count(); firstField = rec.fieldName(0);
            db.close();
        }
        QSqlDatabase::removeDatabase("smoke_crud");
        if (!ok) { d="query failed"; return false; }
        return rows==2 && sumAge==55 && cols==2 && firstField=="name";
    });

    r.check("sql/querymodel", [&r](QString &d) {
        int rc=0; QString first;
        {
            QSqlDatabase db = QSqlDatabase::addDatabase("QSQLITE", "smoke_qm");
            db.setDatabaseName(":memory:"); db.open();
            { QSqlQuery q(db);
              q.exec("CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)");
              q.exec("INSERT INTO t (v) VALUES ('a')");
              q.exec("INSERT INTO t (v) VALUES ('b')");
              q.exec("INSERT INTO t (v) VALUES ('c')"); }
            QSqlQueryModel model;
            model.setQuery("SELECT v FROM t ORDER BY id", db);
            rc = model.rowCount();
            first = model.data(model.index(0,0)).toString();
            db.close();
        }
        QSqlDatabase::removeDatabase("smoke_qm");
        if (rc!=3) { d=QString("rows=%1").arg(rc); return false; }
        return first=="a";
    });

    r.check("sql/tablemodel", [&r](QString &d) {
        bool ins=false, sub=false; int rc=0;
        {
            QSqlDatabase db = QSqlDatabase::addDatabase("QSQLITE", "smoke_tm");
            db.setDatabaseName(":memory:"); db.open();
            { QSqlQuery q(db); q.exec("CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT)"); }
            QSqlTableModel model(nullptr, db);
            model.setTable("items");
            model.setEditStrategy(QSqlTableModel::OnManualSubmit);
            QSqlRecord rec = model.record();
            rec.setValue("name", "widget");
            ins = model.insertRecord(-1, rec);
            sub = model.submitAll();
            model.select();
            rc = model.rowCount();
            db.close();
        }
        QSqlDatabase::removeDatabase("smoke_tm");
        if (!ins || !sub) { d="insert/submit"; return false; }
        return rc==1;
    });

    r.check("sql/relation-index-plugin-result", [&r](QString &d) {
        bool selected = false;
        int cols = 0;
        QString relationValue;
        bool resultState = false;
        {
            QSqlDatabase db = QSqlDatabase::addDatabase("QSQLITE", "smoke_rel");
            db.setDatabaseName(":memory:"); db.open();
            { QSqlQuery q(db);
              q.exec("CREATE TABLE city (id INTEGER PRIMARY KEY, name TEXT)");
              q.exec("CREATE TABLE person (id INTEGER PRIMARY KEY, name TEXT, city_id INT)");
              q.exec("INSERT INTO city (id, name) VALUES (1, 'Paris')");
              q.exec("INSERT INTO person (name, city_id) VALUES ('alice', 1)"); }

            QSqlIndex index(QStringLiteral("person"), QStringLiteral("idx_person_id"));
            index.append(QSqlField(QStringLiteral("id"), QVariant::Int), true);
            index.setDescending(0, true);

            QSqlRelation relation(QStringLiteral("city"), QStringLiteral("id"), QStringLiteral("name"));
            QSqlRelationalTableModel model(nullptr, db);
            model.setTable(QStringLiteral("person"));
            model.setRelation(2, relation);
            model.setJoinMode(QSqlRelationalTableModel::LeftJoin);
            selected = model.select();
            cols = model.columnCount();
            relationValue = model.relation(2).displayColumn();

            SmokeSqlDriverCreator creator;
            SmokeSqlDriverPlugin plugin;
            SmokeSqlResult result(db.driver());
            result.setActive(true);
            result.setSelect(true);
            resultState = index.isDescending(0)
                && creator.createObject() == nullptr
                && plugin.create(QStringLiteral("smoke")) == nullptr
                && result.isActive()
                && result.isSelect();
            db.close();
        }
        QSqlDatabase::removeDatabase("smoke_rel");
        if (!selected) { d="relational select"; return false; }
        return cols >= 3
            && relationValue == QStringLiteral("name")
            && resultState;
    });
}
