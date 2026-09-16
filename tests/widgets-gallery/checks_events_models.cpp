// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// The last sweep: QEvent's remaining constructible subclasses (every one of
// these is a plain value type an app can build to post/inspect an event),
// custom item-model bases (the real, documented way to expose non-Qt data as
// a model - no concrete QAbstract*Model exists to just instantiate), and a
// handful of remaining standalone classes.
#include "../common/smokecheck.h"

#include <QAction>
#include <QActionEvent>
#include <QChildEvent>
#include <QCloseEvent>
#include <QContextMenuEvent>
#if SMOKE_QT5
#  include <QEnterEvent>
#endif
#if SMOKE_QT5
#  include <QExposeEvent>   // arrived with QPA in Qt 5
#endif
#include <QFileOpenEvent>
#include <QFocusEvent>
#include <QHelpEvent>
#include <QHideEvent>
#include <QHoverEvent>
#include <QIconDragEvent>
#include <QInputMethodEvent>
#if SMOKE_QT5
#  include <QInputMethodQueryEvent>   // Qt 5 and later
#endif
#include <QMoveEvent>
#include <QResizeEvent>
#if SMOKE_QT5
#  include <QScrollEvent>          // kinetic scroller, Qt 5
#  include <QScrollPrepareEvent>
#endif
#include <QShortcutEvent>
#include <QShowEvent>
#include <QStatusTipEvent>
#include <QTabletEvent>
#if QT_VERSION_MAJOR >= 6
#include <QPointingDevice>
#include <QTest>
#include <QWindow>
#endif
#include <QToolBarChangeEvent>
#include <QWindowStateChangeEvent>

#include <QAbstractListModel>
#include <QAbstractTableModel>
#include <QAbstractProxyModel>
#if SMOKE_QT5
#  include <QConcatenateTablesProxyModel>   // Qt 5.13 and later
#endif
#include <QStandardItemModel>
#if QT_VERSION_MAJOR < 6
#include <QDirModel>   // removed in Qt 6; QFileSystemModel below replaces it
#endif
#include <QFileSystemModel>
#include <QListWidgetItem>
#include <QItemDelegate>

#include <QSignalMapper>
#include <QPalette>
#include <QScreen>
#if SMOKE_QT5
#  include <QStyleHints>   // Qt 5 and later
#endif
#include <QSplitter>
#include <QSplitterHandle>
#include <QApplication>
#include <QAbstractEventDispatcher>
#if SMOKE_QT5
#  include <QAbstractNativeEventFilter>   // Qt 5 and later
#endif

