// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Builds the visual gallery: one tab per widget cluster. Each tab constructs a
// representative set of that cluster's widgets so the window can be eyeballed on
// each target OS (fonts, styles, message box background, native dialogs...).
#include "gallery.h"
#include "../common/qtcompat.h"
#include "../common/smokecheck.h"
#include <QDir>
#include <memory>
#if defined(Q_OS_WIN) && defined(QT_WIN95_SUPPORT)
#include <windows.h>
#include <malloc.h>
#include <cstdio>
#endif

#include <QTabBar>
#include <QWidget>
#include <QGroupBox>
#include <QScrollArea>

#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QGridLayout>
#include <QFormLayout>

#include <QPushButton>
#include <QToolButton>
#include <QRadioButton>
#include <QCheckBox>
#include <QCommandLinkButton>
#include <QButtonGroup>
#include <QDialogButtonBox>
#include <QMessageBox>
#include <QInputDialog>
#include <QColorDialog>
#include <QFontDialog>
#include <QFileDialog>
#include <QErrorMessage>
#include <QProgressDialog>
#include <QWizard>
#include <QWizardPage>
#include <QMenu>
#include <QCursor>
#include <QToolTip>
#include <QWhatsThis>
#include <QPageSetupDialog>
#include <QPrintDialog>
#include <QPrinter>

#include <QLineEdit>
#include <QTextEdit>
#include <QPlainTextEdit>
#include <QComboBox>
#include <QCompleter>
#include <QFontComboBox>
#include <QLabel>
#if SMOKE_QT5
#  include <QKeySequenceEdit>          // Qt 5.2 and later
#endif

#include <QSpinBox>
#include <QDoubleSpinBox>
#include <QSlider>
#include <QDial>
#include <QScrollBar>
#include <QProgressBar>
#include <QLCDNumber>
#include <QDateTimeEdit>
#include <QCalendarWidget>
#include <QDateEdit>

#include <QListWidget>
#include <QListView>
#include <QTreeWidget>
#include <QTreeView>
#include <QTableWidget>
#include <QTableView>
#include <QColumnView>
#include <QHeaderView>
#include <QStandardItemModel>
#include <QSortFilterProxyModel>
#include <QStyledItemDelegate>
#include <QStringListModel>

#include <QSplitter>
#include <QToolBox>
#include <QStackedWidget>
#include <QFrame>

#include <QTextBrowser>

#include <QGraphicsView>
#include <QGraphicsScene>
#include <QGraphicsTextItem>

#include <QApplication>
#include <QClipboard>
#include <QContextMenuEvent>
#include <QCoreApplication>
#include <QDrag>
#include <QDragEnterEvent>
#include <QDragLeaveEvent>
#include <QDragMoveEvent>
#include <QDropEvent>
#include <QFontDatabase>
#if SMOKE_QT5
#  include <QGuiApplication>           // the Qt 5 application split
#endif
#include <QImage>
#include <QMimeData>
#include <QMouseEvent>
#if SMOKE_QT5
#  include <QOperatingSystemVersion>   // Qt 5.9 and later
#endif
#include <QPainter>
#include <QPaintEvent>
#include <QDateTime>
#include <QResizeEvent>
#if SMOKE_QT5
#  include <QScreen>                   // screens became objects in Qt 5
#else
#  include <QDesktopWidget>              // Qt 4 asks the desktop widget instead
#endif
#include <QStyle>
#include <QStyleFactory>
#include <QStyleOptionTab>
#include <QStylePainter>
#include <QStringList>
#include <QTimer>
#include <QUrl>
#include <QVariant>

#include <functional>

// SMOKE_HAVE_WINEXTRAS, not Q_OS_WIN: Qt 6 on Windows has no QtWinExtras.
#if defined(Q_OS_WIN) && defined(SMOKE_HAVE_WINEXTRAS)
#include <QtWinExtras/QWinJumpList>
#include <QtWinExtras/QWinJumpListCategory>
#include <QtWinExtras/QWinJumpListItem>
#include <QtWinExtras/QWinTaskbarButton>
#include <QtWinExtras/QWinTaskbarProgress>
#include <QtWinExtras/QWinThumbnailToolBar>
#include <QtWinExtras/QWinThumbnailToolButton>
#endif

// One connect() for Qt 4, 5 and 6: Qt 4 cannot connect a lambda, so functors
// go through a slot on a small QObject parented to the context.
class SmokeFunctorSlot : public QObject
{
    Q_OBJECT

public:
    SmokeFunctorSlot(const std::function<void()> &fn, QObject *parent)
        : QObject(parent), m_fn(fn) {}
    SmokeFunctorSlot(const std::function<void(int)> &fn, QObject *parent)
        : QObject(parent), m_fnInt(fn) {}

public slots:
    void run() { if (m_fn) m_fn(); }
    void runInt(int value) { if (m_fnInt) m_fnInt(value); }

private:
    std::function<void()> m_fn;
    std::function<void(int)> m_fnInt;
};

static void smokeConnect(QObject *sender, const char *signal, QObject *context,
                         const std::function<void()> &fn)
{
    QObject::connect(sender, signal,
                     new SmokeFunctorSlot(fn, context ? context : sender), SLOT(run()));
}

static void smokeConnectInt(QObject *sender, const char *signal, QObject *context,
                            const std::function<void(int)> &fn)
{
    QObject::connect(sender, signal,
                     new SmokeFunctorSlot(fn, context ? context : sender), SLOT(runInt(int)));
}

static QWidget *inScroll(QWidget *inner)
{
    auto *sa = new QScrollArea;
    sa->setWidget(inner);
    sa->setWidgetResizable(true);
    return sa;
}

static QPushButton *gridButton(QGridLayout *grid, int row, int column, const QString &text,
                               const std::function<void()> &slot)
{
    auto *button = new QPushButton(text);
    smokeConnect(button, SIGNAL(clicked()), button, slot);
    grid->addWidget(button, row, column);
    return button;
}

static void showWindowCentered(QWidget *window)
{
#if SMOKE_QT5
    QScreen *screen = QGuiApplication::screenAt(QCursor::pos());
    if (!screen)
        screen = QGuiApplication::primaryScreen();
    const QRect area = screen ? screen->availableGeometry() : QRect();
#else
    // Qt 4 has no QScreen object; the desktop widget answers the same question.
    QDesktopWidget *desktop = QApplication::desktop();
    const QRect area = desktop ? desktop->availableGeometry(QCursor::pos()) : QRect();
#endif
    if (!area.isNull())
        window->move(area.center() - QPoint(window->width() / 2, window->height() / 2));
    window->show();
}

static bool isWindows7OrNewer()
{
#ifdef Q_OS_WIN
#  if SMOKE_QT5
    const QOperatingSystemVersion current = QOperatingSystemVersion::current();
    return current.type() == QOperatingSystemVersion::Windows && current.majorVersion() >= 6;
#  else
    // Qt 4 predates QOperatingSystemVersion; WV_WINDOWS7 is its name for the
    // same release, and the enum is ordered so later versions compare greater.
    return QSysInfo::windowsVersion() >= QSysInfo::WV_WINDOWS7;
#  endif
#else
    return false;
#endif
}

