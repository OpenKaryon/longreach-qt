// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// QtCore, QtGui and QtNetwork API that exists only in Qt 4.
//
// Three kinds of thing end up here, and they got dropped for different reasons
// worth telling apart:
//
//   * classes Qt 5 replaced outright - QHttp and QFtp became
//     QNetworkAccessManager, QWorkspace became QMdiArea;
//   * the versioned style-option structs. Qt 4 could not change a struct
//     without breaking binary compatibility, so it added QStyleOptionTabV2,
//     then V3, then V4. Qt 5 was allowed to break that and collapsed them all
//     back into the base;
//   * interfaces an application *implements* rather than calls - the plugin
//     factory interfaces, the input context, the file engine. Those are covered
//     by subclassing, which is the only way to reference them honestly.

#include "../common/smokecheck.h"
#include "gallery.h"

#include <QApplication>
#include <QBuffer>
#include <QDir>
#include <QFileInfo>
#include <QImage>
#include <QPalette>
#include <QStringList>
#include <QVariant>
#include <QWidget>

#include <QAbstractFileEngine>
#include <QFSFileEngine>
#include <QFtp>
#include <QHttp>
#include <QInputContext>
#include <QInputContextFactory>
#include <QProxyModel>
#include <QStringListModel>
#include <QStyleFactory>
#include <QStyleOption>
#include <QTextStream>
#include <QUrlInfo>
#include <QWorkspace>

#include <QAccessible>
#include <QAccessible2Interface>
#include <QAccessibleBridge>
#include <QAccessibleObject>
#include <QAccessiblePlugin>
#include <QAccessibleWidget>
#include <QContiguousCache>
#include <QLinkedList>
#include <QStringBuilder>
#include <QGenericPlugin>
#include <QGenericPluginFactory>
#include <QIconEnginePlugin>
#include <QInputContextPlugin>
#include <QPictureFormatPlugin>
#include <QClipboard>
#include <QEvent>
#include <QIconEngine>
#include <QImageIOHandler>
#include <QLayout>
#include <QAbstractPageSetupDialog>
#include <QMenuItem>
#include <QPrintDialog>
#include <QSqlDriverPlugin>
#include <QStylePlugin>
#include <QTextCodecPlugin>

#ifdef SMOKE_HAVE_UITOOLS
#include <QComboBox>
#include <QLineEdit>
#include <QUiLoader>
#endif

#include <QCDEStyle>
#include <QCleanlooksStyle>
#include <QMotifStyle>
#include <QPlastiqueStyle>
#include <QWindowsStyle>

namespace {

// QAbstractFileEngine is an interface Qt calls into; an application provides
// one to teach QFile about a new kind of path. Subclassing is how it is
// referenced, and the handler is how one is installed.
class SmokeFileEngine : public QAbstractFileEngine
{
public:
    bool open(QIODevice::OpenMode) { return false; }
    qint64 size() const { return 0; }
    QString fileName(FileName = DefaultName) const { return QLatin1String("smoke:"); }
};

class SmokeFileEngineHandler : public QAbstractFileEngineHandler
{
public:
    QAbstractFileEngine *create(const QString &path) const
    {
        return path.startsWith(QLatin1String("smoke:")) ? new SmokeFileEngine : 0;
    }
};

class SmokeInputContext : public QInputContext
{
public:
    QString identifierName() { return QLatin1String("smoke"); }
    QString language() { return QLatin1String("en"); }
    void reset() {}
    bool isComposing() const { return false; }
};

// QObjectUserData is how Qt 4 let an application hang its own pointer off any
// QObject, before dynamic properties made it unnecessary.
class SmokeUserData : public QObjectUserData
{
public:
    explicit SmokeUserData(int v) : value(v) {}
    int value;
};

} // namespace

