// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

#include "../common/smokecheck.h"
#include "gallery.h"

#include <QAbstractPrintDialog>
#include <QAbstractTextDocumentLayout>
#include <QApplication>
#include <QColorDialog>
#include <QColormap>
#if QT_VERSION_MAJOR < 6
#include <QDesktopWidget>   // removed in Qt 6; QScreen is the replacement
#else
#include <QScreen>
#endif
#include <QDir>
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
// QT_CONFIG(opengl) alone is not the right question: Qt 6 has OpenGL and
// does not have the deprecated QGL* classes below.
#if QT_CONFIG(opengl) && QT_VERSION_MAJOR < 6
#include <QGLBuffer>
#include <QGLColormap>
#include <QGLContext>
#include <QGLFormat>
#include <QGLFramebufferObject>
#include <QGLFramebufferObjectFormat>
#include <QGLFunctions>
#include <QGLPixelBuffer>
#include <QGLShader>
#include <QGLShaderProgram>
#include <QGLWidget>
#endif
#include <QIconEngine>
#include <QIconEnginePlugin>
#include <QImageIOPlugin>
#include <QInputEvent>
#include <QItemEditorCreatorBase>
#include <QItemEditorFactory>
#include <QItemSelectionRange>
#include <QKeyEvent>
#include <QMimeData>
#include <QNativeGestureEvent>
#include <QPainter>
#include <QPaintEngine>
#include <QPanGesture>
#if QT_VERSION_MAJOR < 6
#include <QPictureFormatPlugin>   // both gone in Qt 6; QPicture stays
#include <QPictureIO>
#endif
#include <QPlainTextDocumentLayout>
#include <QPrintDialog>
#include <QPrintEngine>
#include <QPrinter>
#include <QScroller>
#include <QScrollerProperties>
#include <QStandardItemEditorCreator>
#include <QStandardItemModel>
#include <QStyleOptionGraphicsItem>
#include <QStyleOptionTab>

#if QT_VERSION_MAJOR >= 6
#include <QRhiWidget>
#include <QStyleOptionHeaderV2>
#endif
#include <QLineEdit>
#include <QKeyEventTransition>
#include <QMouseEventTransition>
#include <QSpinBox>
#include <QState>
#include <QStateMachine>
#include <QStylePlugin>
#include <QTableWidget>
#include <QTableWidgetSelectionRange>
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
#if QT_CONFIG(opengl)
#include <QOpenGLContext>
#include <QOpenGLWidget>
#include <QOpenGLWindow>
#endif
#include <QOperatingSystemVersion>
#include <QSharedPointer>
#if QT_VERSION_MAJOR < 6
#include <QTouchDevice>
#else
#include <QPointingDevice>   // QTouchDevice under its Qt 6 name
#endif
#include <QTouchEvent>
#include <QTreeWidget>
#include <QTreeWidgetItemIterator>
#include <QUrl>
#include <QWidgetAction>
#include <QWidgetItem>
#include <QWidgetItemV2>
#include <QTestData>
#include <QTestEventLoop>
#include <qpa/qplatformdialoghelper.h>
#include <qpa/qplatformdrag.h>

class QPlatformAccessibility;
class QPlatformBackingStore;
class QPlatformClipboard;
class QPlatformCursor;
class QPlatformCursorImage;
class QPlatformFontDatabase;
class QPlatformGraphicsBuffer;
class QPlatformInputContext;
class QPlatformIntegration;
class QPlatformIntegrationPlugin;
class QPlatformMenu;
class QPlatformMenuBar;
class QPlatformMenuItem;
class QPlatformNativeInterface;
class QPlatformOffscreenSurface;
class QPlatformOpenGLContext;
class QPlatformPixmap;
class QPlatformPlaceholderScreen;
class QPlatformScreen;
class QPlatformServices;
class QPlatformSessionManager;
class QPlatformSharedGraphicsCache;
class QPlatformSurface;
class QPlatformSystemTrayIcon;
class QPlatformTextureList;
class QPlatformTheme;
class QPlatformThemePlugin;
class QPlatformWindow;
class QWindowSystemInterface;

namespace {

bool isWindowsXpFamily()
{
#ifdef Q_OS_WIN
    const QOperatingSystemVersion current = QOperatingSystemVersion::current();
    return current.type() == QOperatingSystemVersion::Windows && current.majorVersion() <= 5;
#else
    return false;
#endif
}

class SmokePlatformColorDialogHelper : public QPlatformColorDialogHelper
{
public:
    void exec() override { executed = true; }
    bool show(Qt::WindowFlags windowFlags, Qt::WindowModality windowModality, QWindow *parent) override
    {
        Q_UNUSED(windowFlags);
        Q_UNUSED(windowModality);
        shown = true;
        parentWindow = parent;
        return true;
    }
    void hide() override { shown = false; }
    void setCurrentColor(const QColor &color) override { current = color; }
    QColor currentColor() const override { return current; }