class ShapedSmokeWindow : public QWidget
{
public:
    explicit ShapedSmokeWindow(const QString &title, bool translucent, QWidget *parent = nullptr)
        : QWidget(parent, Qt::Window | Qt::FramelessWindowHint), m_title(title), m_translucent(translucent)
    {
        setAttribute(Qt::WA_DeleteOnClose);
        setAttribute(Qt::WA_TranslucentBackground, translucent);
        setWindowTitle(title);
        resize(260, 150);
        setMask(QRegion(rect(), QRegion::Ellipse));
        setContextMenuPolicy(Qt::DefaultContextMenu);
        m_ok = new QPushButton(QStringLiteral("OK"), this);
        m_ok->setFixedWidth(64);
        m_ok->move((width() - m_ok->width()) / 2, height() - m_ok->height() - 22);
        QObject::connect(m_ok, SIGNAL(clicked()), this, SLOT(close()));
    }

protected:
    void resizeEvent(QResizeEvent *) override
    {
        setMask(QRegion(rect(), QRegion::Ellipse));
        if (m_ok)
            m_ok->move((width() - m_ok->width()) / 2, height() - m_ok->height() - 22);
    }

    void paintEvent(QPaintEvent *) override
    {
        QPainter painter(this);
        painter.setRenderHint(QPainter::Antialiasing);
        QColor fill = m_translucent ? QColor(30, 120, 180, 190) : QColor(240, 245, 250);
        painter.setPen(QPen(QColor(20, 60, 90), 2));
        painter.setBrush(fill);
        painter.drawEllipse(rect().adjusted(2, 2, -3, -3));
        painter.setPen(m_translucent ? Qt::white : Qt::black);
        painter.drawText(rect(), Qt::AlignCenter, m_title + "\nRight click for menu\nDrag to move");
    }

    void mousePressEvent(QMouseEvent *event) override
    {
        if (event->button() == Qt::LeftButton)
            m_dragOffset = event->globalPos() - frameGeometry().topLeft();
    }

    void mouseMoveEvent(QMouseEvent *event) override
    {
        if (event->buttons().testFlag(Qt::LeftButton))
            move(event->globalPos() - m_dragOffset);
    }

    void contextMenuEvent(QContextMenuEvent *event) override
    {
        QMenu menu(this);
        // addAction(text, receiver, functor) is Qt 5.6; adding the action and
        // connecting it is what that overload does for you.
        smokeConnect(menu.addAction("Restore size"), SIGNAL(triggered()), this, [this] {
            resize(260, 150);
            setMask(QRegion(rect(), QRegion::Ellipse));
        });
        smokeConnect(menu.addAction("Toggle opacity"), SIGNAL(triggered()), this, [this] {
            setWindowOpacity(qFuzzyCompare(windowOpacity(), 1.0) ? 0.78 : 1.0);
        });
        menu.addSeparator();
        QObject::connect(menu.addAction("Close"), SIGNAL(triggered()), this, SLOT(close()));
        menu.exec(event->globalPos());
    }

private:
    QString m_title;
    QPoint m_dragOffset;
    QPushButton *m_ok = nullptr;
    bool m_translucent = false;
};

class DropArea : public QLabel
{
public:
    explicit DropArea(QWidget *parent = nullptr) : QLabel(parent)
    {
        setAcceptDrops(true);
        setFrameStyle(QFrame::StyledPanel | QFrame::Sunken);
        setAlignment(Qt::AlignCenter);
        setMinimumHeight(120);
        setWordWrap(true);
        setText("Drop text here");
        setStyleSheet("QLabel { background: #f3f4f6; border: 1px solid #94a3b8; padding: 12px; }");
    }

protected:
    void dragEnterEvent(QDragEnterEvent *event) override
    {
        if (event->mimeData()->hasText()) {
            setStyleSheet("QLabel { background: #dcfce7; border: 1px solid #16a34a; padding: 12px; }");
            event->acceptProposedAction();
        }
    }

    void dragLeaveEvent(QDragLeaveEvent *) override
    {
        setStyleSheet("QLabel { background: #f3f4f6; border: 1px solid #94a3b8; padding: 12px; }");
    }

    void dragMoveEvent(QDragMoveEvent *event) override
    {
        if (event->mimeData()->hasText())
            event->acceptProposedAction();
    }

    void dropEvent(QDropEvent *event) override
    {
        const QMimeData *mime = event->mimeData();
        if (mime->hasText()) {
            setStyleSheet("QLabel { background: #ecfdf5; border: 1px solid #16a34a; padding: 12px; }");
            setText(QStringLiteral("Received text:\n%1").arg(mime->text()));
            event->acceptProposedAction();
        }
    }
};

class DragTextItem : public QLabel
{
public:
    explicit DragTextItem(const QString &text, QWidget *parent = nullptr) : QLabel(text, parent)
    {
        setFrameStyle(QFrame::StyledPanel | QFrame::Raised);
        setAlignment(Qt::AlignCenter);
        setMinimumHeight(42);
        setCursor(Qt::OpenHandCursor);
        setStyleSheet("QLabel { background: #dbeafe; border: 1px solid #2563eb; padding: 8px; }");
    }

protected:
    void mousePressEvent(QMouseEvent *event) override
    {
        if (event->button() == Qt::LeftButton)
            m_dragStart = event->pos();
        QLabel::mousePressEvent(event);
    }

    void mouseMoveEvent(QMouseEvent *event) override
    {
        if (!(event->buttons() & Qt::LeftButton))
            return;
        if ((event->pos() - m_dragStart).manhattanLength() < QApplication::startDragDistance())
            return;

        auto *mime = new QMimeData;
        mime->setText(text());

        auto *drag = new QDrag(this);
        drag->setMimeData(mime);
        drag->exec(Qt::CopyAction);
    }

private:
    QPoint m_dragStart;
};

class ClearableTabBar : public QTabBar
{
public:
    using QTabBar::QTabBar;

    void setVisualCurrentIndex(int index)
    {
        m_hasVisualCurrent = index >= 0;
        if (m_hasVisualCurrent && currentIndex() != index)
            setCurrentIndex(index);
        update();
    }

protected:
    void paintEvent(QPaintEvent *) override
    {
        QStylePainter painter(this);
        for (int i = 0; i < count(); ++i) {
            QStyleOptionTab option;
            initStyleOption(&option, i);
            if (!m_hasVisualCurrent) {
                option.state &= ~QStyle::State_Selected;
                option.state &= ~QStyle::State_HasFocus;
            }
            painter.drawControl(QStyle::CE_TabBarTab, option);
        }
    }

private:
    bool m_hasVisualCurrent = true;
};

