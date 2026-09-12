// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Headless behavioural self-test over the widget classes. Constructs widgets
// and exercises their behaviour (signals, values, model/view, layouts) without
// showing a window, so it produces the same PASS/FAIL output as the console app
// and is diff-able across OSes. Runs fine under the normal platform (nothing is
// shown) or under -platform offscreen.
#include "../common/smokecheck.h"
#include "gallery.h"

#if !SMOKE_QT5
// Qt 4 counts a click through the spy rather than a lambda; see
// widget/pushbutton-signal below.
#  include <QSignalSpy>
#endif

#include <QPushButton>
#include <QCheckBox>
#include <QRadioButton>
#include <QButtonGroup>
#include <QComboBox>
#include <QLineEdit>
#include <QSpinBox>
#include <QDoubleSpinBox>
#include <QSlider>
#include <QProgressBar>
#include <QLabel>
#include <QTextEdit>
#include <QPlainTextEdit>

#include <QListWidget>
#include <QTreeWidget>
#include <QTableWidget>
#include <QHeaderView>
#include <QListView>
#include <QTreeView>
#include <QTableView>
#include <QStandardItemModel>
#include <QStyledItemDelegate>

#include <QWidget>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QGridLayout>
#include <QFormLayout>
#include <QStackedLayout>
#include <QSplitter>
#include <QTabWidget>
#include <QStackedWidget>
#include <QGroupBox>
#include <QScrollArea>
#include <QMainWindow>
#include <QMenuBar>
#include <QMenu>
#include <QToolBar>
#include <QStatusBar>
#include <QDockWidget>
#include <QAction>
#include <QActionGroup>
#include <QShortcut>
#include <QKeySequence>

#include <QDialog>
#include <QDialogButtonBox>
#include <QMessageBox>
#include <QInputDialog>
#include <QWizard>
#include <QWizardPage>
#include <QColorDialog>
#include <QFontDialog>
#include <QFontDatabase>
#include <QCompleter>

#include <QGraphicsScene>
#include <QGraphicsView>
#include <QGraphicsRectItem>
#include <QGraphicsEllipseItem>
#include <QGraphicsItemGroup>
#include <QGraphicsProxyWidget>

#include <QStringListModel>

void checkWidgets(SmokeReporter &r)
{
    r.check("widget/pushbutton-signal", [&r](QString &d) {
        QPushButton b("Go");
        // Qt 5 and 6 check the functor overload of connect(); Qt 4, which lacks it,
        // counts the click with QSignalSpy.
#if SMOKE_QT5
        int clicks = 0;
        QObject::connect(&b, &QPushButton::clicked, &b, [&]{ ++clicks; });
        b.click();
#else
        QSignalSpy spy(&b, SIGNAL(clicked(bool)));
        b.click();
        const int clicks = spy.count();
#endif
        if (clicks!=1) { d=QString("clicks=%1").arg(clicks); return false; }
        return b.text()=="Go";
    });
    r.check("widget/checkbox-tristate", [&r](QString &d) {
        QCheckBox cb; cb.setTristate(true);
        cb.setCheckState(Qt::PartiallyChecked);
        return cb.checkState()==Qt::PartiallyChecked && cb.isTristate();
    });
    r.check("widget/buttongroup", [&r](QString &d) {
        QButtonGroup g; QRadioButton a("a"), b("b"), c("c");
        g.addButton(&a,1); g.addButton(&b,2); g.addButton(&c,3);
        b.setChecked(true);
        return g.checkedId()==2 && g.buttons().size()==3;
    });
    r.check("widget/combobox", [&r](QString &d) {
        QComboBox cb; cb.addItems({"x","y","z"});
        // currentIndexChanged is overloaded, which is what makes the Qt 5 form
        // need QOverload to say which one. Qt 4 has neither QOverload nor the
        // pointer-to-member connect(), and picks the overload by writing the
        // signature out; the spy then counts the same emission.
#if SMOKE_QT5
        int changed = 0;
        QObject::connect(&cb, QOverload<int>::of(&QComboBox::currentIndexChanged), &cb, [&](int){ ++changed; });
        cb.setCurrentIndex(2);
#else
        QSignalSpy spy(&cb, SIGNAL(currentIndexChanged(int)));
        cb.setCurrentIndex(2);
        const int changed = spy.count();
#endif
        return cb.currentText()=="z" && cb.count()==3 && changed>=1;
    });
    r.check("widget/lineedit-validator", [&r](QString &d) {
        QLineEdit le; le.setMaxLength(5); le.setText("abcdefgh");
        le.setPlaceholderText("type");
        return le.text()=="abcde" && le.maxLength()==5;
    });
    r.check("widget/spinbox-range", [&r](QString &d) {
        QSpinBox sb; sb.setRange(0,10); sb.setValue(99);
        QDoubleSpinBox dsb; dsb.setRange(0,1); dsb.setValue(0.3);
        return sb.value()==10 && qAbs(dsb.value()-0.3)<1e-9;
    });
    r.check("widget/slider-progress", [&r](QString &d) {
        QSlider sl(Qt::Horizontal); sl.setRange(0,100);
        QProgressBar pb; pb.setRange(0,100);
        // String-based: valueChanged/setValue are a signal and a slot in all
        // three versions, and this check is about the widgets rather than about
        // which connect() spelling was used.
        QObject::connect(&sl,SIGNAL(valueChanged(int)),&pb,SLOT(setValue(int)));
        sl.setValue(55);
        return pb.value()==55;
    });
    r.check("widget/textedit", [&r](QString &d) {
        QTextEdit te; te.setHtml("<b>bold</b> text");
        QPlainTextEdit pte; pte.setPlainText("a\nb\nc");
        return te.toPlainText().contains("bold") && pte.document()->blockCount()==3;
    });
    r.check("widget/label-buddy", [&r](QString &d) {
        QLineEdit le; QLabel lab("&Name:"); lab.setBuddy(&le);
        return lab.buddy()==&le && lab.text()=="&Name:";
    });
}

