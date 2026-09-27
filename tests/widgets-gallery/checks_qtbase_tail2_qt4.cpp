// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Qt 4 counterpart to checks_qtbase_tail2.cpp.
//
// That file is written around eighteen "Qt 5 or Qt 6?" branches, and Qt 4 is a
// third answer to a question asked as a binary one - which is why it is swapped
// out here rather than guarded line by line, the same arrangement
// checks_qtbase_misc_qt4.cpp uses in the console app.
//
// The check names are deliberately the ones the Qt 5/Qt 6 file uses, because the
// question each asks is the same on all three; where the Qt 4 body is a strict
// subset the name says so by staying put. Two names differ, and both are noted
// where they appear.
//
// What is NOT here, and why - so a shorter Qt 4 list is readable rather than
// merely shorter:
//
//   QPlatform* / QWindowSystemInterface   Qt 4.8's QPA was an unfinished preview
//                                         with no public headers to include, and
//                                         an application implements none of it.
//   QScroller, QScrollerProperties        Qt 5.0.
//   QNativeGestureEvent, QTouchDevice     Qt 5; Qt 4 keeps the device type on
//                                         QTouchEvent itself, which is what the
//                                         touch check below uses.
//   QGLFunctions                          exists in 4.8, but needs QtOpenGL,
//                                         which this application does not link.
//                                         Covered by gl-heavy's Qt 4 build.
#include "../common/smokecheck.h"
#include "gallery.h"

#include <QAbstractAnimation>
#include <QAbstractPrintDialog>
#include <QAbstractTextDocumentLayout>
#include <QAnimationGroup>
#include <QApplication>
#include <QColorDialog>
#include <QColormap>
#include <QDesktopWidget>
#include <QDrag>
#include <QFileDialog>
#include <QFontDialog>
#include <QGraphicsSceneContextMenuEvent>
#include <QGraphicsSceneDragDropEvent>
#include <QGraphicsSceneEvent>
#include <QGraphicsSceneHelpEvent>
#include <QGraphicsSceneHoverEvent>
#include <QGraphicsSceneMouseEvent>
#include <QGraphicsSceneMoveEvent>
#include <QGraphicsSceneResizeEvent>
#include <QGraphicsSceneWheelEvent>
#include <QGraphicsTransform>
#include <QGestureEvent>
#include <QGestureRecognizer>
#include <QGlyphRun>
#include <QImage>
#include <QImageIOPlugin>
#include <QInputEvent>
#include <QItemEditorCreatorBase>
#include <QItemEditorFactory>
#include <QItemSelectionRange>
#include <QKeyEvent>
#include <QKeyEventTransition>
#include <QLineEdit>
#include <QMatrix4x4>
#include <QMimeData>
#include <QMouseEventTransition>
#include <QPaintEngine>
#include <QPanGesture>
#include <QParallelAnimationGroup>
#include <QPictureIO>
#include <QPlainTextDocumentLayout>
#include <QPrintDialog>
#include <QPrintEngine>
#include <QPrinter>
#include <QPropertyAnimation>
#include <QSpinBox>
#include <QStandardItemEditorCreator>
#include <QStandardItemModel>
#include <QState>
#include <QStateMachine>
#include <QStyleOptionGraphicsItem>
#include <QStyleOptionTab>
#include <QTableWidget>
#include <QTableWidgetSelectionRange>
#include <QTestData>
#include <QTestEventLoop>
#include <QTextBlock>
#include <QTextBlockGroup>
#include <QTextBlockUserData>
#include <QTextDocument>
#include <QTextFragment>
#include <QTextFrame>
#include <QTextFrameLayoutData>
#include <QTextInlineObject>
#include <QTextItem>
#include <QTextObjectInterface>
#include <QTouchEvent>
#include <QTransform>
#include <QTreeWidget>
#include <QTreeWidgetItemIterator>
#include <QVector>
#include <QWheelEvent>
#include <QWidgetAction>
#include <QWidgetItem>
#include <QWidgetItemV2>

namespace {

// `override` throughout, deliberately. Qt 4's signatures for these hooks are the
// same as Qt 5's, but "the same" is exactly the claim being made by porting the
// file - and if one of them differs, a compile error naming it is worth far more
// than a check that silently no longer overrides anything and passes anyway.
class SmokeTextLayoutQt4 : public QAbstractTextDocumentLayout
{
public:
    explicit SmokeTextLayoutQt4(QTextDocument *doc) : QAbstractTextDocumentLayout(doc) {}