class TwoRowTabWidget : public QWidget
{
public:
    explicit TwoRowTabWidget(QWidget *parent = nullptr) : QWidget(parent)
    {
        auto *layout = new QVBoxLayout(this);
        layout->setContentsMargins(0, 0, 0, 0);
        layout->setSpacing(0);

        m_firstRow = new ClearableTabBar;
        m_secondRow = new ClearableTabBar;
        setupTabBar(m_firstRow);
        setupTabBar(m_secondRow);
        layout->addWidget(m_firstRow);
        layout->addWidget(m_secondRow);

        m_stack = new QStackedWidget;
        layout->addWidget(m_stack, 1);

        smokeConnectInt(m_firstRow, SIGNAL(currentChanged(int)), this, [this](int tab) {
            if (!m_updating && tab >= 0)
                selectPage(m_firstRowPages.value(tab, -1));
        });
        smokeConnectInt(m_secondRow, SIGNAL(currentChanged(int)), this, [this](int tab) {
            if (!m_updating && tab >= 0)
                selectPage(m_secondRowPages.value(tab, -1));
        });
        // tabBarClicked is Qt 5.2. It re-selects a page when the already-current
        // tab is clicked again, which currentChanged does not report; on Qt 4
        // that one refinement is simply absent.
#if SMOKE_QT5
        smokeConnectInt(m_firstRow, SIGNAL(tabBarClicked(int)), this, [this](int tab) {
            if (!m_updating && tab >= 0)
                selectPage(m_firstRowPages.value(tab, -1));
        });
        smokeConnectInt(m_secondRow, SIGNAL(tabBarClicked(int)), this, [this](int tab) {
            if (!m_updating && tab >= 0)
                selectPage(m_secondRowPages.value(tab, -1));
        });
#endif
    }

    void addPage(QWidget *page, const QString &label, int row)
    {
        const int pageIndex = m_stack->addWidget(page);
        QTabBar *bar = row == 0 ? m_firstRow : m_secondRow;
        QList<int> &pages = row == 0 ? m_firstRowPages : m_secondRowPages;
        pages << pageIndex;
        bar->addTab(label);
    }

    void selectPage(int pageIndex)
    {
        if (pageIndex < 0)
            return;
        m_updating = true;
        m_stack->setCurrentIndex(pageIndex);
        m_firstRow->setVisualCurrentIndex(m_firstRowPages.indexOf(pageIndex));
        m_secondRow->setVisualCurrentIndex(m_secondRowPages.indexOf(pageIndex));
        m_updating = false;
    }

    int pageCount() const { return m_stack->count(); }
    QString pageName(int pageIndex) const
    {
        const int first = m_firstRowPages.indexOf(pageIndex);
        return first >= 0 ? m_firstRow->tabText(first)
                          : m_secondRow->tabText(m_secondRowPages.indexOf(pageIndex));
    }

private:
    static void setupTabBar(QTabBar *bar)
    {
        bar->setShape(QTabBar::RoundedNorth);
        bar->setExpanding(false);
        bar->setUsesScrollButtons(false);
        bar->setElideMode(Qt::ElideNone);
        bar->setDrawBase(false);
    }

    ClearableTabBar *m_firstRow = nullptr;
    ClearableTabBar *m_secondRow = nullptr;
    QStackedWidget *m_stack = nullptr;
    QList<int> m_firstRowPages;
    QList<int> m_secondRowPages;
    bool m_updating = false;
};

QWidget *makeButtonsTab()
{
    auto *w = new QWidget;
    auto *lay = new QVBoxLayout(w);

    auto *push = new QGroupBox("Buttons");
    auto *g = new QHBoxLayout(push);
    g->addWidget(new QPushButton("Push"));
    auto *def = new QPushButton("Default"); def->setDefault(true); g->addWidget(def);
    auto *tool = new QToolButton; tool->setText("Tool"); g->addWidget(tool);
    g->addWidget(new QCommandLinkButton("Command", "with a description"));
    lay->addWidget(push);

    auto *choices = new QGroupBox("Radio / Check");
    auto *cg = new QVBoxLayout(choices);
    auto *bg = new QButtonGroup(choices);
    for (auto t : {"Alpha","Beta","Gamma"}) { auto *rb = new QRadioButton(t); bg->addButton(rb); cg->addWidget(rb); }
    auto *cb = new QCheckBox("Tristate"); cb->setTristate(true); cg->addWidget(cb);
    lay->addWidget(choices);

    lay->addWidget(new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel | QDialogButtonBox::Apply));
    lay->addStretch();
    return inScroll(w);
}

QWidget *makeInputsTab()
{
    auto *w = new QWidget;
    auto *form = new QFormLayout(w);
    auto *le = new QLineEdit("editable");
#if SMOKE_QT5
    le->setClearButtonEnabled(true);   // Qt 5.2 and later
#endif
    form->addRow("Line edit:", le);
    auto *pw = new QLineEdit; pw->setEchoMode(QLineEdit::Password); pw->setText("secret");
    form->addRow("Password:", pw);
    auto *combo = new QComboBox; combo->addItems({"One","Two","Three"}); combo->setEditable(true);
    form->addRow("Combo:", combo);
    form->addRow("Font combo:", new QFontComboBox);
#if SMOKE_QT5
    form->addRow("Key sequence:", new QKeySequenceEdit);   // Qt 5.2 and later
#endif
    auto *te = new QTextEdit; te->setHtml("<b>Rich</b> <i>text</i> edit");
    form->addRow("Text edit:", te);
    auto *pte = new QPlainTextEdit("Plain text\nsecond line");
    form->addRow("Plain text:", pte);
    return inScroll(w);
}

QWidget *makeRangesTab()
{
    auto *w = new QWidget;
    auto *form = new QFormLayout(w);
    auto *sb = new QSpinBox; sb->setRange(0,100); sb->setValue(42);
    form->addRow("Spin:", sb);
    auto *dsb = new QDoubleSpinBox; dsb->setRange(0,1); dsb->setSingleStep(0.1); dsb->setValue(0.5);
    form->addRow("Double spin:", dsb);
    auto *sl = new QSlider(Qt::Horizontal); sl->setRange(0,100); sl->setValue(60);
    form->addRow("Slider:", sl);
    form->addRow("Dial:", new QDial);
    form->addRow("Scrollbar:", new QScrollBar(Qt::Horizontal));
    auto *pb = new QProgressBar; pb->setRange(0,100); pb->setValue(70);
    form->addRow("Progress:", pb);
    auto *lcd = new QLCDNumber; lcd->display(1234);
    form->addRow("LCD:", lcd);
    form->addRow("Date/time:", new QDateTimeEdit(QDateTime::currentDateTime()));
    form->addRow("Calendar:", new QCalendarWidget);
    return inScroll(w);
}

QWidget *makeItemViewsTab()
{
    auto *w = new QWidget;
    auto *lay = new QHBoxLayout(w);

    auto *list = new QListWidget;
    for (int i=0;i<8;++i) list->addItem(QString("Item %1").arg(i));
    lay->addWidget(list);

    auto *tree = new QTreeWidget; tree->setHeaderLabels({"Name","Value"});
    for (int i=0;i<3;++i) {
        auto *top = new QTreeWidgetItem(tree, {QString("Node %1").arg(i), QString::number(i)});
        for (int j=0;j<2;++j) new QTreeWidgetItem(top, {QString("child %1").arg(j), "x"});
    }
    tree->expandAll();
    lay->addWidget(tree);

    auto *table = new QTableWidget(4,3);
    table->setHorizontalHeaderLabels({"A","B","C"});
    for (int r=0;r<4;++r) for (int c=0;c<3;++c)
        table->setItem(r,c,new QTableWidgetItem(QString("%1,%2").arg(r).arg(c)));
    table->horizontalHeader()->setStretchLastSection(true);
    lay->addWidget(table);

    return w;
}

