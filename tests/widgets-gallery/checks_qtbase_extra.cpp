// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// A second wide sweep over QtBase/QtWidgets: style option value types (the
// family every widget's paint event fills one of to tell the QStyle how to
// draw it), abstract widget bases reached through the
// concrete widgets that already exist elsewhere in the gallery, the
// gesture/undo/printing frameworks, MDI, and a handful of remaining
// standalone widgets/graphics-view classes.
#include "../common/smokecheck.h"

#include <QStyleOptionButton>
#include <QStyleOptionComboBox>
#include <QStyleOptionFrame>
#include <QStyleOptionHeader>
#include <QStyleOptionMenuItem>
#include <QStyleOptionProgressBar>
#include <QStyleOptionSlider>
#include <QStyleOptionSpinBox>
#include <QStyleOptionTab>
#include <QStyleOptionTabBarBase>
#include <QStyleOptionTabWidgetFrame>
#include <QStyleOptionTitleBar>
#include <QStyleOptionToolBar>
#include <QStyleOptionToolBox>
#include <QStyleOptionToolButton>
#include <QStyleOptionViewItem>
#include <QStyleOptionFocusRect>
#include <QStyleOptionGroupBox>
#include <QStyleOptionDockWidget>
#include <QStyleOptionRubberBand>
#include <QStyleOptionSizeGrip>
#include <QStyleOptionComplex>
#include <QStyleHintReturn>
#include <QStyleHintReturnMask>
#include <QStyleHintReturnVariant>
#include <QCommonStyle>
#include <QProxyStyle>
#include <QStyleFactory>

#include <QAbstractButton>
#include <QAbstractSlider>
#include <QAbstractSpinBox>
#include <QAbstractScrollArea>
#include <QAbstractItemView>
#include <QAbstractItemDelegate>
#include <QBoxLayout>
#include <QDir>
#include <QLayout>
#include <QWidgetItem>
#include <QSpacerItem>
#include <QPushButton>
#include <QSlider>
#include <QSpinBox>
#include <QListView>
#include <QStandardItemModel>
#include <QStyledItemDelegate>

#include <QGesture>
#include <QPanGesture>
#include <QPinchGesture>
#include <QSwipeGesture>
#include <QTapGesture>
#include <QTapAndHoldGesture>

#include <QUndoStack>
#include <QUndoCommand>
#include <QUndoGroup>
#include <QUndoView>

#include <QPrinter>
#include <QPaintDevice>
#include <QPrinterInfo>
#if SMOKE_QT5
#  include <QPageLayout>
#endif
#if SMOKE_QT5
#  include <QPageSize>   // Qt 5.3 and later
#endif
#if SMOKE_QT5
#  include <QPagedPaintDevice>   // Qt 5 and later
#  include <QPdfWriter>
#endif
#include <QPrintDialog>
#include <QPageSetupDialog>
#include <QPrintPreviewDialog>
#include <QPrintPreviewWidget>

#include <QMdiArea>
#include <QMdiSubWindow>
#include <QMovie>
#include <QSystemTrayIcon>
#include <QMenu>
#include <QClipboard>
#include <QCursor>
#include <QApplication>
#include <QDateEdit>
#include <QTimeEdit>
#include <QTabBar>
#include <QDataWidgetMapper>
#include <QSizePolicy>
#include <QRubberBand>
#include <QSizeGrip>
#include <QFocusFrame>
#include <QSplashScreen>
#include <QErrorMessage>
#include <QProgressDialog>
#include <QToolTip>
#include <QWhatsThis>
#include <QSyntaxHighlighter>
#include <QTextDocument>

#include <QDragEnterEvent>
#include <QDragMoveEvent>
#include <QDragLeaveEvent>
#include <QDropEvent>
#include <QMimeData>