void checkItemViewWidgets(SmokeReporter &r)
{
    r.check("itemview/listwidget", [&r](QString &d) {
        QListWidget lw;
        for (int i=0;i<5;++i) lw.addItem(QString("i%1").arg(i));
        lw.setCurrentRow(2);
        return lw.count()==5 && lw.currentItem()->text()=="i2";
    });
    r.check("itemview/treewidget", [&r](QString &d) {
        QTreeWidget tw; tw.setColumnCount(2);
        auto *root = new QTreeWidgetItem(&tw, {"root","0"});
        new QTreeWidgetItem(root, {"child","1"});
        tw.expandAll();
        return tw.topLevelItemCount()==1 && root->childCount()==1 && tw.columnCount()==2;
    });
    r.check("itemview/tablewidget", [&r](QString &d) {
        QTableWidget t(3,2);
        t.setItem(0,0,new QTableWidgetItem("hi"));
        t.setHorizontalHeaderLabels({"A","B"});
        return t.rowCount()==3 && t.columnCount()==2 && t.item(0,0)->text()=="hi"
               && t.horizontalHeaderItem(1)->text()=="B";
    });
    r.check("itemview/view+model+delegate", [&r](QString &d) {
        QStandardItemModel m(3,1);
        for (int i=0;i<3;++i) m.setItem(i,0,new QStandardItem(QString("row%1").arg(i)));
        QListView lv; lv.setModel(&m);
        QTreeView tv; tv.setModel(&m);
        QTableView tbl; tbl.setModel(&m);
        QStyledItemDelegate del; lv.setItemDelegate(&del);
        return lv.model()->rowCount()==3 && tv.model()==&m && tbl.model()==&m && lv.itemDelegate()==&del;
    });
}

void checkLayoutsAndWindows(SmokeReporter &r)
{
    r.check("layout/box-grid-form", [&r](QString &d) {
        QWidget w;
        auto *v = new QVBoxLayout(&w);
        auto *h = new QHBoxLayout; h->addWidget(new QLabel("a")); h->addWidget(new QLabel("b"));
        v->addLayout(h);
        auto *grid = new QGridLayout; grid->addWidget(new QPushButton("g"),0,0);
        v->addLayout(grid);
        auto *form = new QFormLayout; form->addRow("k", new QLineEdit);
        v->addLayout(form);
        return w.layout()==v && v->count()==3 && h->count()==2;
    });
    r.check("layout/stacked+splitter", [&r](QString &d) {
        QWidget host; auto *st = new QStackedLayout(&host);
        st->addWidget(new QLabel("0")); st->addWidget(new QLabel("1"));
        st->setCurrentIndex(1);
        QSplitter sp(Qt::Horizontal); sp.addWidget(new QLabel("l")); sp.addWidget(new QLabel("r"));
        return st->count()==2 && st->currentIndex()==1 && sp.count()==2;
    });
    r.check("window/tab+stacked", [&r](QString &d) {
        QTabWidget tabs;
        tabs.addTab(new QLabel("one"), "One");
        tabs.addTab(new QLabel("two"), "Two");
        tabs.setCurrentIndex(1);
        QStackedWidget sw; sw.addWidget(new QLabel("x"));
        return tabs.count()==2 && tabs.tabText(1)=="Two" && sw.count()==1;
    });
    r.check("window/mainwindow-chrome", [&r](QString &d) {
        QMainWindow win;
        QMenuBar *mb = win.menuBar();
        QMenu *file = mb->addMenu("&File");
        QAction *quit = file->addAction("&Quit");
        QToolBar *tb = win.addToolBar("main"); tb->addAction(quit);
        win.statusBar()->showMessage("ready");
        auto *dock = new QDockWidget("Dock"); win.addDockWidget(Qt::LeftDockWidgetArea, dock);
        win.setCentralWidget(new QLabel("center"));
        return mb->actions().size()==1 && file->actions().contains(quit)
               && win.statusBar()->currentMessage()=="ready";
    });
    r.check("action/group+shortcut", [&r](QString &d) {
        QWidget host;
        QActionGroup grp(&host);
        QAction *a1 = grp.addAction("One"); a1->setCheckable(true);
        QAction *a2 = grp.addAction("Two"); a2->setCheckable(true);
        a2->setChecked(true);
        a1->setShortcut(QKeySequence("Ctrl+1"));
        QShortcut sc(QKeySequence("Ctrl+Q"), &host);
        return grp.checkedAction()==a2 && a1->shortcut()==QKeySequence("Ctrl+1") && !sc.key().isEmpty();
    });
    r.check("widget/completer", [&r](QString &d) {
        QStringListModel m; m.setStringList({"apple","apricot","banana"});
        QCompleter comp(&m);
        comp.setCompletionPrefix("ap");
        QLineEdit le; le.setCompleter(&comp);
        return le.completer()==&comp && comp.model()==&m;
    });
}