    void draw(QPainter *, const PaintContext &) override {}
    int hitTest(const QPointF &, Qt::HitTestAccuracy) const override { return 0; }
    int pageCount() const override { return 1; }
    QSizeF documentSize() const override { return QSizeF(100, 20); }
    QRectF frameBoundingRect(QTextFrame *) const override { return QRectF(0, 0, 100, 20); }
    QRectF blockBoundingRect(const QTextBlock &) const override { return QRectF(0, 0, 100, 20); }

protected:
    void documentChanged(int, int, int) override {}
};

class SmokeTextObjectQt4 : public QObject, public QTextObjectInterface
{
public:
    QSizeF intrinsicSize(QTextDocument *, int, const QTextFormat &) override { return QSizeF(4, 5); }
    void drawObject(QPainter *, const QRectF &, QTextDocument *, int,
                    const QTextFormat &) override {}
};

// Qt 4's plugin interfaces all derive from QFactoryInterface, so every one of
// them has keys() to implement on top of its own hooks. Qt 5 dropped that in
// favour of the JSON metadata, which is the single difference between this
// class and its counterpart in the Qt 5/6 file.
class SmokeImagePluginQt4 : public QImageIOPlugin
{
public:
    QStringList keys() const override { return QStringList() << QStringLiteral("smoke"); }
    Capabilities capabilities(QIODevice *, const QByteArray &format) const override
    {
        return format == QByteArray("smoke") ? Capabilities(CanRead) : Capabilities();
    }
    QImageIOHandler *create(QIODevice *, const QByteArray &) const override { return 0; }
};

class SmokeGestureRecognizerQt4 : public QGestureRecognizer
{
public:
    QGesture *create(QObject *) override { return new QPanGesture; }
    Result recognize(QGesture *, QObject *, QEvent *) override { return Ignore; }
    void reset(QGesture *gesture) override { QGestureRecognizer::reset(gesture); }
};

class SmokeFrameLayoutDataQt4 : public QTextFrameLayoutData
{
public:
    ~SmokeFrameLayoutDataQt4() override {}
};

} // namespace