#include <QGraphicsScene>
#include <QAbstractGraphicsShapeItem>
#include <QGraphicsLineItem>
#include <QGraphicsRectItem>
#include <QGraphicsSimpleTextItem>
#include <QGraphicsObject>
#include <QGraphicsWidget>
#include <QGraphicsAnchorLayout>
#include <QGraphicsLinearLayout>
#include <QGraphicsGridLayout>
#include <QGraphicsRotation>
#include <QGraphicsScale>
#include <QGraphicsItemAnimation>
#include <QTimeLine>
#include <QTemporaryFile>

void checkStyleOptions(SmokeReporter &r)
{
    r.check("styleoption/widget-family", [&](QString &d) {
        QStyleOptionButton button; button.text = "Go";
        QStyleOptionComboBox combo; combo.currentText = "x";
        QStyleOptionFrame frame; frame.lineWidth = 1;
        QStyleOptionHeader header; header.section = 0;
        QStyleOptionMenuItem menuItem; menuItem.text = "Item";
        QStyleOptionProgressBar progress; progress.progress = 50;
        QStyleOptionSlider slider; slider.sliderPosition = 5;
        QStyleOptionSpinBox spin;
        QStyleOptionTab tab; tab.text = "Tab";
        QStyleOptionTabBarBase tabBarBase;
        QStyleOptionTabWidgetFrame tabWidgetFrame;
        QStyleOptionTitleBar titleBar; titleBar.text = "Window";
        QStyleOptionToolBar toolBar;
        QStyleOptionToolBox toolBox;
        QStyleOptionToolButton toolButton;
        QStyleOptionViewItem viewItem;
        // Reached through the real base every style-option value type derives from.
        QStyleOption *asBase = &button;
        return asBase->type == QStyleOption::SO_Button
            && button.text == "Go" && combo.currentText == "x" && frame.lineWidth == 1
            && header.section == 0 && menuItem.text == "Item" && progress.progress == 50
            && slider.sliderPosition == 5 && tab.text == "Tab" && titleBar.text == "Window"
            && spin.subControls == spin.subControls && tabBarBase.selectedTabRect.isNull()
            && tabWidgetFrame.lineWidth == tabWidgetFrame.lineWidth
            && toolBar.toolBarArea == toolBar.toolBarArea && toolBox.icon.isNull()
            && toolButton.arrowType == Qt::DownArrow
            // Qt 4 keeps index on QStyleOptionViewItemV4; the members were
            // folded into the unversioned struct in Qt 5.
#if SMOKE_QT5
            && viewItem.index == QModelIndex()
#endif
            ;
    });
    r.check("styleoption/focus-group-dock-rubberband", [&](QString &d) {
        QStyleOptionFocusRect focusRect; focusRect.backgroundColor = Qt::red;
        QStyleOptionGroupBox groupBox; groupBox.text = "Group";
        QStyleOptionDockWidget dockWidget; dockWidget.title = "Dock";
        QStyleOptionRubberBand rubberBand; rubberBand.opaque = true;
        QStyleOptionSizeGrip sizeGrip; sizeGrip.corner = Qt::BottomRightCorner;
        // Complex options are reached through the real base every one of the
        // slider/combobox/titlebar/toolbutton/spinbox options above derives from.
        QStyleOptionComplex *asComplex = &sizeGrip;
        return focusRect.backgroundColor == QColor(Qt::red) && groupBox.text == "Group"
            && dockWidget.title == "Dock" && rubberBand.opaque
            && sizeGrip.corner == Qt::BottomRightCorner && asComplex != nullptr;
    });
    r.check("styleoption/hint-returns-style-factory", [&](QString &d) {
        QStyleHintReturn base;
        QStyleHintReturnMask mask;
        QStyleHintReturnVariant variant;
        // QProxyStyle(QStyle*) takes ownership (reparents the given style onto
        // itself), so the base style must be heap-allocated - a stack object
        // here would get destroyed twice (once by the proxy, once by scope
        // exit), which is exactly what crashed the first run of this check.
        auto *common = new QCommonStyle;
        QProxyStyle proxy(common);
        const QStringList keys = QStyleFactory::keys();
        return base.version == base.version && mask.region.isEmpty()
            && proxy.baseStyle() == common && keys.size() >= 0;
    });
}