void checkDialogs(SmokeReporter &r)
{
    r.check("dialog/buttonbox", [&r](QString &d) {
        QDialog dlg;
        // Set the buttons rather than pass them to the constructor: Qt 4's
        // second parameter is Qt::Orientation, and the overload that takes the
        // parent there does not exist. setStandardButtons() is the one spelling
        // all three versions accept.
        auto *bb = new QDialogButtonBox(&dlg);
        bb->setStandardButtons(QDialogButtonBox::Ok|QDialogButtonBox::Cancel);
        QObject::connect(bb,SIGNAL(accepted()),&dlg,SLOT(accept()));
        QObject::connect(bb,SIGNAL(rejected()),&dlg,SLOT(reject()));
        return bb->button(QDialogButtonBox::Ok)!=nullptr && bb->button(QDialogButtonBox::Cancel)!=nullptr;
    });
    r.check("dialog/messagebox-construct", [&r](QString &d) {
        // Construct (do NOT exec) - just verify it builds with buttons/icon.
        QMessageBox mb(QMessageBox::Warning, "Title", "Body text",
                       QMessageBox::Yes|QMessageBox::No);
        mb.setDefaultButton(QMessageBox::No);
        return mb.icon()==QMessageBox::Warning && mb.text()=="Body text"
               && mb.standardButtons()==(QMessageBox::Yes|QMessageBox::No);
    });
    r.check("dialog/inputdialog-construct", [&r](QString &d) {
        QInputDialog dlg;
        dlg.setInputMode(QInputDialog::IntInput);
        dlg.setIntRange(0,10); dlg.setIntValue(5);
        dlg.setLabelText("Pick");
        return dlg.intValue()==5 && dlg.labelText()=="Pick";
    });
    r.check("dialog/wizard", [&r](QString &d) {
        QWizard wiz;
        auto *p1 = new QWizardPage; p1->setTitle("Intro");
        auto *p2 = new QWizardPage; p2->setTitle("Details");
        int id1 = wiz.addPage(p1); wiz.addPage(p2);
        wiz.setStartId(id1);
        return wiz.pageIds().size()==2 && wiz.page(id1)==p1;
    });
    r.check("dialog/color+font-construct", [&r](QString &d) {
        QColorDialog cd; cd.setCurrentColor(Qt::red);
        if (QFontDatabase().families().isEmpty()) {
            r.skip(d, QStringLiteral("no fonts available to construct a useful QFontDialog"));
            return false;
        }
        QFontDialog fd; fd.setCurrentFont(QFont("Arial",11));
        const QFont currentFont = fd.currentFont();
        return cd.currentColor()==QColor(Qt::red) && !currentFont.family().isEmpty()
            && currentFont.pointSize()!=0;
    });
}

void checkGraphicsScene(SmokeReporter &r)
{
    r.check("graphics/scene-items", [&r](QString &d) {
        QGraphicsScene scene(0,0,200,200);
        auto *rect = scene.addRect(0,0,50,50);
        auto *ell = scene.addEllipse(60,0,50,50);
        scene.addLine(0,100,200,100);
        auto *txt = scene.addText("hi");
        if (scene.items().size()!=4) { d=QString("items=%1").arg(scene.items().size()); return false; }
        // Reached through the real base every scene item derives from.
        QGraphicsItem *base = rect;
        return rect->rect().width()==50 && ell->rect().height()==50 && txt->toPlainText()=="hi"
               && base->scene()==&scene;
    });
    r.check("graphics/item-group+transform", [&r](QString &d) {
        QGraphicsScene scene;
        auto *r1 = scene.addRect(0,0,10,10);
        auto *r2 = scene.addRect(20,0,10,10);
        auto *group = scene.createItemGroup({r1,r2});
        group->setRotation(45);
        return group->childItems().size()==2 && !qFuzzyIsNull(group->rotation());
    });
    r.check("graphics/view+scene-rect", [&r](QString &d) {
        QGraphicsScene scene(0,0,300,150);
        QGraphicsView view(&scene);
        return view.scene()==&scene && scene.sceneRect().width()==300;
    });
    r.check("graphics/proxywidget", [&r](QString &d) {
        QGraphicsScene scene;
        auto *proxy = scene.addWidget(new QPushButton("proxy"));
        return proxy!=nullptr && scene.items().size()==1;
    });
}