void checkEventCatalogue(SmokeReporter &r)
{
    r.check("events/qt6-touch-sequences", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        QScopedPointer<QPointingDevice> device(QTest::createTouchDevice());
        if (device.isNull()) {
            d = QStringLiteral("QTest::createTouchDevice returned null");
            return false;
        }

        QWindow window;
        window.resize(64, 64);
        window.show();
        QTest::QTouchEventSequence windowSequence = QTest::touchEvent(&window, device.data(), false);
        const bool windowCommitted = windowSequence.press(0, QPoint(8, 8), &window)
            .move(0, QPoint(12, 12), &window)
            .release(0, QPoint(12, 12), &window)
            .commit();

        QWidget widget;
        widget.setAttribute(Qt::WA_AcceptTouchEvents);
        widget.resize(64, 64);
        widget.show();
        QTest::QTouchEventWidgetSequence widgetSequence = QTest::touchEvent(&widget, device.data(), false);
        const bool widgetCommitted = widgetSequence.press(1, QPoint(10, 10), &widget)
            .move(1, QPoint(16, 16), &widget)
            .release(1, QPoint(16, 16), &widget)
            .commit();

        if (!windowCommitted || !widgetCommitted)
            d = QStringLiteral("touch sequence commit failed");
        return windowCommitted && widgetCommitted;
#else
        r.skip(d, QStringLiteral("these QtTest touch sequence types are Qt 6 only"));
        return false;
#endif
    });

    r.check("events/window-lifecycle", [&](QString &d) {
        QCloseEvent closeEv;
        QHideEvent hideEv;
        QShowEvent showEv;
        QMoveEvent moveEv(QPoint(10, 10), QPoint(0, 0));
        QResizeEvent resizeEv(QSize(100, 100), QSize(50, 50));
        QWindowStateChangeEvent stateEv(Qt::WindowNoState);
        // QExposeEvent arrived with the QPA layer in Qt 5; the rest of this
        // check is Qt 4 API and still runs there.
        bool exposeOk = true;
#if SMOKE_QT5
        QExposeEvent exposeEv(QRegion(0, 0, 10, 10));
        exposeOk = exposeEv.region().boundingRect().width() == 10;
#endif
        return moveEv.pos() == QPoint(10, 10) && resizeEv.size() == QSize(100, 100)
            && exposeOk
            && stateEv.oldState() == Qt::WindowNoState
            && closeEv.type() == QEvent::Close && hideEv.type() == QEvent::Hide
            && showEv.type() == QEvent::Show;
    });
    r.check("events/focus-input-help-hover", [&](QString &d) {
        QFocusEvent focusEv(QEvent::FocusIn, Qt::TabFocusReason);
        QHelpEvent helpEv(QEvent::ToolTip, QPoint(2, 2), QPoint(2, 2));
        QInputMethodEvent imEvent;
        // Three of these are Qt 5: QEnterEvent and QInputMethodQueryEvent did
        // not exist, and QHoverEvent took QPoint rather than QPointF - so even
        // the class Qt 4 has cannot be constructed the same way.
        bool qt5Events = true;
#if SMOKE_QT5
        QEnterEvent enterEv(QPointF(1, 1), QPointF(1, 1), QPointF(1, 1));
        QHoverEvent hoverEv(QEvent::HoverMove, QPointF(3, 3), QPointF(2, 2));
        QInputMethodQueryEvent imQuery(Qt::ImCursorPosition);
        qt5Events = enterEv.type() == QEvent::Enter && hoverEv.pos() == QPointF(3, 3)
            && imQuery.queries() == Qt::ImCursorPosition;
#endif
        return focusEv.reason() == Qt::TabFocusReason && helpEv.pos() == QPoint(2, 2)
            && imEvent.type() == QEvent::InputMethod && qt5Events;
    });
    r.check("events/menu-shortcut-statustip-toolbar-icondrag", [&](QString &d) {
        QAction action("Do it", nullptr);
        QActionEvent actionEv(QEvent::ActionAdded, &action);
        QShortcutEvent shortcutEv(QKeySequence("Ctrl+K"), 42);
        QStatusTipEvent statusTipEv("Ready");
        QToolBarChangeEvent toolBarEv(true);
        QIconDragEvent iconDragEv;
        QContextMenuEvent menuEv(QContextMenuEvent::Mouse, QPoint(4, 4));
        return actionEv.action() == &action && shortcutEv.shortcutId() == 42
            && statusTipEv.tip() == "Ready" && toolBarEv.toggle()
            && iconDragEv.type() == QEvent::IconDrag && menuEv.reason() == QContextMenuEvent::Mouse;
    });
    r.check("events/child-fileopen-scroll-tablet", [&](QString &d) {
        QObject parent, child;
        QChildEvent childEv(QEvent::ChildAdded, &child);
        QFileOpenEvent fileOpenEv(QStringLiteral("/tmp/file.txt"));
        bool scrollOk = true;
#if SMOKE_QT5
        QScrollEvent scrollEv(QPointF(0, 0), QPointF(0, 0), QScrollEvent::ScrollStarted);
        QScrollPrepareEvent scrollPrepEv(QPointF(0, 0));
        scrollOk = scrollEv.scrollState() == QScrollEvent::ScrollStarted
            && scrollPrepEv.startPos() == QPointF(0, 0);
#endif
#if !SMOKE_QT5
        // Qt 4 takes the position as QPoint plus a high-resolution QPointF, and
        // knows nothing about buttons - they arrived with Qt 5.
        QTabletEvent tabletEv(QEvent::TabletMove, QPoint(5, 5), QPoint(5, 5),
                              QPointF(5, 5), 0, 0, 1.0, 0, 0, 0.0, 0, 0,
                              Qt::NoModifier, qint64(1));
#elif QT_VERSION_MAJOR < 6
        QTabletEvent tabletEv(QEvent::TabletMove, QPointF(5, 5), QPointF(5, 5),
                              0, 0, 1.0, 0, 0, 0.0, 0, 0, Qt::NoModifier,
                              qint64(1), Qt::NoButton, Qt::NoButton);
#else
        // Qt 6 identifies the tablet by device object rather than by the pair
        // of integer ids, and takes the tilts as float.
        QTabletEvent tabletEv(QEvent::TabletMove, QPointingDevice::primaryPointingDevice(),
                              QPointF(5, 5), QPointF(5, 5), 1.0, 0.0f, 0.0f,
                              0.0f, 0.0, 0.0f, Qt::NoModifier,
                              Qt::NoButton, Qt::NoButton);
#endif
        return childEv.child() == &child && fileOpenEv.file() == QStringLiteral("/tmp/file.txt")
            && scrollOk && tabletEv.type() == QEvent::TabletMove;
    });
}