void addQtBaseWidgetsTail2Qt4Checks(SmokeReporter &r)
{
    r.check("qtbase/dialogs-options-desktop", [&](QString &d) {
        QFileDialog fileDialog;
        fileDialog.setOption(QFileDialog::DontUseNativeDialog);
        fileDialog.setFileMode(QFileDialog::ExistingFiles);
        fileDialog.setNameFilters(QStringList() << QStringLiteral("Text (*.txt)"));
        QColorDialog colorDialog(Qt::green);
        colorDialog.setOption(QColorDialog::ShowAlphaChannel);
        QFontDialog fontDialog;
        fontDialog.setOption(QFontDialog::DontUseNativeDialog);
        QDesktopWidget *desktop = QApplication::desktop();

#if !defined(QT_NO_PRINTER) && !defined(QT_NO_PRINTDIALOG)
        QPrinter printer;
        QPrintDialog printDialog(&printer);
        QAbstractPrintDialog *abstractPrintDialog = &printDialog;
        abstractPrintDialog->setPrintRange(QAbstractPrintDialog::PageRange);
        abstractPrintDialog->setFromTo(1, 2);
#endif

        return fileDialog.testOption(QFileDialog::DontUseNativeDialog)
            && fileDialog.fileMode() == QFileDialog::ExistingFiles
            && colorDialog.testOption(QColorDialog::ShowAlphaChannel)
            && fontDialog.testOption(QFontDialog::DontUseNativeDialog)
            && desktop != 0
#if !defined(QT_NO_PRINTER) && !defined(QT_NO_PRINTDIALOG)
            && abstractPrintDialog->printRange() == QAbstractPrintDialog::PageRange
            && abstractPrintDialog->fromPage() == 1
            && abstractPrintDialog->toPage() == 2
#endif
            ;
    });

    r.check("qtbase/item-editor-selection-ranges", [&](QString &d) {
        QItemEditorFactory factory;
        factory.registerEditor(QVariant::Int, new QStandardItemEditorCreator<QSpinBox>);
        QWidget parent;
        QWidget *editor = factory.createEditor(QVariant::Int, &parent);
        QItemEditorCreatorBase *creator = new QStandardItemEditorCreator<QLineEdit>;
        QStandardItemModel model(3, 3);
        QModelIndex topLeft = model.index(0, 0);
        QModelIndex bottomRight = model.index(1, 1);
        QItemSelectionRange range(topLeft, bottomRight);
        QTableWidgetSelectionRange tableRange(0, 0, 1, 1);
        delete creator;
        return editor != 0
            && factory.valuePropertyName(QVariant::Int) == QByteArray("value")
            && range.top() == 0
            && range.bottom() == 1
            && range.left() == 0
            && range.right() == 1
            && tableRange.rowCount() == 2
            && tableRange.columnCount() == 2;
    });

    r.check("qtbase/graphics-scene-event-catalogue", [&](QString &d) {
        QWidget widget;
        QGraphicsSceneEvent base(QEvent::GraphicsSceneMousePress);
        base.setWidget(&widget);
        QGraphicsSceneMouseEvent mouse(QEvent::GraphicsSceneMousePress);
        mouse.setPos(QPointF(1, 2));
        mouse.setButton(Qt::LeftButton);
        QGraphicsSceneWheelEvent wheel(QEvent::GraphicsSceneWheel);
        wheel.setDelta(120);
        QGraphicsSceneContextMenuEvent context(QEvent::GraphicsSceneContextMenu);
        context.setReason(QGraphicsSceneContextMenuEvent::Keyboard);
        QGraphicsSceneHoverEvent hover(QEvent::GraphicsSceneHoverMove);
        hover.setLastPos(QPointF(2, 3));
        QGraphicsSceneHelpEvent help(QEvent::GraphicsSceneHelp);
        help.setScenePos(QPointF(4, 5));
        QMimeData mime;
        mime.setText(QStringLiteral("drag"));
        QGraphicsSceneDragDropEvent drag(QEvent::GraphicsSceneDrop);
        drag.setMimeData(&mime);
        drag.setDropAction(Qt::CopyAction);
        QGraphicsSceneResizeEvent resize;
        resize.setOldSize(QSizeF(10, 10));
        resize.setNewSize(QSizeF(20, 20));
        QGraphicsSceneMoveEvent move;
        move.setOldPos(QPointF(1, 1));
        move.setNewPos(QPointF(2, 2));
        return base.widget() == &widget
            && mouse.pos() == QPointF(1, 2)
            && mouse.button() == Qt::LeftButton
            && wheel.delta() == 120
            && context.reason() == QGraphicsSceneContextMenuEvent::Keyboard
            && hover.lastPos() == QPointF(2, 3)
            && help.scenePos() == QPointF(4, 5)
            && drag.mimeData()->text() == QStringLiteral("drag")
            && resize.newSize() == QSizeF(20, 20)
            && move.newPos() == QPointF(2, 2);
    });

    r.check("qtbase/text-layout-object-tail", [&](QString &d) {
        QTextDocument doc(QStringLiteral("hello\nworld"));
        QTextDocument plainDoc(QStringLiteral("plain"));
        SmokeTextLayoutQt4 layout(&doc);
        QAbstractTextDocumentLayout *abstractLayout = &layout;
        QPlainTextDocumentLayout plainLayout(&plainDoc);
        SmokeTextObjectQt4 objectHandler;
        QAbstractTextDocumentLayout::PaintContext context;
        QAbstractTextDocumentLayout::Selection selection;
        selection.cursor = QTextCursor(&doc);
        context.selections.append(selection);
        QTextBlock firstBlock = doc.firstBlock();
        QTextBlockUserData *userData = new QTextBlockUserData;
        firstBlock.setUserData(userData);
        QTextBlockGroup *blockGroup = 0;
        QTextFrame *frame = doc.rootFrame();
        QTextObjectInterface *handler = &objectHandler;
        const QSizeF objectSize = handler->intrinsicSize(&doc, 0, QTextFormat());
        QTextInlineObject inlineObject;
        Q_UNUSED(inlineObject);
        QTextFragment fragment;
        QStringList misses;
        if (abstractLayout->documentSize() != QSizeF(100, 20)) misses << QStringLiteral("document-size");
        if (plainLayout.document() != &plainDoc) misses << QStringLiteral("plain-layout");
        if (context.selections.size() != 1) misses << QStringLiteral("selection");
        if (firstBlock.userData() != userData) misses << QStringLiteral("userdata");
        if (blockGroup != 0) misses << QStringLiteral("blockgroup");
        if (frame == 0) misses << QStringLiteral("frame");
        if (handler != &objectHandler) misses << QStringLiteral("handler");
        if (objectSize != QSizeF(4, 5)) misses << QStringLiteral("object-size");
        if (fragment.isValid()) misses << QStringLiteral("fragment");
        if (!misses.isEmpty())
            d = misses.join(QLatin1String(","));
        return misses.isEmpty();
    });

    // Named without "scroller" on purpose: QScroller is Qt 5.0, so this is the
    // rest of the Qt 5/6 check of that name rather than a subset of it.
    r.check("qtbase/icon-plugin-picture-drag", [&](QString &d) {
        QWidget host;
        QDrag drag(&host);
        QMimeData *mime = new QMimeData;
        mime->setText(QStringLiteral("payload"));
        drag.setMimeData(mime);

        SmokeImagePluginQt4 imagePlugin;
        QImageIOPlugin *imagePluginBase = &imagePlugin;
        QPictureIO pictureIo;
        pictureIo.setFormat("smoke");

        return drag.mimeData()->text() == QStringLiteral("payload")
            && imagePluginBase->keys().contains(QStringLiteral("smoke"))
            && (imagePluginBase->capabilities(0, QByteArray("smoke")) & QImageIOPlugin::CanRead)
            && imagePluginBase->create(0, QByteArray("smoke")) == 0
            && QByteArray(pictureIo.format()) == QByteArray("smoke");
    });

    r.check("qtbase/tree-iterator-widget-action-style-tail", [&](QString &d) {
        QTreeWidget tree;
        tree.setColumnCount(1);
        new QTreeWidgetItem(&tree, QStringList() << QStringLiteral("root"));
        QTreeWidgetItemIterator it(&tree);
        QWidget host;
        QWidgetAction widgetAction(&host);
        QLineEdit *lineEdit = new QLineEdit;
        widgetAction.setDefaultWidget(lineEdit);
        QStyleOptionGraphicsItem graphicsOption;
        QStyleOptionTab tabOption;
        tabOption.version = QStyleOptionTab::Version;
        QGraphicsScale scale;
        scale.setXScale(2.0);
        QGraphicsTransform *transformBase = &scale;
        QMatrix4x4 matrix;
        transformBase->applyTo(&matrix);
        return (*it)->text(0) == QStringLiteral("root")
            && widgetAction.defaultWidget() == lineEdit
            && graphicsOption.levelOfDetailFromTransform(QTransform().scale(2, 2)) >= 2.0
            && tabOption.version == QStyleOptionTab::Version
            && !matrix.isIdentity();
    });

    r.check("qtbase/input-touch-gesture-text-tail", [&](QString &d) {
        QKeyEvent keyEvent(QEvent::KeyPress, Qt::Key_A,
                           Qt::KeyboardModifiers(Qt::ControlModifier),
                           QStringLiteral("a"), false, 1);
        QWheelEvent wheelEvent(QPoint(3, 4), 120, Qt::NoButton, Qt::ShiftModifier);
        QInputEvent *inputEvent = &keyEvent;

        // Qt 4 describes the touch device with an enum on the event; QTouchDevice
        // and the per-point state of Qt 5 do not exist here.
        QTouchEvent::TouchPoint touchPoint(1);
        QTouchEvent touchEvent(QEvent::TouchBegin, QTouchEvent::TouchScreen, Qt::NoModifier,
                               Qt::TouchPointPressed,
                               QList<QTouchEvent::TouchPoint>() << touchPoint);

        QPanGesture panGesture;
        QList<QGesture *> gestures;
        gestures << &panGesture;
        QGestureEvent gestureEvent(gestures);
        QWidget widget;
        SmokeGestureRecognizerQt4 recognizer;
        QGestureRecognizer *recognizerBase = &recognizer;
        QGesture *createdGesture = recognizerBase->create(&widget);

        bool ok = inputEvent->modifiers() == Qt::ControlModifier
            && wheelEvent.delta() == 120
            && wheelEvent.modifiers() == Qt::ShiftModifier
            && touchEvent.deviceType() == QTouchEvent::TouchScreen
            && touchEvent.touchPoints().size() == 1
            && touchEvent.touchPointStates() == Qt::TouchPointStates(Qt::TouchPointPressed)
            && gestureEvent.gestures().size() == 1
            && gestureEvent.gesture(Qt::PanGesture) == &panGesture
            && createdGesture != 0;
        delete createdGesture;
        return ok;
    });

    r.check("qtbase/glyph-run-tail", [&](QString &d) {
#ifdef QT_NO_RAWFONT
        r.skip(d, QStringLiteral("QRawFont/QGlyphRun are unavailable in this Qt backend"));
        return false;
#else
        QGlyphRun glyphRun;
        QVector<quint32> glyphIndexes;
        glyphIndexes << 1 << 2;
        QVector<QPointF> glyphPositions;
        glyphPositions << QPointF(0, 0) << QPointF(5, 0);
        glyphRun.setGlyphIndexes(glyphIndexes);
        glyphRun.setPositions(glyphPositions);
        glyphRun.setUnderline(true);

        return glyphRun.glyphIndexes().size() == 2 && glyphRun.underline();
#endif
    });

    r.check("qtbase/state-style-layout-textitem-tail", [&](QString &d) {
        QStateMachine machine;
        QState source(&machine);
        QState target(&machine);
        QObject eventSource;
        QKeyEventTransition keyTransition(&eventSource, QEvent::KeyPress, Qt::Key_A, &source);
        keyTransition.setModifierMask(Qt::ControlModifier);
        keyTransition.setTargetState(&target);
        QMouseEventTransition mouseTransition(&eventSource, QEvent::MouseButtonPress,
                                              Qt::LeftButton, &source);
        mouseTransition.setModifierMask(Qt::ShiftModifier);

        QWidget widget;
        QWidgetItemV2 widgetItem(&widget);
        QWidgetItem *widgetItemBase = &widgetItem;

        QTextDocument doc(QStringLiteral("layout-data"));
        QTextFrame *frame = doc.rootFrame();
        SmokeFrameLayoutDataQt4 *layoutData = new SmokeFrameLayoutDataQt4;
        frame->setLayoutData(layoutData);
        QTextItem *textItem = 0;
        QImage image(4, 4, QImage::Format_ARGB32_Premultiplied);
        QPaintEngine *paintEngine = image.paintEngine();
        QPaintEngineState *paintEngineState = 0;
#ifndef QT_NO_PRINTER
        QPrinter printer;
        QPrintEngine *printEngine = printer.printEngine();
#endif
        QColormap colormap = QColormap::instance();

        return keyTransition.key() == Qt::Key_A
            && keyTransition.modifierMask() == Qt::ControlModifier
            && keyTransition.targetState() == &target
            && mouseTransition.button() == Qt::LeftButton
            && mouseTransition.modifierMask() == Qt::ShiftModifier
            && widgetItemBase->widget() == &widget
            && frame->layoutData() == layoutData
            && textItem == 0
            && paintEngine != 0
            && paintEngineState == 0
#ifndef QT_NO_PRINTER
            && printEngine != 0
#endif
            && colormap.depth() >= 0;
    });

    // QtTest's two shells, and the animation group Qt 5/6 reach through Qt3D's
    // animation aspect - which 4.8.7 predates, while the QtCore framework
    // underneath it is the same one Qt 4.6 introduced.
    r.check("qtbase/testlib-shells-and-animation-group", [&](QString &d) {
        QTestData *testData = 0;
        QTestEventLoop *testEventLoop = 0;

        QObject animationTarget;
        animationTarget.setProperty("smoke", 0);
        QParallelAnimationGroup group;
        QPropertyAnimation *animation = new QPropertyAnimation(&animationTarget, "smoke");
        animation->setStartValue(0);
        animation->setEndValue(1);
        animation->setDuration(1);
        group.addAnimation(animation);
        QAnimationGroup *groupBase = &group;

        return testData == 0
            && testEventLoop == 0
            && groupBase->animationCount() == 1
            && groupBase->animationAt(0) == animation
            && groupBase->state() == QAbstractAnimation::Stopped;
    });
}