QWidget *makeContainersTab()
{
    auto *splitter = new QSplitter(Qt::Horizontal);

    auto *toolbox = new QToolBox;
    for (auto n : {"Page 1","Page 2","Page 3"}) {
        auto *p = new QLabel(QString("Contents of %1").arg(n)); p->setAlignment(Qt::AlignCenter);
        toolbox->addItem(p, n);
    }
    splitter->addWidget(toolbox);

    auto *stacked = new QStackedWidget;
    for (int i=0;i<3;++i) { auto *l=new QLabel(QString("Stack %1").arg(i)); l->setAlignment(Qt::AlignCenter); stacked->addWidget(l); }
    auto *frame = new QFrame; frame->setFrameStyle(QFrame::Box | QFrame::Sunken);
    auto *fl = new QVBoxLayout(frame); fl->addWidget(stacked);
    splitter->addWidget(frame);

    return splitter;
}

QWidget *makeTextTab()
{
    auto *w = new QWidget;
    auto *lay = new QVBoxLayout(w);
    auto *browser = new QTextBrowser;
    browser->setHtml("<h2>QTextBrowser</h2><p>Rich text with a "
                     "<a href='#section'>link</a>, <b>bold</b>, <i>italic</i>, and a list:</p>"
                     "<ul><li>one</li><li>two</li><li>three</li></ul>");
    lay->addWidget(browser);
    return w;
}

QWidget *makeGraphicsTab()
{
    auto *scene = new QGraphicsScene(0,0,300,200);
    scene->addRect(10,10,120,80);
    scene->addEllipse(150,20,120,80);
    scene->addLine(10,150,290,150);
    auto *txt = scene->addText("QGraphicsScene");
    txt->setPos(20,110);
    auto *view = new QGraphicsView(scene);
    view->setRenderHints(QPainter::Antialiasing);
    return view;
}

QWidget *makePopupsTab()
{
    auto *w = new QWidget;
    auto *lay = new QVBoxLayout(w);

    auto *messages = new QGroupBox("Message boxes");
    auto *messageGrid = new QGridLayout(messages);
    auto addButton = [&](QGridLayout *grid, int row, int column, const QString &text, auto slot) {
        auto *button = new QPushButton(text);
        smokeConnect(button, SIGNAL(clicked()), w, slot);
        grid->addWidget(button, row, column);
    };

    addButton(messageGrid, 0, 0, "Information", [w] {
        QMessageBox::information(w, "Information", "Information message box");
    });
    addButton(messageGrid, 0, 1, "Warning", [w] {
        QMessageBox::warning(w, "Warning", "Warning message box");
    });
    addButton(messageGrid, 0, 2, "Critical", [w] {
        QMessageBox::critical(w, "Critical", "Critical message box");
    });
    addButton(messageGrid, 1, 0, "Question", [w] {
        QMessageBox::question(w, "Question", "Question message box",
                              QMessageBox::Yes | QMessageBox::No | QMessageBox::Cancel);
    });
    addButton(messageGrid, 1, 1, "About", [w] {
        QMessageBox::about(w, "About", "Qt Widgets Gallery popup smoke test");
    });
    addButton(messageGrid, 1, 2, "About Qt", [w] {
        QMessageBox::aboutQt(w, "About Qt");
    });
    lay->addWidget(messages);

    auto *dialogs = new QGroupBox("Dialogs");
    auto *dialogGrid = new QGridLayout(dialogs);
    addButton(dialogGrid, 0, 0, "Color Dialog", [w] {
        QColorDialog::getColor(Qt::green, w, "Pick color", QColorDialog::ShowAlphaChannel);
    });
    addButton(dialogGrid, 0, 1, "Font Dialog", [w] {
        bool ok = false;
        QFontDialog::getFont(&ok, QFont("Arial", 10), w, "Pick font");
    });
    addButton(dialogGrid, 0, 2, "Open File", [w] {
        QFileDialog::getOpenFileName(w, "Open file", QString(), "All files (*.*)");
    });
    addButton(dialogGrid, 1, 0, "Save File", [w] {
        QFileDialog::getSaveFileName(w, "Save file", QString(), "Text files (*.txt);;All files (*.*)");
    });
    addButton(dialogGrid, 1, 1, "Directory", [w] {
        QFileDialog::getExistingDirectory(w, "Select directory");
    });
    addButton(dialogGrid, 1, 2, "Custom Dialog", [w] {
        auto *dlg = new QDialog(w);
        dlg->setAttribute(Qt::WA_DeleteOnClose);
        dlg->setWindowTitle("Custom dialog");
        auto *v = new QVBoxLayout(dlg);
        v->addWidget(new QLabel("Custom modal-looking dialog with button box"));
        auto *buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel);
        QObject::connect(buttons, SIGNAL(accepted()), dlg, SLOT(accept()));
        QObject::connect(buttons, SIGNAL(rejected()), dlg, SLOT(reject()));
        v->addWidget(buttons);
        dlg->show();
    });
    lay->addWidget(dialogs);

    auto *inputs = new QGroupBox("Input / progress");
    auto *inputGrid = new QGridLayout(inputs);
    addButton(inputGrid, 0, 0, "Input Text", [w] {
        QInputDialog::getText(w, "Input text", "Value:");
    });
    addButton(inputGrid, 0, 1, "Input Int", [w] {
        QInputDialog::getInt(w, "Input int", "Number:", 5, 0, 100);
    });
    addButton(inputGrid, 0, 2, "Input Item", [w] {
        QInputDialog::getItem(w, "Input item", "Item:", QStringList() << "Alpha" << "Beta" << "Gamma");
    });
    addButton(inputGrid, 1, 0, "Progress Dialog", [w] {
        auto *dlg = new QProgressDialog("Progress dialog", "Cancel", 0, 10, w);
        dlg->setAttribute(Qt::WA_DeleteOnClose);
        dlg->setWindowModality(Qt::WindowModal);
        dlg->setMinimumDuration(0);
        dlg->setAutoClose(false);
        dlg->setAutoReset(false);
        auto *timer = new QTimer(dlg);
        smokeConnect(timer, SIGNAL(timeout()), dlg, [dlg, timer] {
            const int next = dlg->value() + 1;
            dlg->setValue(next);
            if (next >= dlg->maximum()) {
                timer->stop();
                dlg->close();
            }
        });
        smokeConnect(dlg, SIGNAL(canceled()), dlg, [dlg, timer] {
            timer->stop();
            dlg->close();
        });
        timer->start(120);
        dlg->show();
    });
    addButton(inputGrid, 1, 1, "Error Message", [w] {
        auto *err = new QErrorMessage(w);
        err->setAttribute(Qt::WA_DeleteOnClose);
        err->showMessage("QErrorMessage popup");
    });
    addButton(inputGrid, 1, 2, "Wizard", [w] {
        auto *wizard = new QWizard(w);
        wizard->setAttribute(Qt::WA_DeleteOnClose);
        wizard->setWindowTitle("Wizard");
        auto *first = new QWizardPage;
        first->setTitle("First page");
        auto *firstLayout = new QVBoxLayout(first);
        firstLayout->addWidget(new QLabel("First wizard page"));
        auto *second = new QWizardPage;
        second->setTitle("Second page");
        auto *secondLayout = new QVBoxLayout(second);
        secondLayout->addWidget(new QLabel("Second wizard page"));
        wizard->addPage(first);
        wizard->addPage(second);
        wizard->show();
    });
    lay->addWidget(inputs);

    auto *popups = new QGroupBox("Popup widgets");
    auto *popupGrid = new QGridLayout(popups);
    addButton(popupGrid, 0, 0, "Context Menu", [w] {
        QMenu menu(w);
        menu.addAction("First action");
        menu.addAction("Checked action")->setCheckable(true);
        menu.addSeparator();
        menu.addAction("Disabled action")->setEnabled(false);
        menu.exec(QCursor::pos());
    });
    addButton(popupGrid, 0, 1, "Tooltip", [w] {
        QToolTip::showText(QCursor::pos(), "QToolTip popup", w);
    });
    addButton(popupGrid, 0, 2, "What's This", [w] {
        QWhatsThis::showText(QCursor::pos(), "QWhatsThis popup", w);
    });
    lay->addWidget(popups);

    lay->addStretch();
    return inScroll(w);
}