    QColor current = Qt::black;
    QWindow *parentWindow = nullptr;
    bool executed = false;
    bool shown = false;
};

class SmokePlatformFontDialogHelper : public QPlatformFontDialogHelper
{
public:
    void exec() override { executed = true; }
    bool show(Qt::WindowFlags windowFlags, Qt::WindowModality windowModality, QWindow *parent) override
    {
        Q_UNUSED(windowFlags);
        Q_UNUSED(windowModality);
        shown = true;
        parentWindow = parent;
        return true;
    }
    void hide() override { shown = false; }
    void setCurrentFont(const QFont &font) override { current = font; }
    QFont currentFont() const override { return current; }

    QFont current;
    QWindow *parentWindow = nullptr;
    bool executed = false;
    bool shown = false;
};

class SmokePlatformFileDialogHelper : public QPlatformFileDialogHelper
{
public:
    void exec() override { executed = true; }
    bool show(Qt::WindowFlags windowFlags, Qt::WindowModality windowModality, QWindow *parent) override
    {
        Q_UNUSED(windowFlags);
        Q_UNUSED(windowModality);
        shown = true;
        parentWindow = parent;
        return true;
    }
    void hide() override { shown = false; }
    bool defaultNameFilterDisables() const override { return false; }
    void setDirectory(const QUrl &url) override { currentDirectory = url; }
    QUrl directory() const override { return currentDirectory; }
    void selectFile(const QUrl &url) override { files = QList<QUrl>() << url; }
    QList<QUrl> selectedFiles() const override { return files; }
    void setFilter() override { filterWasSet = true; }
    void selectNameFilter(const QString &filter) override { nameFilter = filter; }
    QString selectedNameFilter() const override { return nameFilter; }

    QList<QUrl> files;
    QUrl currentDirectory;
    QString nameFilter;
    QWindow *parentWindow = nullptr;
    bool executed = false;
    bool shown = false;
    bool filterWasSet = false;
};

class SmokePlatformMessageDialogHelper : public QPlatformMessageDialogHelper
{
public:
    void exec() override { executed = true; }
    bool show(Qt::WindowFlags windowFlags, Qt::WindowModality windowModality, QWindow *parent) override
    {
        Q_UNUSED(windowFlags);
        Q_UNUSED(windowModality);
        shown = true;
        parentWindow = parent;
        return true;
    }
    void hide() override { shown = false; }

    QWindow *parentWindow = nullptr;
    bool executed = false;
    bool shown = false;
};

class SmokeTextLayout : public QAbstractTextDocumentLayout
{
public:
    explicit SmokeTextLayout(QTextDocument *doc) : QAbstractTextDocumentLayout(doc) {}

