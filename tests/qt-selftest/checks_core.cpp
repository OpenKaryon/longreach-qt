// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Core value types, containers, QVariant, meta-object system, serialization
// primitives. All headless.
#include "../common/smokecheck.h"
#include "checks.h"

#include <QString>
#include <QStringList>
#if SMOKE_QT5
#include <QStringView>
#endif
#include <QByteArray>
#if SMOKE_QT5
#include <QByteArrayList>
#endif
#include <QBitArray>
#include <QBitRef>
#include <QChar>
#include <QLatin1String>
#include <QVector>
#include <QList>
#include <QMap>
#include <QHash>
#include <QSet>
#include <QPair>
#include <QQueue>
#include <QStack>
#if QT_VERSION_MAJOR < 6
#include <QLinkedList>
#endif
#include <QVariant>
#if SMOKE_QT5
#include <QSequentialIterable>
#include <QAssociativeIterable>
#endif
#include <QVariantMap>
#include <QVariantList>
#include <QDataStream>
#include <QBuffer>
#if SMOKE_QT5
#include <QCborArray>
#include <QCborValueRef>
#include <QJsonArray>
#include <QJsonValueRef>
#include <QRegularExpression>
#endif
#if QT_VERSION_MAJOR < 6
#include <QRegExp>
#endif
#include <QCryptographicHash>
#if SMOKE_QT5
#include <QMessageAuthenticationCode>
#endif
#include <QUuid>
#if SMOKE_QT5
#include <QVersionNumber>
#include <QCommandLineParser>
#include <QCommandLineOption>
#endif
#include <QCoreApplication>
#include <QMetaType>
#include <QMetaObject>
#include <QMetaEnum>
#include <QMetaClassInfo>
#include <QMetaProperty>
#include <QMetaMethod>
#include <QGenericArgument>
#include <QGenericReturnArgument>
#include <QDebug>
#if SMOKE_QT5
#include <QDebugStateSaver>
#include <QMessageLogger>
#endif
#include <QObject>
#include <QTextBoundaryFinder>

// A tiny QObject to exercise the meta-object system.
class MetaProbe : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("smoke", "yes")
    Q_PROPERTY(int answer READ answer WRITE setAnswer NOTIFY answerChanged)
public:
    enum Mood { Happy, Sad, Meh };
#if SMOKE_QT5
    Q_ENUM(Mood)
#else
    Q_ENUMS(Mood)
#endif
    int answer() const { return m_a; }
    void setAnswer(int a) { if (m_a != a) { m_a = a; emit answerChanged(a); } }
    Q_INVOKABLE int twice(int x) const { return 2 * x; }
signals:
    void answerChanged(int);
private:
    int m_a = 0;
};