QWidget *makeWindowPopupLabTab()
{
    auto *w = new QWidget;
    auto *lay = new QVBoxLayout(w);

    auto *flags = new QGroupBox("Window flags");
    auto *grid = new QGridLayout(flags);
    gridButton(grid, 0, 0, "Qt::Popup", [w] {
        auto *popup = new QWidget(nullptr, Qt::Popup);
        popup->setAttribute(Qt::WA_DeleteOnClose);
        auto *v = new QVBoxLayout(popup);
        v->addWidget(new QLabel("Qt::Popup window"));
        v->addWidget(new QPushButton("Focusable button"));
        popup->move(QCursor::pos());
        popup->show();
    });
    gridButton(grid, 0, 1, "Qt::Tool", [w] {
        auto *tool = new QWidget(w, Qt::Tool);
        tool->setAttribute(Qt::WA_DeleteOnClose);
        tool->setWindowTitle("Qt::Tool");
        auto *v = new QVBoxLayout(tool);
        v->addWidget(new QLabel("Tool window"));
        v->addWidget(new QLineEdit("Tool line edit"));
        tool->resize(240, 110);
        tool->show();
    });
    gridButton(grid, 0, 2, "Frameless", [] {
        auto *frameless = new QWidget(nullptr, Qt::Window | Qt::FramelessWindowHint);
        frameless->setAttribute(Qt::WA_DeleteOnClose);
        auto *v = new QVBoxLayout(frameless);
        v->addWidget(new QLabel("Frameless window"));
        auto *close = new QPushButton("Close");
        v->addWidget(close);
        QObject::connect(close, SIGNAL(clicked()), frameless, SLOT(close()));
        frameless->resize(240, 110);
        frameless->move(QCursor::pos());
        frameless->show();
    });
    gridButton(grid, 1, 0, "Nested Menu", [w] {
        QMenu menu(w);
        menu.setTitle("Root menu");
        menu.addAction("Root action");
        auto *submenu = menu.addMenu("Submenu");
        submenu->addAction("Sub action 1");
        auto *nested = submenu->addMenu("Nested submenu");
        nested->addAction("Deep action");
        menu.addSeparator();
        menu.addAction("Checked")->setCheckable(true);
        menu.exec(QCursor::pos());
    });
    lay->addWidget(flags);

    auto *controls = new QGroupBox("Popup controls");
    auto *form = new QFormLayout(controls);
    auto *combo = new QComboBox;
    combo->addItems(QStringList() << "Combo popup one" << "Combo popup two" << "Combo popup three");
    form->addRow("Combo popup:", combo);
    auto *line = new QLineEdit;
    auto *model = new QStringListModel(QStringList() << "alpha" << "alpine" << "beta" << "gamma", line);
    auto *completer = new QCompleter(model, line);
    completer->setCaseSensitivity(Qt::CaseInsensitive);
    line->setCompleter(completer);
    line->setPlaceholderText("type 'a' for completer popup");
    form->addRow("Completer popup:", line);
    auto *dateEdit = new QDateEdit(QDate::currentDate());
    dateEdit->setCalendarPopup(true);
    form->addRow("Calendar popup:", dateEdit);
    auto *menuButton = new QToolButton;
    menuButton->setText("Menu button");
    menuButton->setPopupMode(QToolButton::InstantPopup);
    auto *buttonMenu = new QMenu(menuButton);
    buttonMenu->addAction("Menu item");
    buttonMenu->addAction("Another item");
    menuButton->setMenu(buttonMenu);
    form->addRow("Tool menu popup:", menuButton);
    lay->addWidget(controls);

    auto *fontBox = new QGroupBox("Popup font samples");
    auto *fontLayout = new QVBoxLayout(fontBox);
    fontLayout->addWidget(new QLabel(QString("QMenu font: %1 %2pt")
                                     .arg(QApplication::font("QMenu").family())
                                     .arg(QApplication::font("QMenu").pointSize())));
    fontLayout->addWidget(new QLabel(QString("QComboBox font: %1 %2pt")
                                     .arg(combo->font().family()).arg(combo->font().pointSize())));
    fontLayout->addWidget(new QLabel(QString("QToolTip font: %1 %2pt")
                                     .arg(QToolTip::font().family()).arg(QToolTip::font().pointSize())));
    lay->addWidget(fontBox);
    lay->addStretch();
    return inScroll(w);
}

QWidget *makeShapedWindowsTab()
{
    auto *w = new QWidget;
    auto *lay = new QVBoxLayout(w);

    auto *group = new QGroupBox("Shaped / layered windows");
    auto *grid = new QGridLayout(group);
    gridButton(grid, 0, 0, "setMask ellipse", [] {
        auto *window = new ShapedSmokeWindow("setMask shaped window", false);
        showWindowCentered(window);
    });
    gridButton(grid, 0, 1, "Translucent shaped", [] {
        auto *window = new ShapedSmokeWindow("WA_TranslucentBackground", true);
        showWindowCentered(window);
    });
    gridButton(grid, 0, 2, "Tool shaped", [] {
        auto *window = new ShapedSmokeWindow("Qt::Tool shaped window", true);
        window->setWindowFlags(Qt::Tool | Qt::FramelessWindowHint);
        showWindowCentered(window);
    });
    gridButton(grid, 1, 0, "Opacity 80%", [] {
        auto *window = new ShapedSmokeWindow("Layered opacity smoke", false);
        window->setWindowOpacity(0.80);
        showWindowCentered(window);
    });
    grid->addWidget(new QLabel("Right click every shaped window to test its context menu."), 2, 0, 1, 3);
    lay->addWidget(group);
    lay->addStretch();
    return inScroll(w);
}