    void draw(QPainter *, const PaintContext &) override {}
    int hitTest(const QPointF &, Qt::HitTestAccuracy) const override { return 0; }
    int pageCount() const override { return 1; }
    QSizeF documentSize() const override { return QSizeF(100, 20); }
    QRectF frameBoundingRect(QTextFrame *) const override { return QRectF(0, 0, 100, 20); }
    QRectF blockBoundingRect(const QTextBlock &) const override { return QRectF(0, 0, 100, 20); }
protected:
    void documentChanged(int, int, int) override {}
};

class SmokeTextObject : public QObject, public QTextObjectInterface
{
public:
    QSizeF intrinsicSize(QTextDocument *, int, const QTextFormat &) override { return QSizeF(4, 5); }
    void drawObject(QPainter *, const QRectF &, QTextDocument *, int, const QTextFormat &) override {}
};

class SmokeIconEngine : public QIconEngine
{
public:
    void paint(QPainter *painter, const QRect &rect, QIcon::Mode, QIcon::State) override
    {
        painter->fillRect(rect, Qt::blue);
    }
    QPixmap pixmap(const QSize &size, QIcon::Mode mode, QIcon::State state) override
    {
        QPixmap pm(size);
        pm.fill(Qt::transparent);
        QPainter painter(&pm);
        paint(&painter, QRect(QPoint(0, 0), size), mode, state);
        return pm;
    }
    QIconEngine *clone() const override { return new SmokeIconEngine; }
};

class SmokeIconEnginePlugin : public QIconEnginePlugin
{
public:
    QIconEngine *create(const QString &) override { return new SmokeIconEngine; }
};

class SmokeImagePlugin : public QImageIOPlugin
{
public:
    Capabilities capabilities(QIODevice *, const QByteArray &format) const override
    {
        return format == QByteArrayLiteral("smoke") ? CanRead : Capabilities();
    }
    QImageIOHandler *create(QIODevice *, const QByteArray &) const override { return nullptr; }
};

#if QT_VERSION_MAJOR < 6
// QPictureFormatPlugin and QPictureIO went with Qt 6's image-plugin rework.
// QPicture itself survives and is covered elsewhere in this file.
class SmokePicturePlugin : public QPictureFormatPlugin
{
public:
    bool loadPicture(const QString &, const QString &, QPicture *) override { return false; }
    bool savePicture(const QString &, const QString &, const QPicture &) override { return false; }
    bool installIOHandler(const QString &) override { return false; }
};
#endif

class SmokeGestureRecognizer : public QGestureRecognizer
{
public:
    QGesture *create(QObject *) override { return new QPanGesture; }
    Result recognize(QGesture *, QObject *, QEvent *) override { return Ignore; }
    void reset(QGesture *gesture) override { QGestureRecognizer::reset(gesture); }
};

class SmokeFrameLayoutData : public QTextFrameLayoutData
{
public:
    ~SmokeFrameLayoutData() override = default;
};

class SmokeStylePlugin : public QStylePlugin
{
public:
    QStyle *create(const QString &) override { return nullptr; }
};

#if QT_VERSION_MAJOR >= 6
// QRhiWidget is the widget counterpart of QQuickRhiItem: a QWidget that renders
// with QRhi into a texture the widget compositor then draws. Neither hook is
// pure virtual - the base draws nothing - but overriding them is the whole
// point of the class, and a widget that is never shown is never asked to.
class SmokeRhiWidget : public QRhiWidget
{
public:
    using QRhiWidget::QRhiWidget;
    // Protected on the base: whether Qt supplies the render target or the
    // subclass builds its own is a decision only the subclass can make, so the
    // setter is only reachable from inside one.
    using QRhiWidget::isAutoRenderTargetEnabled;
    using QRhiWidget::setAutoRenderTarget;

protected:
    void initialize(QRhiCommandBuffer *) override { ++initializes; }
    void render(QRhiCommandBuffer *) override { ++renders; }
    void releaseResources() override { ++releases; }

public:
    int initializes = 0;
    int renders = 0;
    int releases = 0;
};
#endif

} // namespace

void checkQtBaseWidgetsTail2(SmokeReporter &r)
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
#if QT_VERSION_MAJOR < 6
        QDesktopWidget *desktop = QApplication::desktop();
#else
        QScreen *desktop = QGuiApplication::primaryScreen();
