// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Qt3Support - the module that makes 4.8.7 a migration target for Qt 3 code
// rather than merely the oldest Qt in this kit, and the reason `-qt3support` is
// passed on every Qt 4 target and never trimmed for image size.
//
// Grouped by area rather than one check per class. A hundred and thirty-seven
// classes as a hundred and thirty-seven checks would be a wall of near-identical
// four-line functions, and would say less: what matters about a compatibility
// module is that the *area* still works - that a Q3ListView takes items, that a
// Q3Canvas holds shapes - not that each constructor returns non-null.
//
// Nothing here is shown. widgets-gallery already owns the QApplication these
// checks need, so the compatibility widgets are built, poked and destroyed
// inside its --selftest path without opening another application.

#include "../common/smokecheck.h"
#include "gallery.h"

#include <QApplication>
#include <QPixmap>
#include <QStringList>
#include <QWidget>

// containers and tools
#include <Q3CString>
#include <Q3StrList>
#include <Q3ValueList>
#include <Q3PtrList>
#include <Q3PtrCollection>
#include <Q3PointArray>
#include <Q3Signal>
#include <Q3Semaphore>
#include <Q3TextStream>

// widgets
#include <Q3Frame>
#include <Q3HBox>
#include <Q3VBox>
#include <Q3Grid>
#include <Q3GroupBox>
#include <Q3HGroupBox>
#include <Q3VGroupBox>
#include <Q3ButtonGroup>
#include <Q3HButtonGroup>
#include <Q3VButtonGroup>
#include <Q3ComboBox>
#include <Q3MultiLineEdit>
#include <Q3ProgressBar>
#include <Q3ScrollView>
#include <Q3GridView>
#include <Q3WidgetStack>
#include <Q3Header>

// item views
#include <Q3ListBox>
#include <Q3ListView>
#include <Q3IconView>
#include <Q3Table>

// text
#include <Q3TextEdit>
#include <Q3TextView>
#include <Q3TextBrowser>
#include <Q3SimpleRichText>
#include <Q3StyleSheet>
#include <Q3SyntaxHighlighter>
#include <Q3MimeSourceFactory>

// windows, actions and dialogs
#include <Q3MainWindow>
#include <Q3ToolBar>
#include <Q3DockWindow>
#include <Q3DockArea>
#include <Q3PopupMenu>
#include <Q3Accel>
#include <Q3Action>
#include <Q3ActionGroup>
#include <Q3TabDialog>
#include <Q3Wizard>
#include <Q3FileDialog>
#include <Q3ProgressDialog>
#include <Q3WhatsThis>
#include <Q3DateTimeEdit>

// canvas
#include <Q3Canvas>
#include <Q3CanvasItem>

// drag and drop
#include <Q3DragObject>
#include <Q3IconDrag>
#include <Q3DropSite>

// network
#include <Q3Socket>
#include <Q3SocketDevice>
#include <Q3ServerSocket>
#include <Q3Dns>
#include <Q3Ftp>
#include <Q3Http>
#include <Q3NetworkProtocol>
#include <Q3LocalFs>
#include <Q3Url>
#include <Q3UrlOperator>

// sql
#include <Q3SqlCursor>
#include <Q3SqlForm>
#include <Q3SqlPropertyMap>
#include <Q3SqlRecordInfo>
#include <Q3SqlSelectCursor>
#include <Q3DataBrowser>
#include <Q3DataTable>
#include <Q3DataView>
#include <Q3EditorFactory>
#include <Q3SqlEditorFactory>

// paint
#include <Q3Painter>
#include <Q3Picture>
#include <Q3PaintDeviceMetrics>
#include <Q3PolygonScanner>
#include <Q3Process>

// The generic container bases. Qt 3's containers were a void* implementation
// with typed wrappers on top - Q3PtrList is Q3GList, Q3Dict is Q3GDict - and
// the bases are public headers because the templates inline against them.
#include <Q3GArray>
#include <Q3GCache>
#include <Q3GDict>
#include <Q3GList>
#include <Q3GVector>
#include <Q3StrIList>
#include <Q3RangeControl>
#include <Q3SpinWidget>
#include <Q3Button>
#include <Q3DateTimeEdit>
#include <Q3CanvasItem>