QWidget *makeNativeDialogsTab()
{
    auto *w = new QWidget;
    auto *lay = new QVBoxLayout(w);

    auto *files = new QGroupBox("File dialogs");
    auto *fileGrid = new QGridLayout(files);
    gridButton(fileGrid, 0, 0, "Native open", [w] {
        QFileDialog::getOpenFileName(w, "Native open", QString(), "All files (*.*)");
    });
    gridButton(fileGrid, 0, 1, "Qt open", [w] {
        auto *dlg = new QFileDialog(w, "Qt open");
        dlg->setAttribute(Qt::WA_DeleteOnClose);
        dlg->setOption(QFileDialog::DontUseNativeDialog);
        dlg->setFileMode(QFileDialog::ExistingFile);
        dlg->show();
    });
    gridButton(fileGrid, 1, 0, "Native save", [w] {
        QFileDialog::getSaveFileName(w, "Native save", QString(), "Text (*.txt);;All files (*.*)");
    });
    gridButton(fileGrid, 1, 1, "Qt directory", [w] {
        auto *dlg = new QFileDialog(w, "Qt directory");
        dlg->setAttribute(Qt::WA_DeleteOnClose);
        dlg->setOption(QFileDialog::DontUseNativeDialog);
        dlg->setFileMode(QFileDialog::Directory);
        dlg->show();
    });
    lay->addWidget(files);

    auto *colorsFonts = new QGroupBox("Color / font dialogs");
    auto *cfGrid = new QGridLayout(colorsFonts);
    gridButton(cfGrid, 0, 0, "Native color", [w] {
        QColorDialog::getColor(Qt::blue, w, "Native color");
    });
    gridButton(cfGrid, 0, 1, "Qt color", [w] {
        auto *dlg = new QColorDialog(Qt::blue, w);
        dlg->setAttribute(Qt::WA_DeleteOnClose);
        dlg->setOption(QColorDialog::DontUseNativeDialog);
        dlg->show();
    });
    gridButton(cfGrid, 1, 0, "Native font", [w] {
        bool ok = false;
        QFontDialog::getFont(&ok, QApplication::font(), w, "Native font");
    });
    gridButton(cfGrid, 1, 1, "Qt font", [w] {
        auto *dlg = new QFontDialog(QApplication::font(), w);
        dlg->setAttribute(Qt::WA_DeleteOnClose);
        dlg->setOption(QFontDialog::DontUseNativeDialog);
        dlg->show();
    });
    lay->addWidget(colorsFonts);

    auto *other = new QGroupBox("Print / input / message");
    auto *otherGrid = new QGridLayout(other);
#if !defined(QT_NO_PRINTER) && !defined(QT_NO_PRINTDIALOG)
    gridButton(otherGrid, 0, 0, "Page setup", [w] {
        auto *printer = new QPrinter;
        auto *dlg = new QPageSetupDialog(printer, w);
        dlg->setAttribute(Qt::WA_DeleteOnClose);
        smokeConnectInt(dlg, SIGNAL(finished(int)), dlg, [printer](int) { delete printer; });
        dlg->show();
    });
    gridButton(otherGrid, 0, 1, "Print dialog", [w] {
        auto *printer = new QPrinter;
        auto *dlg = new QPrintDialog(printer, w);
        dlg->setAttribute(Qt::WA_DeleteOnClose);
        smokeConnectInt(dlg, SIGNAL(finished(int)), dlg, [printer](int) { delete printer; });
        dlg->show();
    });
#else
    otherGrid->addWidget(new QLabel("Printing unavailable in this Qt build"), 0, 0, 1, 2);
#endif
    gridButton(otherGrid, 0, 2, "Input text", [w] {
        QInputDialog::getText(w, "Input dialog", "Text:");
    });
    gridButton(otherGrid, 1, 0, "Message buttons", [w] {
        QMessageBox box(QMessageBox::Question, "Buttons",
                        "Message box button/font/layout smoke",
                        QMessageBox::Yes | QMessageBox::No | QMessageBox::Cancel, w);
        box.setDefaultButton(QMessageBox::No);
        box.exec();
    });
    gridButton(otherGrid, 1, 1, "Error message", [w] {
        auto *err = new QErrorMessage(w);
        err->setAttribute(Qt::WA_DeleteOnClose);
        err->showMessage("Native-vs-Qt dialog lab error message");
    });
    lay->addWidget(other);
    lay->addStretch();
    return inScroll(w);
}

QWidget *makeFontsDpiTab()
{
    auto *w = new QWidget;
    auto *lay = new QVBoxLayout(w);

    auto *table = new QTableWidget(0, 6);
    table->setHorizontalHeaderLabels(QStringList() << "Role" << "Family" << "Point" << "Pixel"
                                                   << "Height" << "Avg width");
    auto addFontRow = [table](const QString &role, const QFont &font) {
        const int row = table->rowCount();
        table->insertRow(row);
        QFontMetrics metrics(font);
        const QStringList values = QStringList()
            << role
            << font.family()
            << QString::number(font.pointSize())
            << QString::number(font.pixelSize())
            << QString::number(metrics.height())
            << QString::number(metrics.averageCharWidth());
        for (int column = 0; column < values.size(); ++column)
            table->setItem(row, column, new QTableWidgetItem(values.at(column)));
    };
    addFontRow("QApplication", QApplication::font());
#if SMOKE_QT5
    addFontRow("QGuiApplication", QGuiApplication::font());
#endif
    addFontRow("QMenu", QApplication::font("QMenu"));
    addFontRow("QMessageBox", QApplication::font("QMessageBox"));
    addFontRow("QStatusBar", QApplication::font("QStatusBar"));
    addFontRow("QToolTip", QToolTip::font());
#if SMOKE_QT5
    addFontRow("System general", QFontDatabase::systemFont(QFontDatabase::GeneralFont));
    addFontRow("System fixed", QFontDatabase::systemFont(QFontDatabase::FixedFont));
    addFontRow("System title", QFontDatabase::systemFont(QFontDatabase::TitleFont));
#endif
    table->horizontalHeader()->setStretchLastSection(true);
    lay->addWidget(table);

    auto *info = new QGroupBox("Runtime metrics");
    auto *form = new QFormLayout(info);
    form->addRow("Style:", new QLabel(QApplication::style()->objectName()));
    form->addRow("Available styles:", new QLabel(QStyleFactory::keys().join(", ")));
#if SMOKE_QT5
    if (QScreen *screen = QGuiApplication::primaryScreen()) {
        form->addRow("Logical DPI:", new QLabel(QString::number(screen->logicalDotsPerInch(), 'f', 1)));
        form->addRow("Physical DPI:", new QLabel(QString::number(screen->physicalDotsPerInch(), 'f', 1)));
        form->addRow("Device pixel ratio:", new QLabel(QString::number(screen->devicePixelRatio(), 'f', 2)));
    }
#else
    // Qt 4 reports the same numbers through the desktop widget, and has no
    // notion of a device pixel ratio - that arrived with Qt 5's high-DPI work.
    if (QWidget *desktop = QApplication::desktop()) {
        form->addRow("Logical DPI:", new QLabel(QString::number(desktop->logicalDpiX())));
        form->addRow("Physical DPI:", new QLabel(QString::number(desktop->physicalDpiX())));
    }
#endif
    lay->addWidget(info);

    auto *samples = new QGroupBox("Visual samples");
    auto *sampleLayout = new QHBoxLayout(samples);
    sampleLayout->addWidget(new QPushButton("Button text"));
    auto *combo = new QComboBox;
    combo->addItems(QStringList() << "Combo popup" << "Second item" << "Third item");
    sampleLayout->addWidget(combo);
    auto *tool = new QToolButton;
    tool->setText("Menu");
    tool->setPopupMode(QToolButton::InstantPopup);
    auto *menu = new QMenu(tool);
    menu->addAction("Menu font sample");
    menu->addAction("Second menu item");
    tool->setMenu(menu);
    sampleLayout->addWidget(tool);
    auto *message = new QPushButton("Message box");
    smokeConnect(message, SIGNAL(clicked()), w, [w] {
        QMessageBox::information(w, "Font sample", "Message box font sample");
    });
    sampleLayout->addWidget(message);
    lay->addWidget(samples);
    return w;
}