#endif

        QPrinter printer;
        QPrintDialog printDialog(&printer);
        QAbstractPrintDialog *abstractPrintDialog = &printDialog;
        abstractPrintDialog->setPrintRange(QAbstractPrintDialog::PageRange);
        abstractPrintDialog->setFromTo(1, 2);

        return fileDialog.testOption(QFileDialog::DontUseNativeDialog)
            && fileDialog.fileMode() == QFileDialog::ExistingFiles
            && colorDialog.testOption(QColorDialog::ShowAlphaChannel)
            && fontDialog.testOption(QFontDialog::DontUseNativeDialog)
            && desktop != nullptr
            && abstractPrintDialog->printRange() == QAbstractPrintDialog::PageRange
            && abstractPrintDialog->fromPage() == 1
            && abstractPrintDialog->toPage() == 2;
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
        return editor != nullptr
            && factory.valuePropertyName(QVariant::Int) == QByteArrayLiteral("value")
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
        SmokeTextLayout layout(&doc);
        QAbstractTextDocumentLayout *abstractLayout = &layout;
        QPlainTextDocumentLayout plainLayout(&plainDoc);
        SmokeTextObject objectHandler;
        QAbstractTextDocumentLayout::PaintContext context;
        QAbstractTextDocumentLayout::Selection selection;
        selection.cursor = QTextCursor(&doc);
        context.selections.append(selection);
        QTextBlock firstBlock = doc.firstBlock();
        auto *userData = new QTextBlockUserData;
        firstBlock.setUserData(userData);
        QTextBlockGroup *blockGroup = nullptr;
        QTextFrame *frame = doc.rootFrame();
        QTextObjectInterface *handler = &objectHandler;
        const QSizeF objectSize = handler->intrinsicSize(&doc, 0, QTextFormat());
        QTextInlineObject inlineObject;
        Q_UNUSED(inlineObject);
        QStringList misses;
        if (abstractLayout->documentSize() != QSizeF(100, 20)) misses << QStringLiteral("document-size");
        if (plainLayout.document() != &plainDoc) misses << QStringLiteral("plain-layout");
        if (context.selections.size() != 1) misses << QStringLiteral("selection");
        if (firstBlock.userData() != userData) misses << QStringLiteral("userdata");
        if (blockGroup != nullptr) misses << QStringLiteral("blockgroup");
        if (frame == nullptr) misses << QStringLiteral("frame");
        if (handler != &objectHandler) misses << QStringLiteral("handler");
        if (objectSize != QSizeF(4, 5)) misses << QStringLiteral("object-size");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
    });

    r.check("qtbase/scroller-icon-plugin-picture-drag", [&](QString &d) {
        QWidget host;
        QScroller *scroller = QScroller::scroller(&host);
        QScrollerProperties properties = scroller->scrollerProperties();
        properties.setScrollMetric(QScrollerProperties::DragStartDistance, 0.01);
        scroller->setScrollerProperties(properties);

        QDrag drag(&host);
        auto *mime = new QMimeData;
        mime->setText(QStringLiteral("payload"));
        drag.setMimeData(mime);

        auto *engine = new SmokeIconEngine;
        QIcon icon(engine);
        QIconEngine *engineClone = (new SmokeIconEngine)->clone();
        SmokeIconEnginePlugin iconPlugin;
        QIconEnginePlugin *iconPluginBase = &iconPlugin;
        SmokeImagePlugin imagePlugin;
        QImageIOPlugin *imagePluginBase = &imagePlugin;
#if QT_VERSION_MAJOR < 6
        SmokePicturePlugin picturePlugin;
        QPictureFormatPlugin *picturePluginBase = &picturePlugin;
        QPictureIO pictureIo;
        pictureIo.setFormat("smoke");
#endif

        QIconEngine *pluginEngine = iconPluginBase->create(QStringLiteral("smoke"));

        bool ok = scroller->target() == &host
            && scroller->scrollerProperties().scrollMetric(QScrollerProperties::DragStartDistance).toDouble() == 0.01
            && drag.mimeData()->text() == QStringLiteral("payload")
            && !icon.pixmap(4, 4).isNull()
            && engineClone != nullptr
            && pluginEngine != nullptr
            && imagePluginBase->capabilities(nullptr, QByteArrayLiteral("smoke")).testFlag(QImageIOPlugin::CanRead)
#if QT_VERSION_MAJOR < 6
            && picturePluginBase->installIOHandler(QStringLiteral("smoke")) == false
            && QByteArray(pictureIo.format()) == QByteArrayLiteral("smoke")
#endif
            ;
        delete engineClone;
        delete pluginEngine;
        return ok;
    });

    r.check("qtbase/tree-iterator-widget-action-style-tail", [&](QString &d) {
        QTreeWidget tree;
        tree.setColumnCount(1);
        new QTreeWidgetItem(&tree, QStringList() << QStringLiteral("root"));
        QTreeWidgetItemIterator it(&tree);
        QWidget host;
        QWidgetAction widgetAction(&host);
        auto *lineEdit = new QLineEdit;
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
        QKeyEvent keyEvent(QEvent::KeyPress, Qt::Key_A, Qt::ControlModifier, QStringLiteral("a"));
        QInputEvent *inputEvent = &keyEvent;

#if QT_VERSION_MAJOR < 6
        QTouchDevice touchDevice;
        touchDevice.setName(QStringLiteral("smoke-touch"));
        touchDevice.setType(QTouchDevice::TouchScreen);
        touchDevice.setCapabilities(QTouchDevice::Position);
        touchDevice.setMaximumTouchPoints(1);
#else
        // Qt 6 describes the device at construction rather than through setters.
        QPointingDevice touchDevice(QStringLiteral("smoke-touch"), 1,
                                    QInputDevice::DeviceType::TouchScreen,
                                    QPointingDevice::PointerType::Finger,
                                    QInputDevice::Capability::Position, 1, 0);
#endif
        QTouchEvent::TouchPoint touchPoint(1);
        QPointingDeviceUniqueId pointingId = QPointingDeviceUniqueId::fromNumericId(11);
#if QT_VERSION_MAJOR < 6
        QTouchEvent touchEvent(QEvent::TouchBegin, &touchDevice, Qt::NoModifier,
                               Qt::TouchPointPressed, QList<QTouchEvent::TouchPoint>() << touchPoint);
        QNativeGestureEvent nativeGesture(Qt::ZoomNativeGesture, &touchDevice,
                                          QPointF(1, 2), QPointF(1, 2), QPointF(1, 2),
                                          1.5, 7, 0);
#else
        // Qt 6 keeps the state on each QEventPoint instead of on the event, and
        // QNativeGestureEvent carries a finger count and a QPointF delta.
        QTouchEvent touchEvent(QEvent::TouchBegin, &touchDevice, Qt::NoModifier,
                               QList<QEventPoint>() << touchPoint);
        QNativeGestureEvent nativeGesture(Qt::ZoomNativeGesture, &touchDevice, 1,
                                          QPointF(1, 2), QPointF(1, 2), QPointF(1, 2),
                                          1.5, QPointF(0, 0), 7);
#endif

        QPanGesture panGesture;
        QList<QGesture *> gestures;
        gestures << &panGesture;
        QGestureEvent gestureEvent(gestures);
        QWidget widget;
        gestureEvent.setWidget(&widget);
        SmokeGestureRecognizer recognizer;
        QGestureRecognizer *recognizerBase = &recognizer;
        QGesture *createdGesture = recognizerBase->create(&widget);

        QGlyphRun glyphRun;
        glyphRun.setGlyphIndexes(QVector<quint32>() << 1 << 2);
        glyphRun.setPositions(QVector<QPointF>() << QPointF(0, 0) << QPointF(5, 0));
        glyphRun.setUnderline(true);
        QTextFragment fragment;

        bool ok = inputEvent->modifiers() == Qt::ControlModifier
#if QT_VERSION_MAJOR < 6
            && touchDevice.maximumTouchPoints() == 1
#else
            && touchDevice.maximumPoints() == 1
#endif
            && pointingId.isValid()
            && pointingId.numericId() == 11
            && touchEvent.device() == &touchDevice
            && touchEvent.touchPoints().size() == 1
            && nativeGesture.gestureType() == Qt::ZoomNativeGesture
            && qFuzzyCompare(nativeGesture.value(), qreal(1.5))
            && gestureEvent.gesture(Qt::PanGesture) == &panGesture
            && gestureEvent.widget() == &widget
            && createdGesture != nullptr
            && glyphRun.glyphIndexes().size() == 2
            && glyphRun.underline()
            && !fragment.isValid();
        delete createdGesture;
        return ok;
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

        SmokeStylePlugin stylePlugin;
        QStylePlugin *stylePluginBase = &stylePlugin;
#if QT_VERSION_MAJOR < 6
        QStyleOptionTabV4 tabOptionV4;
#else
        QStyleOptionTab tabOptionV4;   // V4 folded into the base in Qt 6
#endif
        tabOptionV4.tabIndex = 3;

        QWidget widget;
        QWidgetItemV2 widgetItem(&widget);
        QWidgetItem *widgetItemBase = &widgetItem;

        QTextDocument doc(QStringLiteral("layout-data"));
        QTextFrame *frame = doc.rootFrame();
        auto *layoutData = new SmokeFrameLayoutData;
        frame->setLayoutData(layoutData);
        QTextItem *textItem = nullptr;
        QImage image(4, 4, QImage::Format_ARGB32_Premultiplied);
        QPaintEngine *paintEngine = image.paintEngine();
        QPaintEngineState *paintEngineState = nullptr;
        QPrinter printer;
        QPrintEngine *printEngine = printer.printEngine();
        QColormap colormap = QColormap::instance();

        return keyTransition.key() == Qt::Key_A
            && keyTransition.modifierMask() == Qt::ControlModifier
            && keyTransition.targetState() == &target
            && mouseTransition.button() == Qt::LeftButton
            && mouseTransition.modifierMask() == Qt::ShiftModifier
            && stylePluginBase->create(QStringLiteral("missing")) == nullptr
            && tabOptionV4.tabIndex == 3
            && widgetItemBase->widget() == &widget
            && frame->layoutData() == layoutData
            && textItem == nullptr
            && paintEngine != nullptr
            && paintEngineState == nullptr
            && printEngine != nullptr
            && colormap.depth() >= 0;
    });