namespace {

// A Q3ServerSocket subclass, because the base is abstract: newConnection() is
// pure virtual. Qt 3's server socket delivered accepted descriptors this way
// rather than through a signal, which is one of the shapes Qt 4 replaced.
class SmokeServerSocket : public Q3ServerSocket
{
public:
    SmokeServerSocket() : Q3ServerSocket(quint16(0)), accepted(0) {}
    void newConnection(int) { ++accepted; }
    int accepted;
};

// Likewise for the abstract halves of the Qt 3 network protocol framework.
class SmokeNetworkProtocol : public Q3NetworkProtocol
{
public:
    int supportedOperations() const { return 0; }
};

class SmokeSyntaxHighlighter : public Q3SyntaxHighlighter
{
public:
    explicit SmokeSyntaxHighlighter(Q3TextEdit *e) : Q3SyntaxHighlighter(e), runs(0) {}
    int highlightParagraph(const QString &, int) { ++runs; return 0; }
    int runs;
};

// Q3GridView is abstract: paintCell() is how a Qt 3 grid drew itself, and
// there was no default.
class SmokeGridView : public Q3GridView
{
public:
    SmokeGridView() : painted(0) {}
    void paintCell(QPainter *, int, int) { ++painted; }
    int painted;
};

class SmokePolygonScanner : public Q3PolygonScanner
{
public:
    SmokePolygonScanner() : spans(0) {}
    void processSpans(int n, QPoint *, int *) { spans += n; }
    int spans;
};

} // namespace