QWidget *makeModelViewStressTab()
{
    auto *w = new QWidget;
    auto *lay = new QVBoxLayout(w);
    auto *filter = new QLineEdit;
    filter->setPlaceholderText("Filter rows");
    lay->addWidget(filter);

    auto *splitter = new QSplitter(Qt::Horizontal);
    auto *source = new QStandardItemModel(w);
    source->setHorizontalHeaderLabels(QStringList() << "Name" << "State" << "Value");
    QIcon folderIcon = QApplication::style()->standardIcon(QStyle::SP_DirIcon);
    QIcon fileIcon = QApplication::style()->standardIcon(QStyle::SP_FileIcon);
    for (int row = 0; row < 320; ++row) {
        QList<QStandardItem *> items;
        auto *name = new QStandardItem(row % 10 == 0 ? folderIcon : fileIcon,
                                       QString("Item %1").arg(row, 3, 10, QLatin1Char('0')));
        name->setCheckable(true);
        name->setCheckState(row % 3 == 0 ? Qt::Checked : Qt::Unchecked);
        items << name
              << new QStandardItem(row % 2 ? "Enabled" : "Disabled")
              << new QStandardItem(QString::number(row * 17));
        source->appendRow(items);
        if (row % 20 == 0) {
            for (int child = 0; child < 5; ++child)
                name->appendRow(QList<QStandardItem *>()
                                << new QStandardItem(fileIcon, QString("Child %1").arg(child))
                                << new QStandardItem("Nested")
                                << new QStandardItem(QString::number(child)));
        }
    }

    auto *proxy = new QSortFilterProxyModel(w);
    proxy->setSourceModel(source);
    proxy->setFilterCaseSensitivity(Qt::CaseInsensitive);
    proxy->setFilterKeyColumn(-1);
    QObject::connect(filter, SIGNAL(textChanged(QString)), proxy, SLOT(setFilterFixedString(QString)));

    auto *table = new QTableView;
    table->setModel(proxy);
    table->setSortingEnabled(true);
    table->setAlternatingRowColors(true);
    table->setItemDelegate(new QStyledItemDelegate(table));
    table->horizontalHeader()->setStretchLastSection(true);
    table->setEditTriggers(QAbstractItemView::DoubleClicked | QAbstractItemView::EditKeyPressed);
    splitter->addWidget(table);

    auto *tree = new QTreeView;
    tree->setModel(source);
    tree->setAlternatingRowColors(true);
    tree->setSortingEnabled(true);
    tree->setItemDelegate(new QStyledItemDelegate(tree));
    tree->expandToDepth(0);
    splitter->addWidget(tree);
    lay->addWidget(splitter);

    auto *buttons = new QHBoxLayout;
    auto *sortButton = new QPushButton("Sort by value");
    smokeConnect(sortButton, SIGNAL(clicked()), table, [table] { table->sortByColumn(2, Qt::DescendingOrder); });
    buttons->addWidget(sortButton);
    auto *editButton = new QPushButton("Edit current");
    smokeConnect(editButton, SIGNAL(clicked()), table, [table] { table->edit(table->currentIndex()); });
    buttons->addWidget(editButton);
    buttons->addStretch();
    lay->addLayout(buttons);
    return w;
}

QWidget *makeClipboardDragDropTab()
{
    auto *w = new QWidget;
    auto *lay = new QVBoxLayout(w);

    auto *edit = new QTextEdit;
    edit->setHtml("<b>Clipboard HTML</b><br/>Plain text fallback");
    lay->addWidget(edit);

    auto *buttons = new QHBoxLayout;
    auto *copyText = new QPushButton("Copy text");
    smokeConnect(copyText, SIGNAL(clicked()), w, [edit] {
        QApplication::clipboard()->setText(edit->toPlainText());
    });
    buttons->addWidget(copyText);
    auto *copyHtml = new QPushButton("Copy HTML");
    smokeConnect(copyHtml, SIGNAL(clicked()), w, [edit] {
        auto *mime = new QMimeData;
        mime->setText(edit->toPlainText());
        mime->setHtml(edit->toHtml());
        QApplication::clipboard()->setMimeData(mime);
    });
    buttons->addWidget(copyHtml);
    auto *copyImage = new QPushButton("Copy image");
    smokeConnect(copyImage, SIGNAL(clicked()), w, [] {
        QImage image(96, 48, QImage::Format_ARGB32_Premultiplied);
        image.fill(QColor(40, 120, 180));
        QPainter painter(&image);
        painter.setPen(Qt::white);
        painter.drawText(image.rect(), Qt::AlignCenter, "Qt");
        QApplication::clipboard()->setImage(image);
    });
    buttons->addWidget(copyImage);
    auto *paste = new QPushButton("Paste summary");
    buttons->addWidget(paste);
    buttons->addStretch();
    lay->addLayout(buttons);

    auto *summary = new QLabel;
    summary->setFrameStyle(QFrame::StyledPanel | QFrame::Sunken);
    summary->setMinimumHeight(60);
    smokeConnect(paste, SIGNAL(clicked()), w, [summary] {
        const QMimeData *mime = QApplication::clipboard()->mimeData();
        QStringList parts;
        if (mime->hasText())
            parts << "text";
        if (mime->hasHtml())
            parts << "html";
        if (mime->hasImage())
            parts << "image";
        if (mime->hasUrls())
            parts << "urls";
        summary->setText("Clipboard formats: " + parts.join(", ") + "\n" + mime->text().left(160));
    });
    lay->addWidget(summary);

    auto *dragDropBox = new QGroupBox("Drag and drop");
    auto *dragDropLayout = new QHBoxLayout(dragDropBox);

    auto *sources = new QWidget;
    auto *sourcesLayout = new QVBoxLayout(sources);
    sourcesLayout->setContentsMargins(0, 0, 0, 0);
    sourcesLayout->addWidget(new DragTextItem("First draggable text"));
    sourcesLayout->addWidget(new DragTextItem("Second draggable text"));
    sourcesLayout->addWidget(new DragTextItem("Third draggable text"));
    sourcesLayout->addStretch();

    dragDropLayout->addWidget(sources, 1);
    dragDropLayout->addWidget(new DropArea, 2);
    lay->addWidget(dragDropBox);
    return w;
}