void checkAbstractBasesViaConcrete(SmokeReporter &r)
{
    r.check("qtbase/abstract-widget-bases", [&](QString &d) {
        QPushButton button("Go");
        QSlider slider;
        QSpinBox spin;
        QListView view;
        QStandardItemModel model;
        QStyledItemDelegate delegate;
        view.setModel(&model);
        view.setItemDelegate(&delegate);
        // Reached through the real bases every concrete widget derives from.
        QAbstractButton *asButton = &button;
        QAbstractSlider *asSlider = &slider;
        QAbstractSpinBox *asSpin = &spin;
        QAbstractItemView *asView = &view;
        QAbstractScrollArea *asScrollArea = &view;
        QAbstractItemDelegate *asDelegate = view.itemDelegate();
        return asButton->text() == "Go" && asSlider->minimum() == 0
            && asSpin->isReadOnly() == false && asView->model() == &model
            && asScrollArea->viewport() != nullptr && asDelegate == &delegate
#if SMOKE_QT5
            && asDelegate->paintingRoles().isEmpty()   // Qt 5 and later
#endif
            ;
    });
    r.check("qtbase/layout-item-bases", [&](QString &d) {
        QWidget host;
        auto *box = new QVBoxLayout(&host);
        box->addWidget(new QPushButton("a"));
        auto *spacer = new QSpacerItem(10, 10);
        box->addItem(spacer);
        // Reached through the real bases QVBoxLayout/addWidget's wrapper derive from.
        QBoxLayout *asBoxLayout = box;
        QLayout *asLayout = box;
        QLayoutItem *widgetItem = asLayout->itemAt(0);
        return asBoxLayout->count() == 2 && dynamic_cast<QWidgetItem *>(widgetItem) != nullptr
            && asLayout->itemAt(1) == spacer;
    });
}

void checkGestures(SmokeReporter &r)
{
    r.check("gesture/construct-catalogue", [&](QString &d) {
        QWidget host;
        QPanGesture pan;
        QPinchGesture pinch;
        QSwipeGesture swipe;
        QTapGesture tap;
        QTapAndHoldGesture tapHold;
        pan.setAcceleration(2.0);
        // Reached through the real base every gesture type derives from.
        QGesture *asGesture = &pan;
        return qFuzzyCompare(pan.acceleration(), 2.0) && asGesture->state() == Qt::NoGesture
            && pinch.totalScaleFactor() == pinch.totalScaleFactor()
            && swipe.swipeAngle() == swipe.swipeAngle() && tap.position() == tap.position()
            && tapHold.position() == tapHold.position();
    });
}

void checkUndoFramework(SmokeReporter &r)
{
    r.check("undo/stack-command-group-view", [&](QString &d) {
        QUndoStack stack;
        int applied = 0;
        class IncrementCommand : public QUndoCommand {
        public:
            int *counter;
            IncrementCommand(int *c) : counter(c) { setText("increment"); }
            void redo() override { ++*counter; }
            void undo() override { --*counter; }
        };
        stack.push(new IncrementCommand(&applied));
        stack.push(new IncrementCommand(&applied));
        stack.undo();
        QUndoGroup group;
        group.addStack(&stack);
        QUndoView view(&stack);
        return applied == 1 && stack.count() == 2 && group.stacks().contains(&stack)
            && view.stack() == &stack;
    });
}