void checkCore(SmokeReporter &r)
{
#if SMOKE_QT5
    r.check("core/string+unicode", [&r](QString &d) {
        QString s = QStringLiteral("Сәлем, әлем ") + QString::fromUtf8("世界");
        if (QString::fromUtf8(s.toUtf8()) != s) { d = "utf8 round-trip"; return false; }
        QStringView v(s);
        return s.toUpper().contains(QStringLiteral("СӘЛЕМ")) && v.size() == s.size();
    });
#else
    r.check("core/string+unicode", [&r](QString &d) {
        QString s = QString::fromUtf8("Qt 4 unicode: \xd0\xbc\xd0\xb8\xd1\x80");
        return QString::fromUtf8(s.toUtf8()) == s && s.contains(QString::fromUtf8("\xd0\xbc\xd0\xb8\xd1\x80"));
    });
#endif
    r.check("core/latin1+char", [&r](QString &d) {
        QLatin1String l("abc");
        QChar c = QLatin1Char('Z');
        return QString(l).size() == 3 && c.toLower() == QChar('z') && c.isLetter();
    });
    r.check("core/stringlist", [&r](QString &d) {
        QStringList sl = QString("a,b,c,d").split(',');
        if (sl.size() != 4) { d = "split"; return false; }
        return sl.join(QStringLiteral("-")) == "a-b-c-d" && sl.filter("b").size() == 1;
    });
    r.check("core/bytearray+bitarray", [&r](QString &d) {
        QByteArray b = QByteArray::fromHex("48656c6c6f");
        if (b != "Hello") { d = "fromHex"; return false; }
        QBitArray bits(8); bits.setBit(1); bits.setBit(3);
        QBitRef bitRef = bits[3];
        return bits.count(true) == 2 && bool(bitRef) && b.toBase64() == "SGVsbG8=";
    });
    r.check("core/containers", [&r](QString &d) {
        QVector<int> v{5,3,1,4,2}; std::sort(v.begin(), v.end());
        QMap<QString,int> m; m["x"]=1; m["y"]=2;
        QHash<int,QString> h; h[1]="one";
        QSet<int> s; s << 1 << 2 << 2 << 3;
        QList<int> lst{1,2,3};
        if (v.first()!=1 || v.last()!=5) { d="vector sort"; return false; }
        return m.value("y")==2 && h.value(1)=="one" && s.size()==3 && lst.contains(2);
    });
    r.check("core/queue+stack", [&r](QString &d) {
        QQueue<int> q; q.enqueue(1); q.enqueue(2);
        QStack<int> st; st.push(9); st.push(8);
        return q.dequeue()==1 && st.pop()==8;
    });
    r.check("core/pair", [&r](QString &) {
        auto p = qMakePair(QString("k"), 42);
        return p.first=="k" && p.second==42;
    });
    r.check("core/variant", [&r](QString &d) {
        QVariant vi(42), vs("text"), vl(QVariant::fromValue(QStringList{"a","b"}));
        if (vi.toInt()!=42 || vs.toString()!="text") { d="convert"; return false; }
        QVariantMap vm; vm["n"]=1; vm["s"]="z";
#if SMOKE_QT5
        QSequentialIterable sequential = vl.value<QSequentialIterable>();
        QVariant vmVariant = QVariant::fromValue(vm);
        QAssociativeIterable associative = vmVariant.value<QAssociativeIterable>();
        return vl.toStringList().size()==2 && vm["n"].toInt()==1
            && sequential.size()==2 && associative.size()==2
            && associative.value(QStringLiteral("n")).toInt()==1;
#else
        return vl.toStringList().size()==2 && vm["n"].toInt()==1;
#endif
    });
#if SMOKE_QT5
    r.check("core/json-cbor-value-refs", [&](QString &d) {
        QJsonArray jsonArray;
        jsonArray.append(1);
        QJsonValueRef jsonRef = jsonArray[0];
        jsonRef = 7;

        QCborArray cborArray;
        cborArray.append(1);
        QCborValueRef cborRef = cborArray[0];
        cborRef = 9;

        return jsonArray.at(0).toInt() == 7
            && cborArray.at(0).toInteger() == 9;
    });
#endif
    r.check("core/datastream", [&r](QString &d) {
        QByteArray buf;
        { QDataStream out(&buf, QIODevice::WriteOnly); out << QString("hi") << 42 << QList<int>{1,2,3}; }
        QString s; int n; QList<int> l;
        { QDataStream in(&buf, QIODevice::ReadOnly); in >> s >> n >> l; }
        if (s!="hi" || n!=42) { d="scalars"; return false; }
        return l.size()==3 && l.at(2)==3;
    });
    r.check("core/regularexpression", [&r](QString &d) {
#if SMOKE_QT5
        QRegularExpression re("(?<num>\\d+)-(\\d+)");
        auto m = re.match("id 42-7 x");
        if (!m.hasMatch()) { d="no match"; return false; }
        auto it = re.globalMatch("1-2 3-4 5-6"); int c=0; while (it.hasNext()){ it.next(); ++c; }
        return m.captured("num")=="42" && c==3;
#else
        r.skip(d, QStringLiteral("QRegularExpression arrived in Qt 5; QRegExp is checked separately"));
        return false;
#endif
    });
    r.check("core/regexp-legacy", [&r](QString &d) {
#if QT_VERSION_MAJOR < 6
        QRegExp rx("(\\w+)@(\\w+)");
        return rx.indexIn("a@b") == 0 && rx.cap(2) == "b";
#else
        r.skip(d, QStringLiteral("QRegExp moved to Qt5Compat, which this app does not link"));
        return false;
#endif
    });
    r.check("core/crypto+hmac", [&r](QString &d) {
#if SMOKE_QT5
        QByteArray h = QCryptographicHash::hash("abc", QCryptographicHash::Sha256).toHex();
        QByteArray mac = QMessageAuthenticationCode::hash("msg","key",QCryptographicHash::Sha256);
        return h=="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" && mac.size()==32;
#else
        QByteArray h = QCryptographicHash::hash("abc", QCryptographicHash::Sha1).toHex();
        return h=="a9993e364706816aba3e25717850c26c9cd0d89d";
#endif
    });
    r.check("core/uuid", [&r](QString &) {
        QUuid u = QUuid::createUuid();
        return !u.isNull() && QUuid(u.toString())==u;
    });
    r.check("core/versionnumber", [&r](QString &d) {
#if SMOKE_QT5
        auto v = QVersionNumber::fromString("5.15.19");
        return v.majorVersion()==5 && v.minorVersion()==15 && v.microVersion()==19;
#else
        r.skip(d, QStringLiteral("QVersionNumber arrived in Qt 5"));
        return false;
#endif
    });
    r.check("core/commandlineparser", [&r](QString &d) {
#if SMOKE_QT5
        QCommandLineParser p;
        p.addOption(QCommandLineOption("count", "c", "n"));
        QStringList args{"app","--count","7"};
        if (!p.parse(args)) { d="parse"; return false; }
        return p.value("count").toInt()==7;
#else
        r.skip(d, QStringLiteral("QCommandLineParser arrived in Qt 5"));
        return false;
#endif
    });
    r.check("core/textboundaryfinder", [&r](QString &d) {
#if SMOKE_QT5
        QTextBoundaryFinder bf(QTextBoundaryFinder::Word, QStringLiteral("one two three"));
        int words=0; bf.toStart();
        // check position 0 too, then advance (a word start sets StartOfItem)
        do { if (bf.boundaryReasons() & QTextBoundaryFinder::StartOfItem) ++words; }
        while (bf.toNextBoundary()!=-1);
        if (words!=3) { d=QString("words=%1").arg(words); return false; }
        return true;
#else
        QTextBoundaryFinder bf(QTextBoundaryFinder::Word, QStringLiteral("one two three"));
        int boundaries=0; bf.toStart();
        while (bf.toNextBoundary()!=-1) ++boundaries;
        return boundaries >= 5;
#endif
    });
    r.check("core/metaobject+enum+invoke", [&r](QString &d) {
        MetaProbe p;
        const QMetaObject *mo = p.metaObject();
        int pi = mo->indexOfProperty("answer");
        if (pi < 0) { d="no property"; return false; }
        QMetaProperty mp = mo->property(pi);
        mp.write(&p, 21);
        QMetaEnum me = mo->enumerator(mo->indexOfEnumerator("Mood"));
        QMetaClassInfo classInfo = mo->classInfo(mo->indexOfClassInfo("smoke"));
        int ret = 0;
        int value = 21;
#if SMOKE_QT5
        QGenericReturnArgument returnArg("int", &ret);
        QGenericArgument arg("int", &value);
        QMetaObject::invokeMethod(&p, "twice", returnArg, arg);
        return p.answer()==21 && me.keyCount()==3 && QString(me.valueToKey(MetaProbe::Sad))=="Sad"
            && QString(classInfo.value())=="yes" && returnArg.name()!=nullptr && arg.name()!=nullptr
            && ret==42;
#else
        const bool invoked = QMetaObject::invokeMethod(&p, "twice",
            Q_RETURN_ARG(int, ret), Q_ARG(int, value));
        const bool ok = p.answer()==21
            && QString(classInfo.value())=="yes" && invoked && ret==42;
        if (!ok)
            d = QStringLiteral("answer=%1 info=%2 invoked=%3 ret=%4")
                .arg(p.answer())
                .arg(QString::fromLatin1(classInfo.value()))
                .arg(invoked).arg(ret);
        return ok;
#endif
    });
    r.check("core/debug-message-helpers", [&](QString &d) {
#if SMOKE_QT5
        QString text;
        QDebug debug(&text);
        QDebugStateSaver saver(debug);
        debug.nospace() << "value=" << 5;
        QMessageLogger logger(__FILE__, __LINE__, Q_FUNC_INFO);
        Q_UNUSED(logger);
        return text.contains(QStringLiteral("value=5"));
#else
        r.skip(d, QStringLiteral("QDebugStateSaver and QMessageLogger arrived in Qt 5"));
        return false;
#endif
    });
    r.check("core/metatype", [&r](QString &d) {
        int id = qMetaTypeId<QString>();
        return QMetaType::isRegistered(id) && QString(QMetaType::typeName(id))=="QString";
    });
    r.check("core/property-signal", [&r](QString &d) {
#if SMOKE_QT5
        MetaProbe p; int seen=-1;
        QObject::connect(&p, &MetaProbe::answerChanged, &p, [&](int v){ seen=v; });
        p.setAnswer(99);
        return seen==99;
#else
        r.skip(d, QStringLiteral("Qt 4 has no functor QObject::connect overload"));
        return false;
#endif
    });
}

#include "checks_core.moc"