// The body below is the deprecated QGL* API, which Qt 6 does not have -
// QT_CONFIG(opengl) alone would still be true there.
#if QT_CONFIG(opengl) && QT_VERSION_MAJOR < 6
    r.check("qtbase/qgl-and-testlib-shells", [&](QString &d) {
        QGLFormat glFormat;
        glFormat.setVersion(2, 1);
        glFormat.setSampleBuffers(true);
        QGLColormap glColormap;
        QGLContext *glContext = nullptr;
        QGLBuffer glBuffer(QGLBuffer::VertexBuffer);
        QGLFramebufferObject *glFramebufferObject = nullptr;
        QGLFramebufferObjectFormat glFramebufferFormat;
        glFramebufferFormat.setAttachment(QGLFramebufferObject::CombinedDepthStencil);
        QGLFunctions *glFunctions = nullptr;
        QGLPixelBuffer *glPixelBuffer = nullptr;
        QGLShader *glShader = nullptr;
        QGLShaderProgram glShaderProgram;
        QGLWidget *glWidget = nullptr;

        QAbstractOpenGLFunctions *abstractOpenGLFunctions = nullptr;
        QOpenGLContextGroup *contextGroup = nullptr;
        QOpenGLWidget *openGLWidget = nullptr;
        QOpenGLWindow *openGLWindow = nullptr;
        QTestData *testData = nullptr;
        QTestEventLoop *testEventLoop = nullptr;

        return glFormat.majorVersion() == 2
            && glFormat.minorVersion() == 1
            && glFormat.sampleBuffers()
            && glColormap.isEmpty()
            && glContext == nullptr
            && !glBuffer.isCreated()
            && glFramebufferObject == nullptr
            && glFramebufferFormat.attachment() == QGLFramebufferObject::CombinedDepthStencil
            && glFunctions == nullptr
            && glPixelBuffer == nullptr
            && glShader == nullptr
            && !glShaderProgram.isLinked()
            && glWidget == nullptr
            && abstractOpenGLFunctions == nullptr
            && contextGroup == nullptr
            && openGLWidget == nullptr
            && openGLWindow == nullptr
            && testData == nullptr
            && testEventLoop == nullptr;
    });