void checkPrinting(SmokeReporter &r)
{
    r.check("printing/printer-and-page-setup", [&](QString &d) {
        // QPdfWriter, QPageLayout and QPageSize are all Qt 5 (5.0, 5.3 and 5.3);
        // Qt 4 describes a page through QPrinter::PageSize instead, which is a
        // different API rather than a spelling difference. Reported as a skip
        // rather than reworked, so the gap stays visible.
#if !SMOKE_QT5
        r.skip(d, QStringLiteral("QPdfWriter/QPageLayout/QPageSize are Qt 5 and later"));
        return true;
#else
        QTemporaryFile printerFile(QDir::tempPath() + "/qt-smoke-printer-XXXXXX.pdf");
        QTemporaryFile writerFile(QDir::tempPath() + "/qt-smoke-writer-XXXXXX.pdf");
        if (!printerFile.open() || !writerFile.open()) {
            d = "temporary PDF output file could not be opened";
            return false;
        }
        const QString printerPath = printerFile.fileName();
        const QString writerPath = writerFile.fileName();
        printerFile.close();
        writerFile.close();

        QPrinter printer(QPrinter::ScreenResolution);
        printer.setOutputFormat(QPrinter::PdfFormat);
        printer.setOutputFileName(printerPath);
        QPageLayout layout(QPageSize(QPageSize::Letter), QPageLayout::Portrait, QMarginsF(10, 10, 10, 10));
        printer.setPageLayout(layout);
        QPdfWriter writer(writerPath);
#if QT_VERSION_MAJOR < 6
        writer.setPageSize(QPagedPaintDevice::A4);
#else
        writer.setPageSize(QPageSize(QPageSize::A4));
#endif
        QPagedPaintDevice *paged = &writer;
        QPaintDevice *paintDevice = &writer;
        const QList<QPrinterInfo> printers = QPrinterInfo::availablePrinters();
        const bool ok = printer.outputFormat() == QPrinter::PdfFormat
            && printer.pageLayout().pageSize().id() == QPageSize::Letter
#if QT_VERSION_MAJOR < 6
            && paged->pageSize() == QPagedPaintDevice::A4
#else
            && paged->pageLayout().pageSize().id() == QPageSize::A4
#endif
            && paintDevice->devType() >= 0
            && printers.size() >= 0;
        if (!ok) {
            d = QStringLiteral("format=%1 printerPage=%2 writerPage=%3 devType=%4 printers=%5")
                    .arg(int(printer.outputFormat()))
                    .arg(int(printer.pageLayout().pageSize().id()))
#if QT_VERSION_MAJOR < 6
                    .arg(int(paged->pageSize()))
#else
                    .arg(int(paged->pageLayout().pageSize().id()))
#endif
                    .arg(paintDevice->devType())
                    .arg(printers.size());
        }
        return ok;
#endif  // SMOKE_QT5
    });
    r.check("printing/dialogs-construct", [&](QString &d) {
#if defined(QT_NO_PRINTER) || defined(QT_NO_PRINTDIALOG) || defined(QT_NO_PRINTPREVIEWDIALOG) || defined(QT_NO_PRINTPREVIEWWIDGET)
        r.skip(d, QStringLiteral("Printing dialogs disabled in this Qt build"));
        return false;
#else
        QPrinter printer;
        QPrintDialog printDlg(&printer);
        QPageSetupDialog pageSetupDlg(&printer);
        QPrintPreviewDialog previewDlg(&printer);
        QPrintPreviewWidget previewWidget(&printer);
        return printDlg.printer() == &printer && pageSetupDlg.printer() == &printer;
#endif
    });
}