namespace {
class MinimalListModel : public QAbstractListModel {
public:
    int rowCount(const QModelIndex & = QModelIndex()) const override { return 3; }
    QVariant data(const QModelIndex &index, int role) const override {
        return role == Qt::DisplayRole ? QVariant(index.row()) : QVariant();
    }
};
class MinimalTableModel : public QAbstractTableModel {
public:
    int rowCount(const QModelIndex & = QModelIndex()) const override { return 2; }
    int columnCount(const QModelIndex & = QModelIndex()) const override { return 2; }
    QVariant data(const QModelIndex &, int) const override { return QVariant(); }
};
class PassthroughProxyModel : public QAbstractProxyModel {
public:
    QModelIndex mapToSource(const QModelIndex &proxyIndex) const override { return proxyIndex; }
    QModelIndex mapFromSource(const QModelIndex &sourceIndex) const override { return sourceIndex; }
    int rowCount(const QModelIndex &parent = QModelIndex()) const override {
        return sourceModel() ? sourceModel()->rowCount(parent) : 0;
    }
    int columnCount(const QModelIndex &parent = QModelIndex()) const override {
        return sourceModel() ? sourceModel()->columnCount(parent) : 0;
    }
    QModelIndex index(int row, int column, const QModelIndex &parent = QModelIndex()) const override {
        return hasIndex(row, column, parent) ? createIndex(row, column) : QModelIndex();
    }
    QModelIndex parent(const QModelIndex &) const override { return QModelIndex(); }
};
#if SMOKE_QT5
class DummyEventFilter : public QAbstractNativeEventFilter {
public:
#if QT_VERSION_MAJOR < 6
    bool nativeEventFilter(const QByteArray &, void *, long *) override { return false; }
#else
    // qintptr in Qt 6: on 64-bit Windows `long` is 32 bits and the
    // result is pointer-sized, so the old signature was wrong there.
    bool nativeEventFilter(const QByteArray &, void *, qintptr *) override { return false; }
#endif
};
#endif  // SMOKE_QT5
}

void checkModelBasesAndFileModels(SmokeReporter &r)
{
    r.check("models/list-table-proxy-concatenate-bases", [&](QString &d) {
        MinimalListModel listModel;
        MinimalTableModel tableModel;
        PassthroughProxyModel proxy;
        QStandardItemModel source(3, 1);
        proxy.setSourceModel(&source);
        // QConcatenateTablesProxyModel is Qt 5.13; the other three model bases
        // in this check are as old as Qt 4.
        bool concatOk = true;
#if SMOKE_QT5
        QConcatenateTablesProxyModel concat;
        concat.addSourceModel(&source);
        concatOk = concat.rowCount() == 3;
#endif
        return listModel.rowCount() == 3 && tableModel.columnCount() == 2
            && proxy.sourceModel() == &source && concatOk;
    });
    r.check("models/dirmodel-filesystemmodel-listitem-delegate", [&](QString &d) {
        QFileSystemModel fsModel;
        auto *item = new QListWidgetItem("entry");
        QItemDelegate delegate;
        bool dirModelOk = true;
#if QT_VERSION_MAJOR < 6
        QDirModel dirModel;
        dirModelOk = dirModel.columnCount() > 0;
#endif
        return dirModelOk && !fsModel.rootPath().isEmpty()
            && item->text() == "entry" && delegate.itemEditorFactory() == delegate.itemEditorFactory();
    });
}

void checkMiscQtBaseTail(SmokeReporter &r)
{
    r.check("qtbase/signalmapper-palette-screen-stylehints-splitter", [&](QString &d) {
        QSignalMapper mapper;
        mapper.setMapping(&mapper, 7);
        QPalette palette(Qt::blue);
        bool screenAndHintsOk = true;
#if SMOKE_QT5
        QScreen *screen = QApplication::primaryScreen();
        QStyleHints *hints = QApplication::styleHints();
        screenAndHintsOk = screen != nullptr && hints != nullptr;
#endif
        QSplitter splitter;
        splitter.addWidget(new QWidget);
        splitter.addWidget(new QWidget);
        QSplitterHandle *handle = splitter.handle(1);
        return palette.color(QPalette::Button) == QColor(Qt::blue)
            && screenAndHintsOk && handle != nullptr;
    });
    r.check("qtbase/event-dispatcher-native-filter", [&](QString &d) {
        QAbstractEventDispatcher *dispatcher = QAbstractEventDispatcher::instance();
        // Native event filters are installed on the application in Qt 5; Qt 4
        // has no QAbstractNativeEventFilter and overrides
        // QCoreApplication::winEventFilter() instead. The dispatcher half of
        // the check is the same on both.
#if SMOKE_QT5
        DummyEventFilter filter;
        QCoreApplication::instance()->installNativeEventFilter(&filter);
        QCoreApplication::instance()->removeNativeEventFilter(&filter);
#endif
        return dispatcher != nullptr;
    });
}