void addQtBaseQt4Checks(SmokeReporter &r)
{
    // ---- networking Qt 5 replaced -----------------------------------------
    r.check("qt4/http-and-ftp", [](QString &d) {
        QHttp http;
        QHttpRequestHeader request(QLatin1String("GET"), QLatin1String("/index.html"));
        request.setValue(QLatin1String("Host"), QLatin1String("example.org"));
        QHttpResponseHeader response(404, QLatin1String("Not Found"));
        QHttpHeader &base = request;
        QFtp ftp;
        d = QString::fromLatin1("%1 %2, header lines %3")
                .arg(request.method(), request.path()).arg(base.keys().count());
        return request.method() == QLatin1String("GET")
            && request.path() == QLatin1String("/index.html")
            && base.value(QLatin1String("Host")) == QLatin1String("example.org")
            && response.statusCode() == 404
            && response.reasonPhrase() == QLatin1String("Not Found")
            && http.state() == QHttp::Unconnected
            && ftp.state() == QFtp::Unconnected;
    });

    r.check("qt4/urlinfo", [](QString &d) {
        QUrlInfo info;
        info.setName(QLatin1String("file.txt"));
        info.setSize(4887);
        info.setFile(true);
        d = QString::fromLatin1("%1, %2 bytes").arg(info.name()).arg(info.size());
        return info.isValid() && info.name() == QLatin1String("file.txt")
            && info.size() == 4887 && info.isFile();
    });

    // ---- the versioned style options ---------------------------------------
    r.check("qt4/style-option-versions", [](QString &d) {
        // Every one of these exists because Qt 4 could not add a member to the
        // base struct without breaking binary compatibility. Reading the version
        // field back is the point: it is what a style used to dispatch on.
        QStyleOptionFrameV2 frameV2;
        QStyleOptionFrameV3 frameV3;
        QStyleOptionProgressBarV2 progressV2;
        QStyleOptionTabV2 tabV2;
        QStyleOptionTabV3 tabV3;
        QStyleOptionTabBarBaseV2 tabBarV2;
        QStyleOptionTabWidgetFrameV2 tabFrameV2;
        QStyleOptionToolBoxV2 toolBoxV2;
        QStyleOptionViewItemV2 itemV2;
        QStyleOptionViewItemV3 itemV3;
        QStyleOptionViewItemV4 itemV4;
        QStyleOptionDockWidgetV2 dockV2;
        d = QString::fromLatin1("frame v%1/v%2, tab v%3/v%4, item v%5/v%6/v%7")
                .arg(frameV2.version).arg(frameV3.version)
                .arg(tabV2.version).arg(tabV3.version)
                .arg(itemV2.version).arg(itemV3.version).arg(itemV4.version);
        return frameV2.version == 2 && frameV3.version == 3
            && progressV2.version == 2 && tabV2.version == 2 && tabV3.version == 3
            && tabBarV2.version == 2 && tabFrameV2.version == 2
            && toolBoxV2.version == 2 && itemV2.version == 2 && itemV3.version == 3
            && itemV4.version == 4 && dockV2.version == 2;
    });

    r.check("qt4/style-options-for-qt3", [](QString &d) {
        // The style options that exist only to draw Qt3Support widgets.
        QStyleOptionQ3DockWindow dockWindow;
        QStyleOptionQ3ListView listView;
        QStyleOptionQ3ListViewItem listViewItem;
        listViewItem.height = 16;
        listView.items.append(listViewItem);
        d = QString::fromLatin1("dock v%1, listview v%2 with %3 item")
                .arg(dockWindow.version).arg(listView.version).arg(listView.items.count());
        return dockWindow.version == 1 && listView.version == 1
            && listView.items.count() == 1 && listView.items.at(0).height == 16;
    });

    // ---- the Motif-era styles ---------------------------------------------
    r.check("qt4/legacy-styles", [](QString &d) {
        // Qt 5 kept only Fusion and the native styles; all of these went. They
        // are constructed rather than looked up by name, because
        // QStyleFactory::keys() answers with what the build enabled, and the
        // point here is that the classes are present.
        QMotifStyle motif;
        QCDEStyle cde;
        QPlastiqueStyle plastique;
        QCleanlooksStyle cleanlooks;
        QWindowsStyle windows;
        const QStringList keys = QStyleFactory::keys();
        d = QString::fromLatin1("%1, and the factory offers %2")
                .arg(motif.metaObject()->className()).arg(keys.count());
        return motif.metaObject() && cde.metaObject() && plastique.metaObject()
            && cleanlooks.metaObject() && windows.metaObject() && !keys.isEmpty();
    });

    // ---- QtGui classes Qt 5 replaced --------------------------------------
    r.check("qt4/workspace-and-proxymodel", [](QString &d) {
        QWidget top;
        QWorkspace workspace(&top);
        QWidget *child = workspace.addWindow(new QWidget);
        // QProxyModel installs an empty model of its own rather than starting
        // null, so what is worth asserting is that it takes one and reports it.
        QProxyModel proxy;
        QStringListModel source;
        proxy.setModel(&source);
        d = QString::fromLatin1("workspace has %1 window(s), proxy wraps %2")
                .arg(workspace.windowList().count())
                .arg(proxy.model() ? proxy.model()->metaObject()->className() : "nothing");
        return child != 0 && workspace.windowList().count() == 1
            && proxy.model() == &source;
    });

    r.check("qt4/colorgroup", [](QString &d) {
        // QColorGroup was Qt 3's palette slice; Qt 4 kept it as a typedef-like
        // class and Qt 5 removed it entirely in favour of QPalette's groups.
        QPalette palette;
        QColorGroup group(palette);
        d = QString::fromLatin1("window colour %1").arg(group.background().name());
        return group.background().isValid();
    });

    // ---- interfaces an application implements ------------------------------
    r.check("qt4/file-engine", [](QString &d) {
        SmokeFileEngineHandler handler;
        QFileInfo info(QLatin1String("smoke:/anything"));
        // QFSFileEngine is the built-in one; naming it here is what an
        // application does when it wants the real filesystem behind its own.
        QFSFileEngine real(QDir::tempPath());
        d = QString::fromLatin1("temp engine reports %1")
                .arg(real.fileName(QAbstractFileEngine::DefaultName));
        return !real.fileName(QAbstractFileEngine::DefaultName).isEmpty()
            && sizeof(QAbstractFileEngineIterator) > 0;
    });

    r.check("qt4/input-context", [](QString &d) {
        SmokeInputContext context;
        const QStringList keys = QInputContextFactory::keys();
        d = QString::fromLatin1("'%1', factory knows %2")
                .arg(context.identifierName()).arg(keys.count());
        return context.identifierName() == QLatin1String("smoke")
            && !context.isComposing();
    });

    r.check("qt4/object-user-data", [](QString &d) {
        QObject owner;
        const uint id = QObject::registerUserData();
        owner.setUserData(id, new SmokeUserData(4887));
        SmokeUserData *back = static_cast<SmokeUserData *>(owner.userData(id));
        d = QString::fromLatin1("read back %1").arg(back ? back->value : -1);
        return back && back->value == 4887;
    });

    // ---- small core types Qt 5 dropped or hid ------------------------------
    r.check("qt4/core-odds-and-ends", [](QString &d) {
        // QFlag and QIncompatibleFlag are what QFlags<> was built out of before
        // Qt 5 made the whole thing constexpr.
        QFlag flag(3);
        QIncompatibleFlag incompatible(4);
        // QCharRef and QByteRef are the proxy types operator[] returns on a
        // mutable QString and QByteArray.
        QString text = QLatin1String("abc");
        QCharRef ch = text[0];
        ch = QLatin1Char('A');
        QByteArray bytes("xyz");
        QByteRef byte = bytes[0];
        byte = 'X';
        d = QString::fromLatin1("'%1' / '%2' / %3")
                .arg(text, QString::fromLatin1(bytes)).arg(int(flag));
        return text == QLatin1String("Abc") && bytes == QByteArray("Xyz")
            && int(flag) == 3 && int(incompatible) == 4;
    });

    r.check("qt4/text-stream-aliases", [](QString &d) {
        // QTextIStream and QTextOStream are Qt 3 spellings kept for the
        // migration; Qt 5 has only QTextStream.
        QString out;
        QTextOStream os(&out);
        os << "written " << 42;
        QString in = QLatin1String("77 rest");
        QTextIStream is(&in);
        int value = 0;
        is >> value;
        d = QString::fromLatin1("'%1', read %2").arg(out).arg(value);
        return out == QLatin1String("written 42") && value == 77;
    });

    // ---- the plugin factory interfaces -------------------------------------
    r.check("qt4/plugin-interfaces", [](QString &d) {
        // Qt 4 plugins: a Q_DECLARE_INTERFACE factory and a QObject base, replaced in
        // Qt 5 by Q_PLUGIN_METADATA. Pure interfaces, so the types are named.
        // QGenericPluginFactory's implementation is not exported in this static kit,
        // so sizeof is what is reachable.
        d = QLatin1String("style, icon engine, image format, codec, sql, generic");
        return sizeof(QGenericPluginFactory) > 0
            && sizeof(QStyleFactoryInterface) > 0
            && sizeof(QIconEngineFactoryInterface) > 0
            && sizeof(QIconEngineFactoryInterfaceV2) > 0
            && sizeof(QIconEngineV2) > 0
            && sizeof(QIconEnginePluginV2) > 0
            && sizeof(QImageIOHandlerFactoryInterface) > 0
            && sizeof(QTextCodecFactoryInterface) > 0
            && sizeof(QTextCodecPlugin) > 0
            && sizeof(QSqlDriverFactoryInterface) > 0
            && sizeof(QInputContextFactoryInterface) > 0
            && sizeof(QInputContextPlugin) > 0
            && sizeof(QGenericPluginFactoryInterface) > 0
            && sizeof(QPictureFormatInterface) > 0;
    });

    // ---- the accessibility interfaces Qt 4 had ------------------------------
    r.check("qt4/accessibility-interfaces", [&](QString &d) {
#ifdef QT_NO_ACCESSIBILITY
        r.skip(d, QStringLiteral("Accessibility disabled in this Qt build"));
        return false;
#else
        // Qt 4's "Ex" and "2" accessibility interfaces, added for binary
        // compatibility. QAccessibleWidget's destructor is protected, so the interface
        // is queried, not constructed.
        QWidget widget;
        QAccessibleInterface *accessible = QAccessible::queryAccessibleInterface(&widget);
        const int children = accessible ? accessible->childCount() : -1;
        if (accessible)
            delete accessible;
        d = QString::fromLatin1("interface %1, %2 children")
                .arg(accessible ? "found" : "none").arg(children);
        return sizeof(QAccessibleWidget) > 0
            && sizeof(QAccessibleInterfaceEx) > 0
            && sizeof(QAccessibleObjectEx) > 0
            && sizeof(QAccessibleWidgetEx) > 0
            && sizeof(QAccessible2Interface) > 0
            && sizeof(QAccessibleSimpleEditableTextInterface) > 0
            && sizeof(QAccessibleTable2Interface) > 0
            && sizeof(QAccessibleTable2CellInterface) > 0
            && sizeof(QAccessibleFactoryInterface) > 0
            && sizeof(QAccessibleBridgeFactoryInterface) > 0;
#endif
    });

    // ---- events and small types Qt 5 dropped -------------------------------
    r.check("qt4/legacy-events", [](QString &d) {
        // QCustomEvent was how Qt 3 posted an application event before
        // QEvent::User + a subclass became the idiom; the other two are
        // internal event types that were nonetheless public.
        QCustomEvent custom(QEvent::Type(QEvent::User + 1));
        d = QString::fromLatin1("custom event type %1").arg(int(custom.type()));
        return custom.type() == QEvent::User + 1
            && sizeof(QClipboardEvent) > 0
            && sizeof(QDragResponseEvent) > 0
            && sizeof(QMenubarUpdatedEvent) > 0;
    });

    r.check("qt4/implicit-sharing-internals", [](QString &d) {
        // QSharedData is the base of every implicitly shared Qt class, and the
        // *Data structs are the private container headers the inline template
        // code operates on. They are public headers because that code is inline.
        class Shared : public QSharedData { public: int value; };
        QSharedDataPointer<Shared> data(new Shared);
        data->value = 4887;
        QSharedDataPointer<Shared> copy = data;
        d = QString::fromLatin1("shared value %1").arg(copy->value);
        return copy->value == 4887
            && sizeof(QHashData) > 0 && sizeof(QListData) > 0
            && sizeof(QMapData) > 0 && sizeof(QVectorData) > 0
            && sizeof(QLinkedListData) > 0 && sizeof(QContiguousCacheData) > 0
            && sizeof(QAbstractConcatenable) > 0;
    });

    r.check("qt4/atomics-and-locale", [](QString &d) {
        // QBasicAtomicInt is the POD atomic Qt 4 used where a constructor could
        // not run; Qt 5 replaced it with QAtomicInteger and std::atomic.
        QBasicAtomicInt counter = Q_BASIC_ATOMIC_INITIALIZER(0);
        counter.ref();
        counter.ref();
        // QSystemLocale is the hook an application overrides to answer locale
        // queries itself.
        QSystemLocale systemLocale;
        d = QString::fromLatin1("counter %1").arg(int(counter));
        return int(counter) == 2 && sizeof(QSystemLocale) > 0;
    });

    r.check("qt4/menu-item-and-layout-iterator", [](QString &d) {
        // QMenuItem and QLayoutIterator are Qt 3 shapes Qt 4 kept as aliases
        // and Qt 5 removed: menus hold QActions and layouts are walked with
        // itemAt() now.
        QWidget top;
        QHBoxLayout layout(&top);
        layout.addWidget(new QWidget);
        d = QString::fromLatin1("layout holds %1").arg(layout.count());
        return layout.count() == 1
            && sizeof(QMenuItem) > 0 && sizeof(QLayoutIterator) > 0
            && sizeof(QMimeSource) > 0;
    });

    r.check("qt4/print-dialog-helpers", [&](QString &d) {
#if defined(QT_NO_PRINTER) || defined(QT_NO_PRINTDIALOG)
        r.skip(d, QStringLiteral("Printing dialogs disabled in this Qt build"));
        return false;
#else
        // QUnixPrintWidget exists only where the print dialog is Qt's own, not on
        // Windows or Mac; the guard mirrors qprintdialog.h.
#if !defined(Q_WS_WIN) && !defined(Q_WS_MAC)
        d = QLatin1String("page setup base and the unix print widget");
        return sizeof(QAbstractPageSetupDialog) > 0
            && sizeof(QUnixPrintWidget) > 0;
#else
        d = QLatin1String("page setup base; no unix print widget on this platform");
        return sizeof(QAbstractPageSetupDialog) > 0;
#endif
#endif
    });

    r.check("qt4/image-text-key", [](QString &d) {
        // QImageTextKeyLang carried the key/language pair for the PNG text
        // chunks that QImage::setText() used to write.
        QImageTextKeyLang key("Author", "en");
        d = QString::fromLatin1("%1/%2")
                .arg(QString::fromLatin1(key.key), QString::fromLatin1(key.lang));
        return key.key == QByteArray("Author") && key.lang == QByteArray("en");
    });

#ifdef SMOKE_HAVE_UITOOLS
    r.check("qt4/uiloader", [](QString &d) {
        // QUiLoader builds a form from Designer's .ui XML at run time.
        static const char form[] =
            "<?xml version='1.0' encoding='UTF-8'?><ui version='4.0'><class>Form</class>"
            "<widget class='QWidget' name='form'>"
            "<property name='windowTitle'><string>UI Tools</string></property>"
            "<layout class='QVBoxLayout' name='layout'>"
            "<item><widget class='QLineEdit' name='nameEdit'/></item>"
            "<item><widget class='QComboBox' name='choiceBox'>"
            "<item><property name='text'><string>First</string></property></item>"
            "<item><property name='text'><string>Second</string></property></item>"
            "</widget></item></layout></widget><resources/><connections/></ui>";
        QBuffer source;
        source.setData(form);
        if (!source.open(QIODevice::ReadOnly))
            return false;
        QUiLoader loader;
        QWidget *w = loader.load(&source);
        if (!w)
            return false;
        QLineEdit *edit = w->findChild<QLineEdit *>(QLatin1String("nameEdit"));
        QComboBox *combo = w->findChild<QComboBox *>(QLatin1String("choiceBox"));
        const bool ok = edit && combo && combo->count() == 2
            && combo->itemText(1) == QLatin1String("Second")
            && w->windowTitle() == QLatin1String("UI Tools");
        d = QString::fromLatin1("%1 widgets, title '%2'")
                .arg(w->findChildren<QWidget *>().count()).arg(w->windowTitle());
        delete w;
        return ok;
    });
#endif
}