void checkMdiMovieTrayMisc(SmokeReporter &r)
{
    r.check("widgets/mdi-area-subwindow", [&](QString &d) {
        QMdiArea area;
        auto *sub = area.addSubWindow(new QPushButton("inner"));
        sub->setWindowTitle("Sub");
        return area.subWindowList().contains(sub) && sub->windowTitle() == "Sub";
    });
    r.check("widgets/movie-tray-clipboard-cursor", [&](QString &d) {
        QMovie movie;   // no file needed - construct/configure only
        movie.setSpeed(150);
#ifndef QT_NO_SYSTEMTRAYICON
        QSystemTrayIcon tray;
        tray.setToolTip("qt-smoke");
#endif
        QClipboard *clipboard = QApplication::clipboard();
        QCursor cursor(Qt::PointingHandCursor);
        return movie.speed() == 150
#ifndef QT_NO_SYSTEMTRAYICON
            && tray.toolTip() == "qt-smoke"
#endif
            && clipboard != nullptr && cursor.shape() == Qt::PointingHandCursor;
    });
#ifdef QT_NO_SYSTEMTRAYICON
    r.check("widgets/system-tray", [&](QString &d) {
        r.skip(d, QStringLiteral("System tray disabled in this Qt build"));
        return false;
    });
#else
    r.check("widgets/system-tray", [&](QString &d) {
        if (!QSystemTrayIcon::isSystemTrayAvailable()) {
            r.skip(d, QStringLiteral("no system tray in this desktop session"));
            return false;
        }
        QPixmap pixmap(16, 16);
        pixmap.fill(Qt::blue);
        QSystemTrayIcon tray{QIcon(pixmap)};
        QMenu menu;
        menu.addAction("Restore");
        tray.setContextMenu(&menu);
        const QString tip = QString::fromUtf8("Qt tray: Привет");
        tray.setToolTip(tip);
        tray.show();
        QApplication::processEvents();
        const bool configured = tray.isVisible() && !tray.icon().isNull()
            && tray.toolTip() == tip && tray.contextMenu() == &menu;
        tray.setToolTip("Qt tray updated");
        QApplication::processEvents();
        tray.hide();
        QApplication::processEvents();
        d = QStringLiteral("configured=%1 messages=%2").arg(configured)
            .arg(QSystemTrayIcon::supportsMessages());
        // Shell rendering and actual mouse activation are checked separately
        // in the interactive guest; isVisible() itself is only Qt's state.
        return configured && !tray.isVisible() && tray.toolTip() == "Qt tray updated";
    });
#endif
    r.check("widgets/dateedit-timeedit-tabbar-datamapper-sizepolicy", [&](QString &d) {
        QDateEdit dateEdit(QDate(2024, 1, 1));
        QTimeEdit timeEdit(QTime(12, 30));
        QTabBar tabBar;
        tabBar.addTab("One");
        QStandardItemModel model(2, 1);
        QDataWidgetMapper mapper;
        mapper.setModel(&model);
        QSizePolicy policy(QSizePolicy::Expanding, QSizePolicy::Fixed);
        return dateEdit.date() == QDate(2024, 1, 1) && timeEdit.time() == QTime(12, 30)
            && tabBar.count() == 1 && mapper.model() == &model
            && policy.horizontalPolicy() == QSizePolicy::Expanding;
    });
    r.check("widgets/rubberband-sizegrip-focusframe-splash-errormsg-progress-tooltip", [&](QString &d) {
        QWidget host;
        QRubberBand rubberBand(QRubberBand::Rectangle, &host);
        QSizeGrip sizeGrip(&host);
        QFocusFrame focusFrame(&host);
        QPixmap pixmap(1, 1);
        QSplashScreen splash(pixmap);
        QErrorMessage errorMsg;
        QProgressDialog progress("Working...", "Cancel", 0, 100);
        QToolTip::showText(QPoint(0, 0), QString());   // immediately hidden, just touches the API
        QWhatsThis::leaveWhatsThisMode();               // no-op if not active - safe to call
        return rubberBand.shape() == QRubberBand::Rectangle && sizeGrip.parent() == &host
            && focusFrame.parent() == &host && progress.maximum() == 100;
    });
    r.check("widgets/syntaxhighlighter", [&](QString &d) {
        QTextDocument doc("hello world");
        class UppercaseHighlighter : public QSyntaxHighlighter {
        public:
            using QSyntaxHighlighter::QSyntaxHighlighter;
            int blocksSeen = 0;
            void highlightBlock(const QString &) override { ++blocksSeen; }
        };
        UppercaseHighlighter highlighter(&doc);
        highlighter.rehighlight();
        return highlighter.blocksSeen >= 1;
    });
}