#else
    // QtOpenGL (the deprecated QGL* classes) and QOpenGLWidget/QOpenGLWindow
    // only exist when Qt was configured with desktop OpenGL. Report the gap
    // rather than dropping the check silently.
    r.check("qtbase/qgl-and-testlib-shells", [&](QString &d) {
        r.skip(d, QStringLiteral("Qt was configured without desktop OpenGL"));
        return false;
    });
#endif

    r.check("qtbase/win7plus-qpa-dialog-helpers", [&](QString &d) {
        if (isWindowsXpFamily()) {
            r.skip(d, QStringLiteral("QPA dialog helper runtime is covered on Win7+ only"));
            return false;
        }

        QSharedPointer<QColorDialogOptions> colorOptions = QColorDialogOptions::create();
        colorOptions->setWindowTitle(QStringLiteral("Color"));
        colorOptions->setOption(QColorDialogOptions::ShowAlphaChannel);
        QSharedPointer<QFontDialogOptions> fontOptions = QFontDialogOptions::create();
        fontOptions->setWindowTitle(QStringLiteral("Font"));
        fontOptions->setOption(QFontDialogOptions::ScalableFonts);
        QSharedPointer<QFileDialogOptions> fileOptions = QFileDialogOptions::create();
        fileOptions->setWindowTitle(QStringLiteral("File"));
        fileOptions->setFileMode(QFileDialogOptions::ExistingFiles);
        fileOptions->setAcceptMode(QFileDialogOptions::AcceptOpen);
        fileOptions->setInitialDirectory(QUrl::fromLocalFile(QDir::tempPath()));
        fileOptions->setNameFilters(QStringList() << QStringLiteral("Text (*.txt)"));
        QSharedPointer<QMessageDialogOptions> messageOptions = QMessageDialogOptions::create();
        messageOptions->setWindowTitle(QStringLiteral("Message"));
#if QT_VERSION_MAJOR < 6
        messageOptions->setIcon(QMessageDialogOptions::Information);
#else
        messageOptions->setStandardIcon(QMessageDialogOptions::Information);
#endif
        messageOptions->setText(QStringLiteral("Body"));
        QPlatformDialogHelper::StandardButtons messageButtons(QPlatformDialogHelper::Ok);
        messageButtons |= QPlatformDialogHelper::Cancel;
        messageOptions->setStandardButtons(messageButtons);

        SmokePlatformColorDialogHelper colorHelper;
        colorHelper.setOptions(colorOptions);
        colorHelper.setCurrentColor(Qt::red);
        SmokePlatformFontDialogHelper fontHelper;
        fontHelper.setOptions(fontOptions);
        fontHelper.setCurrentFont(QFont(QStringLiteral("Arial"), 10));
        SmokePlatformFileDialogHelper fileHelper;
        fileHelper.setOptions(fileOptions);
        fileHelper.setDirectory(QUrl::fromLocalFile(QDir::tempPath()));
        fileHelper.selectFile(QUrl::fromLocalFile(QDir::temp().filePath(QStringLiteral("smoke.txt"))));
        fileHelper.selectNameFilter(QStringLiteral("Text (*.txt)"));
        fileHelper.setFilter();
        SmokePlatformMessageDialogHelper messageHelper;
        messageHelper.setOptions(messageOptions);
        QPlatformDialogHelper *helperBase = &messageHelper;
        helperBase->show(Qt::Dialog, Qt::ApplicationModal, nullptr);
        helperBase->hide();

        const int *buttonLayout = QPlatformDialogHelper::buttonLayout(Qt::Horizontal,
                                                                      QPlatformDialogHelper::WinLayout);
        return colorOptions->testOption(QColorDialogOptions::ShowAlphaChannel)
            && colorOptions->clone()->windowTitle() == QStringLiteral("Color")
            && fontOptions->testOption(QFontDialogOptions::ScalableFonts)
            && fontOptions->clone()->windowTitle() == QStringLiteral("Font")
            && fileOptions->fileMode() == QFileDialogOptions::ExistingFiles
            && fileOptions->acceptMode() == QFileDialogOptions::AcceptOpen
            && fileOptions->initialDirectory().isLocalFile()
            && fileOptions->nameFilters().size() == 1
#if QT_VERSION_MAJOR < 6
            && messageOptions->icon() == QMessageDialogOptions::Information
#else
            && messageOptions->standardIcon() == QMessageDialogOptions::Information
#endif
            && messageOptions->standardButtons().testFlag(QPlatformDialogHelper::Ok)
            && QPlatformDialogHelper::buttonRole(QPlatformDialogHelper::Ok) == QPlatformDialogHelper::AcceptRole
            && buttonLayout != nullptr
            && colorHelper.options() == colorOptions
            && colorHelper.currentColor() == QColor(Qt::red)
            && fontHelper.options() == fontOptions
            && fontHelper.currentFont().family() == QStringLiteral("Arial")
            && fileHelper.options() == fileOptions
            && fileHelper.directory().isLocalFile()
            && fileHelper.selectedFiles().size() == 1
            && fileHelper.selectedNameFilter() == QStringLiteral("Text (*.txt)")
            && fileHelper.filterWasSet
            && messageHelper.options() == messageOptions
            && !messageHelper.shown;
    });

    r.check("qtbase/win7plus-qpa-interface-shells", [&](QString &d) {
        if (isWindowsXpFamily()) {
            r.skip(d, QStringLiteral("QPA interface shells are covered on Win7+ only"));
            return false;
        }

        QPlatformDropQtResponse dropResponse(true, Qt::CopyAction);
        QPlatformDragQtResponse dragResponse(true, Qt::MoveAction, QRect(1, 2, 3, 4));
        QPlatformAccessibility *platformAccessibility = nullptr;
        QPlatformBackingStore *platformBackingStore = nullptr;
        QPlatformClipboard *platformClipboard = nullptr;
        QPlatformCursor *platformCursor = nullptr;
        QPlatformCursorImage *platformCursorImage = nullptr;
        QPlatformFontDatabase *platformFontDatabase = nullptr;
        QPlatformGraphicsBuffer *platformGraphicsBuffer = nullptr;
        QPlatformInputContext *platformInputContext = nullptr;
        QPlatformIntegration *platformIntegration = nullptr;
        QPlatformIntegrationPlugin *platformIntegrationPlugin = nullptr;
        QPlatformMenu *platformMenu = nullptr;
        QPlatformMenuBar *platformMenuBar = nullptr;
        QPlatformMenuItem *platformMenuItem = nullptr;
        QPlatformNativeInterface *platformNativeInterface = nullptr;
        QPlatformOffscreenSurface *platformOffscreenSurface = nullptr;
        QPlatformOpenGLContext *platformOpenGLContext = nullptr;
        QPlatformPixmap *platformPixmap = nullptr;
        QPlatformPlaceholderScreen *platformPlaceholderScreen = nullptr;
        QPlatformScreen *platformScreen = nullptr;
        QPlatformServices *platformServices = nullptr;
        QPlatformSessionManager *platformSessionManager = nullptr;
        QPlatformSharedGraphicsCache *platformSharedGraphicsCache = nullptr;
        QPlatformSurface *platformSurface = nullptr;
        QPlatformSystemTrayIcon *platformSystemTrayIcon = nullptr;
        QPlatformTextureList *platformTextureList = nullptr;
        QPlatformTheme *platformTheme = nullptr;
        QPlatformThemePlugin *platformThemePlugin = nullptr;
        QPlatformWindow *platformWindow = nullptr;
        QWindowSystemInterface *windowSystemInterface = nullptr;

        return dropResponse.isAccepted()
            && dropResponse.acceptedAction() == Qt::CopyAction
            && dragResponse.answerRect() == QRect(1, 2, 3, 4)
            && dragResponse.acceptedAction() == Qt::MoveAction
            && platformAccessibility == nullptr
            && platformBackingStore == nullptr
            && platformClipboard == nullptr
            && platformCursor == nullptr
            && platformCursorImage == nullptr
            && platformFontDatabase == nullptr
            && platformGraphicsBuffer == nullptr
            && platformInputContext == nullptr
            && platformIntegration == nullptr
            && platformIntegrationPlugin == nullptr
            && platformMenu == nullptr
            && platformMenuBar == nullptr
            && platformMenuItem == nullptr
            && platformNativeInterface == nullptr
            && platformOffscreenSurface == nullptr
            && platformOpenGLContext == nullptr
            && platformPixmap == nullptr
            && platformPlaceholderScreen == nullptr
            && platformScreen == nullptr
            && platformServices == nullptr
            && platformSessionManager == nullptr
            && platformSharedGraphicsCache == nullptr
            && platformSurface == nullptr
            && platformSystemTrayIcon == nullptr
            && platformTextureList == nullptr
            && platformTheme == nullptr
            && platformThemePlugin == nullptr
            && platformWindow == nullptr
            && windowSystemInterface == nullptr;
    });

    r.check("qtbase/header-v2-option-and-rhi-widget", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        // Qt 6.5 added a second version of the header style option rather than
        // adding fields to the first, because QStyleOption subclasses are
        // copied by value into styles that may be older than the caller. The
        // version constant is how a style tells the two apart.
        QStyleOptionHeaderV2 headerOption;
        headerOption.section = 3;
        headerOption.text = QStringLiteral("qt-smoke");
        headerOption.textElideMode = Qt::ElideMiddle;
        headerOption.isSectionDragTarget = true;

        // Sliced to the base on purpose: this is what a style that predates V2
        // sees, and the check is that the shared fields survive it.
        const QStyleOptionHeader &asV1 = headerOption;

        SmokeRhiWidget rhiWidget;
        rhiWidget.setApi(QRhiWidget::Api::Null);
        rhiWidget.setSampleCount(1);
        rhiWidget.setColorBufferFormat(QRhiWidget::TextureFormat::RGBA8);
        rhiWidget.setFixedColorBufferSize(96, 48);
        rhiWidget.setMirrorVertically(true);
        rhiWidget.setAutoRenderTarget(false);
        QWidget *asWidget = &rhiWidget;

        QStringList misses;
        if (headerOption.version != QStyleOptionHeaderV2::Version)
            misses << QStringLiteral("v2-version");
        if (QStyleOptionHeaderV2::Type != QStyleOption::SO_Header)
            misses << QStringLiteral("v2-type");
        if (headerOption.textElideMode != Qt::ElideMiddle) misses << QStringLiteral("elide");
        if (!headerOption.isSectionDragTarget) misses << QStringLiteral("dragtarget");
        if (asV1.section != 3 || asV1.text != QStringLiteral("qt-smoke"))
            misses << QStringLiteral("sliced");
        if (rhiWidget.api() != QRhiWidget::Api::Null) misses << QStringLiteral("api");
        if (rhiWidget.sampleCount() != 1) misses << QStringLiteral("samplecount");
        if (rhiWidget.fixedColorBufferSize() != QSize(96, 48))
            misses << QStringLiteral("fixedsize");
        if (!rhiWidget.isMirrorVerticallyEnabled()) misses << QStringLiteral("mirror");
        if (rhiWidget.isAutoRenderTargetEnabled()) misses << QStringLiteral("autorendertarget");
        if (!asWidget) misses << QStringLiteral("as-widget");
        // Never shown, so the render hooks are never called - which is what
        // makes constructing one safe with no GPU present.
        if (rhiWidget.initializes != 0 || rhiWidget.renders != 0)
            misses << QStringLiteral("unexpected-render");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QStyleOptionHeaderV2 and QRhiWidget are Qt 6 only"));
        return false;
#endif
    });
}