QWidget *makeWinExtrasTaskbarTab()
{
    auto *w = new QWidget;
    auto *lay = new QVBoxLayout(w);

#if defined(Q_OS_WIN) && defined(SMOKE_HAVE_WINEXTRAS)
    const bool enabled = isWindows7OrNewer();
    auto *state = new QLabel(enabled ? "WinExtras runtime enabled" : "WinExtras disabled on XP");
    state->setWordWrap(true);
    lay->addWidget(state);

    auto *grid = new QGridLayout;
    auto *taskbarButton = gridButton(grid, 0, 0, "Taskbar progress 60%", [w, state] {
        auto *button = new QWinTaskbarButton(w);
        if (!w->window()->windowHandle())
            w->window()->winId();
        button->setWindow(w->window()->windowHandle());
        button->progress()->setRange(0, 100);
        button->progress()->setValue(60);
        button->progress()->show();
        state->setText("Taskbar progress set to 60%. The effect is visible on the Windows taskbar button.");
    });
    auto *thumbnailButton = gridButton(grid, 0, 1, "Thumbnail toolbar", [w, state] {
        auto *bar = new QWinThumbnailToolBar(w);
        if (!w->window()->windowHandle())
            w->window()->winId();
        bar->setWindow(w->window()->windowHandle());
        auto *button = new QWinThumbnailToolButton(bar);
        button->setToolTip("Thumbnail button");
        button->setIcon(QApplication::style()->standardIcon(QStyle::SP_MediaPlay));
        bar->addButton(button);
        state->setText("Thumbnail toolbar button installed. Hover the taskbar preview to see it on supported Windows versions.");
    });
    auto *jumpButton = gridButton(grid, 0, 2, "Jump list", [w, state] {
        auto *list = new QWinJumpList(w);
        list->recent()->setVisible(true);
        list->frequent()->setVisible(true);
        auto *tasks = list->tasks();
        tasks->addLink(QApplication::style()->standardIcon(QStyle::SP_ComputerIcon),
                       "Widgets Gallery", QCoreApplication::applicationFilePath());
        state->setText("Jump list task installed. Right-click the taskbar button to inspect it on supported Windows versions.");
    });
    taskbarButton->setEnabled(enabled);
    thumbnailButton->setEnabled(enabled);
    jumpButton->setEnabled(enabled);
    if (!enabled)
        state->setText("WinExtras shell integration requires Windows 7 or newer; these buttons are disabled on XP.");
    lay->addLayout(grid);
#elif defined(Q_OS_WIN)
#if QT_VERSION_MAJOR < 5
    lay->addWidget(new QLabel("QtWinExtras arrived in Qt 5. This Qt 4 build "
                              "uses the platform facilities available through "
                              "QtGui and native Windows APIs instead."));
#else
    lay->addWidget(new QLabel("QtWinExtras is not part of Qt 6, so this tab has "
                              "nothing to show in a Qt 6 build."));
#endif
#else
    lay->addWidget(new QLabel("WinExtras are Windows-only."));
#endif

    lay->addStretch();
    return inScroll(w);
}

QWidget *buildGallery()
{
    auto *tabs = new TwoRowTabWidget;
    tabs->addPage(makeButtonsTab(),   "Buttons", 0);
    tabs->addPage(makeInputsTab(),    "Inputs", 0);
    tabs->addPage(makeRangesTab(),    "Ranges", 0);
    tabs->addPage(makeItemViewsTab(), "Item Views", 0);
    tabs->addPage(makeContainersTab(),"Containers", 0);
    tabs->addPage(makeTextTab(),      "Text", 0);
    tabs->addPage(makeGraphicsTab(),  "Graphics", 0);
    tabs->addPage(makePopupsTab(),    "Popups", 0);
    tabs->addPage(makeWindowPopupLabTab(), "Window/Popup Lab", 1);
    tabs->addPage(makeShapedWindowsTab(), "Shaped Windows", 1);
    tabs->addPage(makeNativeDialogsTab(), "Native/Qt Dialogs", 1);
    tabs->addPage(makeFontsDpiTab(), "Fonts/DPI", 1);
    tabs->addPage(makeModelViewStressTab(), "Model Stress", 1);
    tabs->addPage(makeClipboardDragDropTab(), "Clipboard/DnD", 1);
    tabs->addPage(makeWinExtrasTaskbarTab(), "WinExtras", 1);
    tabs->selectPage(0);
    return tabs;
}

void checkGalleryRendering(SmokeReporter &r)
{
    std::unique_ptr<TwoRowTabWidget> gallery(static_cast<TwoRowTabWidget *>(buildGallery()));
    gallery->resize(760, 560);
    gallery->show();
    const int rows = (gallery->pageCount() + 3) / 4;
    QImage sheet(1600, rows * 320, QImage::Format_RGB32);
#if defined(Q_OS_WIN) && defined(QT_WIN95_SUPPORT)
    std::printf("Gallery contact sheet: width=%d height=%d stride=%d bytes=%d format=%d null=%d\n",
                sheet.width(), sheet.height(), sheet.bytesPerLine(), sheet.byteCount(),
                int(sheet.format()), sheet.isNull());
    std::fflush(stdout);
    if (!sheet.isNull()) {
        unsigned char *buffer = sheet.bits();
        std::printf("Gallery contact sheet: data=%p CRT-size=%lu end=%p\n", buffer,
                    static_cast<unsigned long>(_msize(buffer)), buffer + sheet.byteCount());
        MEMORY_BASIC_INFORMATION info;
        for (unsigned char *page = buffer; page < buffer + sheet.byteCount();) {
            if (!VirtualQuery(page, &info, sizeof(info)) || !info.RegionSize
                    || static_cast<unsigned char *>(info.BaseAddress) + info.RegionSize <= page)
                break;
            std::printf("Gallery allocation: base=%p bytes=%lu state=%08lX protect=%08lX\n",
                        info.BaseAddress, static_cast<unsigned long>(info.RegionSize),
                        static_cast<unsigned long>(info.State), static_cast<unsigned long>(info.Protect));
            page = static_cast<unsigned char *>(info.BaseAddress) + info.RegionSize;
        }
        std::fflush(stdout);
    }
#endif
    sheet.fill(Qt::white);
    for (int page = 0; page < gallery->pageCount(); ++page) {
        r.check(QStringLiteral("gallery/render/") + gallery->pageName(page), [&](QString &d) {
            gallery->selectPage(page);
            QApplication::processEvents();
            QImage frame(gallery->size(), QImage::Format_RGB32);
            frame.fill(Qt::magenta);
            // Render directly to a raster image; native grabWidget previously
            // crashed old Win95 display drivers in another gallery.
            gallery->render(&frame);
            QPainter painter(&sheet);
            const int x = (page % 4) * 400, y = (page / 4) * 320;
            painter.drawText(QRect(x + 4, y, 392, 24), Qt::AlignCenter, gallery->pageName(page));
            painter.drawImage(QRect(x, y + 24, 400, 296), frame);
            d = QString::fromLatin1("page %1").arg(page + 1);
            return !frame.isNull() && frame.pixel(frame.width() / 2, frame.height() / 2)
                    != qRgb(255, 0, 255);
        });
    }
    r.check("gallery/save-contact-sheet", [&](QString &d) {
        d = QDir(QCoreApplication::applicationDirPath()).filePath(QStringLiteral("widgets-gallery-pages.png"));
        return sheet.save(d);
    });
}

#include "gallery.moc"   // SmokeFunctorSlot's Q_OBJECT lives in this .cpp