void addQt3SupportChecks(SmokeReporter &r)
{
    // ---- containers and tools ---------------------------------------------
    r.check("qt3/containers", [](QString &d) {
        Q3CString cs("legacy");
        cs += " string";
        Q3StrList list;
        list.append("one");
        list.append("two");
        Q3ValueList<int> values;
        values.append(4);
        values.append(8);
        Q3PtrList<int> ptrs;
        int owned = 7;
        ptrs.append(&owned);
        d = QString::fromLatin1("%1 / %2 / %3 / %4")
                .arg(cs.length()).arg(list.count()).arg(values.count()).arg(ptrs.count());
        return cs == Q3CString("legacy string") && list.count() == 2
            && values.count() == 2 && ptrs.count() == 1
            && Q3PtrCollection::Item(0) == 0;
    });

    r.check("qt3/pointarray-and-signal", [](QString &d) {
        Q3PointArray points(3);
        points.setPoint(0, 0, 0);
        points.setPoint(1, 10, 0);
        points.setPoint(2, 5, 8);
        QRect bounds = points.boundingRect();
        Q3Signal signal;
        signal.setValue(QVariant(42));
        d = QString::fromLatin1("bounds %1x%2, signal %3")
                .arg(bounds.width()).arg(bounds.height()).arg(signal.value().toInt());
        // Qt 3's boundingRect() is inclusive of both edges, so a span of 0..10
        // measures 11 rather than the 10 a QRect built from the same corners
        // would report in Qt 4 terms.
        return points.count() == 3 && bounds.width() == 11 && signal.value().toInt() == 42;
    });

    r.check("qt3/semaphore-and-textstream", [](QString &d) {
        Q3Semaphore sem(2);
        sem++;                       // Qt 3 spelling of acquire()
        const bool held = sem.available() == 1;
        sem--;
        QString target;
        Q3TextStream ts(&target, QIODevice::WriteOnly);
        ts << "value " << 4887;
        d = target;
        return held && sem.available() == 2 && target == QLatin1String("value 4887");
    });

    // ---- plain widgets -----------------------------------------------------
    r.check("qt3/layout-widgets", [](QString &d) {
        QWidget top;
        Q3Frame frame(&top);
        Q3HBox hbox(&top);
        Q3VBox vbox(&top);
        Q3Grid grid(2, &top);
        Q3GroupBox group(&top);
        Q3HGroupBox hgroup(&top);
        Q3VGroupBox vgroup(&top);
        frame.setFrameStyle(Q3Frame::Box | Q3Frame::Raised);
        d = QString::fromLatin1("frame style %1, grid %2")
                .arg(frame.frameStyle()).arg(grid.metaObject()->className());
        return frame.frameStyle() != 0 && hbox.metaObject() && vbox.metaObject()
            && group.metaObject() && hgroup.metaObject() && vgroup.metaObject();
    });

    r.check("qt3/button-groups", [](QString &d) {
        QWidget top;
        Q3ButtonGroup group(&top);
        Q3HButtonGroup hgroup(&top);
        Q3VButtonGroup vgroup(&top);
        d = QString::fromLatin1("%1 / %2 / %3")
                .arg(group.metaObject()->className())
                .arg(hgroup.metaObject()->className())
                .arg(vgroup.metaObject()->className());
        return group.count() == 0 && hgroup.metaObject() && vgroup.metaObject();
    });

    r.check("qt3/input-widgets", [](QString &d) {
        QWidget top;
        Q3ComboBox combo(&top);
        combo.insertItem("first");
        combo.insertItem("second");
        Q3MultiLineEdit edit(&top);
        edit.setText("two\nlines");
        Q3ProgressBar progress(100, &top);
        progress.setProgress(50);
        Q3DateTimeEdit dateTime(&top);
        d = QString::fromLatin1("combo %1, progress %2")
                .arg(combo.count()).arg(progress.progress());
        return combo.count() == 2 && edit.numLines() == 2
            && progress.progress() == 50 && dateTime.metaObject();
    });

    r.check("qt3/scrolling-widgets", [](QString &d) {
        QWidget top;
        Q3ScrollView view(&top);
        view.resizeContents(500, 400);
        SmokeGridView grid;
        grid.setNumRows(4);
        grid.setNumCols(3);
        Q3WidgetStack stack(&top);
        QWidget *page = new QWidget;
        const int id = stack.addWidget(page);
        Q3Header header(&top);
        header.addLabel("column");
        d = QString::fromLatin1("contents %1x%2, grid %3x%4, header %5")
                .arg(view.contentsWidth()).arg(view.contentsHeight())
                .arg(grid.numRows()).arg(grid.numCols()).arg(header.count());
        return view.contentsWidth() == 500 && grid.numRows() == 4
            && id >= 0 && header.count() == 1;
    });

    // ---- item views --------------------------------------------------------
    r.check("qt3/listbox", [](QString &d) {
        QWidget top;
        Q3ListBox box(&top);
        new Q3ListBoxText(&box, "text item");
        new Q3ListBoxPixmap(&box, QPixmap(4, 4));
        Q3ListBoxItem *first = box.item(0);
        d = QString::fromLatin1("%1 items, first '%2'")
                .arg(box.count()).arg(first ? first->text() : QString());
        return box.count() == 2 && first && first->text() == QLatin1String("text item");
    });

    r.check("qt3/listview", [](QString &d) {
        QWidget top;
        Q3ListView view(&top);
        view.addColumn("name");
        Q3ListViewItem *a = new Q3ListViewItem(&view, "alpha");
        new Q3ListViewItem(&view, "beta");
        new Q3CheckListItem(&view, "checked", Q3CheckListItem::CheckBox);
        int seen = 0;
        for (Q3ListViewItemIterator it(&view); it.current(); ++it)
            ++seen;
        d = QString::fromLatin1("%1 children, iterator saw %2")
                .arg(view.childCount()).arg(seen);
        return view.childCount() == 3 && seen == 3
            && a->text(0) == QLatin1String("alpha");
    });

    r.check("qt3/iconview", [](QString &d) {
        QWidget top;
        Q3IconView view(&top);
        new Q3IconViewItem(&view, "first");
        new Q3IconViewItem(&view, "second");
        Q3IconViewItem *item = view.firstItem();
        d = QString::fromLatin1("%1 items").arg(view.count());
        return view.count() == 2 && item && item->text() == QLatin1String("first");
    });

    r.check("qt3/table", [](QString &d) {
        QWidget top;
        Q3Table table(3, 2, &top);
        table.setText(0, 0, "cell");
        table.setItem(1, 0, new Q3TableItem(&table, Q3TableItem::Never, "plain"));
        QStringList choices;
        choices << "one" << "two";
        table.setItem(1, 1, new Q3ComboTableItem(&table, choices));
        table.setItem(2, 0, new Q3CheckTableItem(&table, "checked"));
        Q3TableSelection selection;
        selection.init(0, 0);
        selection.expandTo(1, 1);
        d = QString::fromLatin1("%1x%2, selection %3 rows")
                .arg(table.numRows()).arg(table.numCols())
                .arg(selection.bottomRow() - selection.topRow() + 1);
        return table.numRows() == 3 && table.text(0, 0) == QLatin1String("cell")
            && selection.bottomRow() == 1;
    });

    // ---- rich text ---------------------------------------------------------
    r.check("qt3/text-widgets", [](QString &d) {
        QWidget top;
        Q3TextEdit edit(&top);
        edit.setText("editable");
        Q3TextView view(&top);
        Q3TextBrowser browser(&top);
        SmokeSyntaxHighlighter highlighter(&edit);
        d = QString::fromLatin1("edit '%1', highlighter on %2")
                .arg(edit.text().trimmed())
                .arg(highlighter.textEdit() == &edit ? "the editor" : "nothing");
        return edit.text().contains(QLatin1String("editable"))
            && view.metaObject() && browser.metaObject()
            && highlighter.textEdit() == &edit;
    });

    r.check("qt3/rich-text-engine", [](QString &d) {
        Q3StyleSheet sheet;
        Q3StyleSheetItem *item = sheet.item("p");
        Q3SimpleRichText rich(QLatin1String("<p>rich <b>text</b></p>"), QApplication::font());
        rich.setWidth(200);
        Q3MimeSourceFactory factory;
        d = QString::fromLatin1("width %1, height %2, item %3")
                .arg(rich.width()).arg(rich.height())
                .arg(item ? item->name() : QString());
        return item != 0 && rich.width() > 0 && factory.data("missing") == 0;
    });

    // ---- windows, actions, dialogs ----------------------------------------
    r.check("qt3/mainwindow-and-docks", [](QString &d) {
        Q3MainWindow window;
        Q3ToolBar *bar = new Q3ToolBar(&window);
        Q3DockWindow *dock = new Q3DockWindow(Q3DockWindow::InDock, &window);
        Q3DockArea *area = window.topDock();
        d = QString::fromLatin1("toolbar %1, dock %2, area %3")
                .arg(bar->metaObject()->className())
                .arg(dock->metaObject()->className())
                .arg(area ? area->metaObject()->className() : "none");
        return bar->metaObject() && dock->metaObject() && area != 0;
    });

    r.check("qt3/actions-and-menus", [](QString &d) {
        Q3MainWindow window;
        Q3Action action(&window);
        action.setText("act");
        Q3ActionGroup group(&window);
        group.add(&action);
        Q3PopupMenu menu(&window);
        const int id = menu.insertItem("entry");
        Q3Accel accel(&window);
        const int accelId = accel.insertItem(Qt::CTRL + Qt::Key_S);
        d = QString::fromLatin1("menu id %1, accel id %2").arg(id).arg(accelId);
        return action.text() == QLatin1String("act") && menu.count() == 1
            && accel.count() == 1;
    });

    r.check("qt3/dialogs", [](QString &d) {
        Q3TabDialog tabs;
        tabs.addTab(new QWidget, "one");
        Q3Wizard wizard;
        wizard.addPage(new QWidget, "step");
        Q3FileDialog files;
        Q3ProgressDialog progress;
        progress.setTotalSteps(10);
        d = QString::fromLatin1("wizard %1 pages, progress %2 steps")
                .arg(wizard.pageCount()).arg(progress.totalSteps());
        return wizard.pageCount() == 1 && progress.totalSteps() == 10
            && files.metaObject() && tabs.metaObject();
    });

    r.check("qt3/file-dialog-helpers", [](QString &d) {
        Q3FileIconProvider provider;
        Q3FileDialog dialog;
        Q3FileIconProvider *previous = dialog.iconProvider();
        dialog.setIconProvider(&provider);
        d = QString::fromLatin1("provider installed: %1")
                .arg(dialog.iconProvider() == &provider ? "yes" : "no");
        // Q3FilePreview is a pure interface with one virtual - the file dialog
        // calls into it, so an application implements rather than uses it.
        const bool installed = dialog.iconProvider() == &provider;
        // Qt3Support stores this provider globally, beyond the dialog's lifetime.
        dialog.setIconProvider(previous);
        return installed && sizeof(Q3FilePreview) > 0;
    });

    // ---- canvas ------------------------------------------------------------
    r.check("qt3/canvas", [](QString &d) {
        Q3Canvas canvas(200, 150);
        new Q3CanvasRectangle(QRect(0, 0, 20, 20), &canvas);
        new Q3CanvasEllipse(30, 20, &canvas);
        new Q3CanvasLine(&canvas);
        new Q3CanvasPolygon(&canvas);
        new Q3CanvasSpline(&canvas);
        new Q3CanvasText(&canvas);
        Q3CanvasPixmapArray array;
        new Q3CanvasSprite(&array, &canvas);
        Q3CanvasItemList items = canvas.allItems();
        Q3CanvasView view(&canvas);
        d = QString::fromLatin1("%1x%2 with %3 items")
                .arg(canvas.width()).arg(canvas.height()).arg(items.count());
        return canvas.width() == 200 && items.count() >= 6 && view.canvas() == &canvas;
    });

    // ---- drag and drop -----------------------------------------------------
    r.check("qt3/drag-and-drop", [](QString &d) {
        QWidget top;
        Q3TextDrag textDrag(QLatin1String("dragged"), &top);
        Q3ImageDrag imageDrag(QImage(4, 4, QImage::Format_ARGB32), &top);
        Q3ColorDrag colorDrag(QColor(Qt::red), &top);
        Q3StoredDrag stored("application/x-smoke", &top);
        stored.setEncodedData(QByteArray("payload"));
        Q3UriDrag uris(&top);
        Q3IconDragItem dragItem;
        Q3IconDrag iconDrag(&top);
        Q3DropSite site(&top);
        QString decoded;
        const bool ok = Q3TextDrag::decode(&textDrag, decoded);
        d = QString::fromLatin1("decoded '%1'").arg(decoded);
        return ok && decoded == QLatin1String("dragged")
            && imageDrag.format(0) && colorDrag.format(0)
            && stored.encodedData("application/x-smoke") == QByteArray("payload")
            && uris.metaObject() && iconDrag.metaObject()
            && sizeof(Q3DropSite) > 0 && sizeof(Q3IconDragItem) > 0
            && sizeof(Q3DragObject) > 0;
    });

    // ---- network -----------------------------------------------------------
    r.check("qt3/sockets", [](QString &d) {
        Q3Socket socket;
        Q3SocketDevice device(Q3SocketDevice::Stream, Q3SocketDevice::IPv4, 0);
        SmokeServerSocket server;
        Q3Dns dns(QLatin1String("localhost"));
        d = QString::fromLatin1("server port %1, socket state %2")
                .arg(server.port()).arg(int(socket.state()));
        return server.ok() && device.isValid()
            && dns.label() == QLatin1String("localhost");
    });

    r.check("qt3/network-protocols", [](QString &d) {
        Q3Ftp ftp;
        Q3Http http;
        Q3HttpRequestHeader request(QLatin1String("GET"), QLatin1String("/"));
        // The status-line constructor is protected in Qt3Support - only the
        // protocol implementation was meant to build one - so this is the
        // default header, and what can be asserted about it is that it knows it
        // carries nothing yet.
        Q3HttpResponseHeader response;
        Q3HttpHeader &header = request;
        header.setValue(QLatin1String("Host"), QLatin1String("example.org"));
        SmokeNetworkProtocol protocol;
        Q3NetworkOperation op(Q3NetworkProtocol::OpGet, QString(), QString(), QString());
        Q3LocalFs localFs;
        d = QString::fromLatin1("request '%1', host '%2'")
                .arg(request.method()).arg(request.value(QLatin1String("Host")));
        return request.method() == QLatin1String("GET")
            && request.value(QLatin1String("Host")) == QLatin1String("example.org")
            && !response.isValid()
            && op.operation() == Q3NetworkProtocol::OpGet
            && protocol.supportedOperations() == 0 && localFs.metaObject()
            && ftp.metaObject() && http.metaObject()
            && sizeof(Q3NetworkProtocolFactoryBase) > 0;
    });

    r.check("qt3/url", [](QString &d) {
        Q3Url url(QLatin1String("http://example.org/path/file.txt"));
        Q3UrlOperator op(QLatin1String("file:///tmp"));
        d = QString::fromLatin1("host '%1', file '%2'").arg(url.host(), url.fileName());
        return url.isValid() && url.host() == QLatin1String("example.org")
            && url.fileName() == QLatin1String("file.txt")
            && op.protocol() == QLatin1String("file");
    });

    // ---- sql ---------------------------------------------------------------
    r.check("qt3/sql", [](QString &d) {
        // Constructed without a database: these are the compatibility shapes,
        // and what is being checked is that they exist and hold their fields,
        // not that they can reach a server nothing here is running.
        Q3SqlCursor cursor(QLatin1String("targets"));
        Q3SqlSelectCursor select;
        Q3SqlPropertyMap map;
        Q3SqlRecordInfo info;
        Q3SqlFieldInfo field(QLatin1String("name"), QVariant::String);
        info.append(field);
        Q3SqlForm form;
        Q3EditorFactory *editors = Q3SqlEditorFactory::defaultFactory();
        d = QString::fromLatin1("cursor '%1', record %2 fields")
                .arg(cursor.name()).arg(info.count());
        return cursor.name() == QLatin1String("targets") && info.count() == 1
            && field.name() == QLatin1String("name") && editors != 0
            && form.count() == 0 && select.isActive() == false
            && sizeof(Q3SqlPropertyMap) > 0 && &map != 0;
    });

    r.check("qt3/sql-widgets", [](QString &d) {
        QWidget top;
        Q3DataBrowser browser(&top);
        Q3DataTable table(&top);
        Q3DataView view(&top);
        d = QString::fromLatin1("%1 / %2 / %3")
                .arg(browser.metaObject()->className())
                .arg(table.metaObject()->className())
                .arg(view.metaObject()->className());
        return browser.metaObject() && table.metaObject() && view.metaObject();
    });

    // ---- painting and processes -------------------------------------------
    r.check("qt3/painting", [](QString &d) {
        QPixmap pixmap(40, 30);
        pixmap.fill(Qt::white);
        Q3Painter painter(&pixmap);
        painter.drawRect(QRect(2, 2, 10, 10));
        painter.end();
        Q3PaintDeviceMetrics metrics(&pixmap);
        Q3Picture picture;
        SmokePolygonScanner scanner;
        d = QString::fromLatin1("metrics %1x%2").arg(metrics.width()).arg(metrics.height());
        return metrics.width() == 40 && metrics.height() == 30
            && picture.isNull() && scanner.spans == 0;
    });

    r.check("qt3/process", [](QString &d) {
        Q3Process process;
        process.addArgument(QLatin1String("true"));
        d = QString::fromLatin1("arguments: %1").arg(process.arguments().count());
        return process.arguments().count() == 1 && !process.isRunning();
    });

    // ---- the generic container bases ---------------------------------------
    r.check("qt3/generic-containers", [](QString &d) {
        // The untyped machinery under Q3PtrList, Q3Dict and friends; their interfaces
        // are protected, so the types are referenced.
        Q3StrIList caseInsensitive;
        caseInsensitive.append("Alpha");
        caseInsensitive.append("beta");
        const bool found = caseInsensitive.find("ALPHA") == 0;
        d = QString::fromLatin1("case-insensitive list: %1 items, ALPHA at %2")
                .arg(caseInsensitive.count()).arg(caseInsensitive.find("ALPHA"));
        return found && caseInsensitive.count() == 2
            && sizeof(Q3GArray) > 0 && sizeof(Q3GList) > 0 && sizeof(Q3GDict) > 0
            && sizeof(Q3GVector) > 0 && sizeof(Q3GCache) > 0
            && sizeof(Q3GListIterator) > 0 && sizeof(Q3GDictIterator) > 0
            && sizeof(Q3GCacheIterator) > 0 && sizeof(Q3GListStdIterator) > 0
            && sizeof(Q3LNode) > 0 && sizeof(Q3Shared) > 0;
    });

    // ---- the remaining widgets ---------------------------------------------
    r.check("qt3/spin-and-range", [](QString &d) {
        QWidget top;
        Q3SpinWidget spin(&top);
        // Q3RangeControl is the value/step machinery Qt 3 put behind sliders and
        // spin boxes; Qt 4 folded it into QAbstractSlider.
        Q3RangeControl range;
        range.setRange(0, 100);
        range.setValue(40);
        range.addLine();
        d = QString::fromLatin1("value %1 in %2..%3")
                .arg(range.value()).arg(range.minValue()).arg(range.maxValue());
        return range.value() == 41 && range.maxValue() == 100
            && spin.metaObject() && sizeof(Q3Button) > 0;
    });

    r.check("qt3/date-and-time-editors", [](QString &d) {
        QWidget top;
        Q3DateEdit dateEdit(&top);
        dateEdit.setDate(QDate(2015, 5, 25));
        Q3TimeEdit timeEdit(&top);
        timeEdit.setTime(QTime(12, 30));
        d = QString::fromLatin1("%1 %2")
                .arg(dateEdit.date().toString(Qt::ISODate), timeEdit.time().toString());
        return dateEdit.date().year() == 2015 && timeEdit.time().hour() == 12
            && sizeof(Q3DateTimeEditBase) > 0;
    });

    r.check("qt3/canvas-pixmaps-and-shapes", [](QString &d) {
        Q3Canvas canvas(60, 60);
        QPixmap source(8, 8);
        source.fill(Qt::blue);
        Q3CanvasPixmap pixmap(source.toImage());
        // Q3CanvasPolygonalItem is the base every filled canvas shape derives
        // from - rectangle, ellipse, polygon - so it is reached through one of
        // them rather than on its own.
        Q3CanvasRectangle *rect = new Q3CanvasRectangle(QRect(0, 0, 10, 10), &canvas);
        Q3CanvasPolygonalItem *shape = rect;
        shape->setBrush(QBrush(Qt::green));
        d = QString::fromLatin1("pixmap %1x%2, shape brush %3")
                .arg(pixmap.width()).arg(pixmap.height())
                .arg(shape->brush().color().name());
        return pixmap.width() == 8 && shape->brush().color() == QColor(Qt::green);
    });

    r.check("qt3/dock-area-layout", [](QString &d) {
        Q3MainWindow window;
        Q3DockArea *area = window.topDock();
        // Q3DockAreaLayout is the layout a dock area installs on itself. Its
        // accessor is not public - the area owns it outright - so the type is
        // all that can be named from outside.
        d = QString::fromLatin1("dock area %1")
                .arg(area ? area->metaObject()->className() : "none");
        return area != 0 && sizeof(Q3DockAreaLayout) > 0;
    });

    r.check("qt3/textstream-manipulators", [](QString &d) {
        // Q3TSManip is what a parameterised Q3TextStream manipulator returns -
        // the Qt 3 spelling of what <iomanip> does for std::ostream.
        QString target;
        Q3TextStream ts(&target, QIODevice::WriteOnly);
        ts.width(6);
        ts << 42;
        d = QString::fromLatin1("'%1'").arg(target);
        return target.length() == 6 && target.trimmed() == QLatin1String("42")
            && sizeof(Q3TSManip) > 0;
    });

    r.check("qt3/whats-this", [](QString &d) {
        // Qt 3 stored the help text on the widget; Qt 4 forwards it to
        // QWidget::whatsThis(), which is where it can be read back.
        QWidget top;
        Q3WhatsThis::add(&top, QLatin1String("explains the widget"));
        d = top.whatsThis();
        return top.whatsThis() == QLatin1String("explains the widget");
    });
}