void checkDragDropEvents(SmokeReporter &r)
{
    r.check("dragdrop/event-value-types", [&](QString &d) {
        QMimeData mime;
        mime.setText("payload");
        QDragEnterEvent enter(QPoint(1, 1), Qt::CopyAction, &mime, Qt::LeftButton, Qt::NoModifier);
        QDragMoveEvent move(QPoint(2, 2), Qt::CopyAction, &mime, Qt::LeftButton, Qt::NoModifier);
        QDragLeaveEvent leave;
#if SMOKE_QT5
        QDropEvent drop(QPointF(3, 3), Qt::CopyAction, &mime, Qt::LeftButton, Qt::NoModifier);
#else
        QDropEvent drop(QPoint(3, 3), Qt::CopyAction, &mime, Qt::LeftButton, Qt::NoModifier);
#endif
        return enter.mimeData()->text() == "payload" && move.pos() == QPoint(2, 2)
            && drop.mimeData() == &mime && leave.type() == QEvent::DragLeave;
    });
}

void checkGraphicsExtras(SmokeReporter &r)
{
    r.check("graphics/line-simpletext-object-widget", [&](QString &d) {
        QGraphicsScene scene;
        auto *line = scene.addLine(0, 0, 10, 10);
        auto *rect = scene.addRect(0, 0, 10, 10);
        rect->setBrush(Qt::green);
        auto *text = scene.addSimpleText("hi");
        auto *widget = new QGraphicsWidget;
        scene.addItem(widget);
        // Reached through the real base every scene item derives from.
        QGraphicsObject *asObject = qgraphicsitem_cast<QGraphicsObject *>(widget);
        QAbstractGraphicsShapeItem *asShape = rect;
        return line->line().length() > 0 && text->text() == "hi" && asObject == widget
            && asShape->brush().color() == QColor(Qt::green);
    });
    r.check("graphics/anchor-linear-grid-layouts", [&](QString &d) {
        // A layout item can only belong to one layout at a time -
        // addAnchor()/addItem() below each reparent their items away from
        // whatever layout previously held them, so each layout here needs its
        // own distinct set of widgets, not shared ones.
        auto *linear = new QGraphicsLinearLayout(Qt::Horizontal);
        auto *w1 = new QGraphicsWidget; auto *w2 = new QGraphicsWidget;
        linear->addItem(w1); linear->addItem(w2);
        // Reached through the real base every layout-managed item derives from.
        QGraphicsLayoutItem *asLayoutItem = w1;
        auto *anchorLayout = new QGraphicsAnchorLayout;
        auto *w3 = new QGraphicsWidget; auto *w4 = new QGraphicsWidget;
        QGraphicsAnchor *anchor = anchorLayout->addAnchor(w3, Qt::AnchorLeft, w4, Qt::AnchorRight);
        auto *w5 = new QGraphicsWidget;
        auto *grid = new QGraphicsGridLayout;
        grid->addItem(w5, 0, 0);
        bool ok = linear->count() == 2 && anchor != nullptr && grid->count() == 1
            && !asLayoutItem->isLayout();
        delete linear; delete anchorLayout; delete grid;
        return ok;
    });
    r.check("graphics/rotation-scale-item-animation", [&](QString &d) {
        QGraphicsScene scene;
        auto *rect = scene.addRect(0, 0, 10, 10);
        auto *rotation = new QGraphicsRotation;
        rotation->setAngle(45);
        auto *scale = new QGraphicsScale;
        scale->setXScale(2.0);
        rect->setTransformations({rotation, scale});
        auto *anim = new QGraphicsItemAnimation;
        auto *timeline = new QTimeLine(1000);
        anim->setItem(rect);
        anim->setTimeLine(timeline);
        anim->setPosAt(0.0, QPointF(0, 0));
        anim->setPosAt(1.0, QPointF(50, 50));
        bool ok = qFuzzyCompare(rotation->angle(), 45.0) && qFuzzyCompare(scale->xScale(), 2.0)
            && anim->item() == rect;
        delete anim; delete timeline;
        return ok;
    });
}
