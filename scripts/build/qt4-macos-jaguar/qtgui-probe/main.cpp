// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// QtGui probe for the Mac OS X 10.2 Jaguar port (milestone 3). Each check
// prints PASS or FAIL with a detail; the exit status is the failure count.
// Run it from a logged-in session: it opens a window for a few seconds.
#include <QtGui/QApplication>
#include <QtGui/QClipboard>
#include <QtGui/QFontDatabase>
#include <QtGui/QImage>
#include <QtGui/QLabel>
#include <QtGui/QLineEdit>
#include <QtGui/QPainter>
#include <QtGui/QPixmap>
#include <QtGui/QPushButton>
#include <QtGui/QStyle>
#include <QtGui/QVBoxLayout>
#include <QtGui/QWidget>
#include <QtCore/QSysInfo>
#include <QtCore/QTime>
#include <Carbon/Carbon.h>
#include <cstdio>
#include <cstring>

// The Jaguar shim in QtGui (qt_jaguar_mac.cpp); on 10.3 and later these
// call the Pasteboard and Drag Manager functions themselves.
extern "C" {
OSStatus qt_jaguar_PasteboardCreate(CFStringRef, PasteboardRef *);
OSStatus qt_jaguar_PasteboardClear(PasteboardRef);
OSStatus qt_jaguar_PasteboardPutItemFlavor(PasteboardRef, PasteboardItemID, CFStringRef, CFDataRef, PasteboardFlavorFlags);
OSStatus qt_jaguar_PasteboardCopyItemFlavorData(PasteboardRef, PasteboardItemID, CFStringRef, CFDataRef *);
OSStatus qt_jaguar_NewDragWithPasteboard(PasteboardRef, DragRef *);
OSStatus qt_jaguar_GetDragPasteboard(DragRef, PasteboardRef *);
OSErr qt_jaguar_DisposeDrag(DragRef);
}

// A drag made from a pasteboard: its text reaches the Drag Manager, and a
// drop in this process gets the pasteboard back with Qt's private flavor.
static bool checkDragPasteboard(QString &detail)
{
    PasteboardRef board = 0;
    if (qt_jaguar_PasteboardCreate(0, &board) != noErr || !board) {
        detail = QString::fromLatin1("no pasteboard");
        return false;
    }
    // As Qt does: a pasteboard must be cleared before data is put on it.
    qt_jaguar_PasteboardClear(board);
    const PasteboardItemID item = PasteboardItemID(1);
    CFDataRef text = CFDataCreate(0, reinterpret_cast<const UInt8 *>("jaguar-drag"), 11);
    qt_jaguar_PasteboardPutItemFlavor(board, item, CFSTR("com.apple.traditional-mac-plain-text"), text, 0);
    qt_jaguar_PasteboardPutItemFlavor(board, item, CFSTR("com.trolltech.anymime.qtkit-probe"), text, 0);
    CFRelease(text);
    DragRef drag = 0;
    bool ok = qt_jaguar_NewDragWithPasteboard(board, &drag) == noErr && drag;
    char buffer[32] = { 0 };
    Size size = sizeof(buffer) - 1;
    const bool viaDragManager = ok && GetFlavorData(drag, DragItemRef(1), 'TEXT', buffer, &size, 0) == noErr
        && size == 11 && !std::memcmp(buffer, "jaguar-drag", 11);
    PasteboardRef back = 0;
    CFDataRef privateData = 0;
    const bool viaPasteboard = ok && qt_jaguar_GetDragPasteboard(drag, &back) == noErr && back
        && qt_jaguar_PasteboardCopyItemFlavorData(back, item, CFSTR("com.trolltech.anymime.qtkit-probe"),
                                                  &privateData) == noErr
        && privateData && CFDataGetLength(privateData) == 11;
    if (privateData)
        CFRelease(privateData);
    if (drag)
        qt_jaguar_DisposeDrag(drag);
    CFRelease(board);
    detail = QString::fromLatin1("drag manager %1, pasteboard %2")
             .arg(viaDragManager ? "yes" : "no").arg(viaPasteboard ? "yes" : "no");
    // From 10.3 the Drag Manager may translate flavors lazily; only the
    // pasteboard path is required there.
    return viaPasteboard && (viaDragManager || QSysInfo::MacintoshVersion >= QSysInfo::MV_10_3);
}

static int failures = 0;

static void report(const char *name, bool ok, const QString &detail = QString())
{
    if (!ok)
        ++failures;
    std::printf("%s: %s%s%s\n", ok ? "PASS" : "FAIL", name,
                detail.isEmpty() ? "" : " - ", detail.toLocal8Bit().constData());
    std::fflush(stdout);
}

static void settle(int ms)
{
    QTime timer;
    timer.start();
    while (timer.elapsed() < ms)
        QApplication::processEvents(QEventLoop::AllEvents, 50);
}

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    report("sysinfo", true, QString::fromLatin1("MacintoshVersion=0x%1")
           .arg(int(QSysInfo::MacintoshVersion), 0, 16));
    report("style", app.style() != 0,
           app.style() ? QString::fromLatin1(app.style()->metaObject()->className()) : QString());

    QFontDatabase fonts;
    const QStringList families = fonts.families();
    report("fonts/families", families.size() > 3,
           QString::fromLatin1("%1 families, first %2").arg(families.size())
           .arg(families.isEmpty() ? QString() : families.first()));

    QImage image(64, 32, QImage::Format_ARGB32_Premultiplied);
    image.fill(0xffffffff);
    {
        QPainter p(&image);
        p.setRenderHint(QPainter::Antialiasing);
        p.fillRect(QRect(0, 0, 16, 32), Qt::red);
        p.setPen(QPen(Qt::blue, 3));
        p.drawLine(20, 2, 60, 30);
    }
    report("paint/raster-fill", image.pixel(4, 4) == qRgb(255, 0, 0),
           QString::number(image.pixel(4, 4), 16));

    QImage text(120, 40, QImage::Format_ARGB32_Premultiplied);
    text.fill(0xffffffff);
    {
        QPainter p(&text);
        p.setPen(Qt::black);
        p.setFont(QFont(QString::fromLatin1("Helvetica"), 18));
        p.drawText(text.rect(), Qt::AlignCenter, QString::fromLatin1("Jaguar"));
    }
    int dark = 0;
    for (int y = 0; y < text.height(); ++y)
        for (int x = 0; x < text.width(); ++x)
            if (qGray(text.pixel(x, y)) < 128)
                ++dark;
    report("paint/text-glyphs", dark > 30, QString::fromLatin1("%1 dark pixels").arg(dark));

    QWidget window;
    window.setWindowTitle(QString::fromLatin1("Qt 4.8.7 on Jaguar"));
    QVBoxLayout *layout = new QVBoxLayout(&window);
    QLabel *label = new QLabel(QString::fromLatin1("Hello from Qt 4.8.7"));
    QLineEdit *edit = new QLineEdit(QString::fromLatin1("editable"));
    QPushButton *button = new QPushButton(QString::fromLatin1("Push"));
    layout->addWidget(label);
    layout->addWidget(edit);
    layout->addWidget(button);
    window.resize(260, 140);
    // Right of a Terminal at the default position, so a screenshot shows it:
    // a process outside an application bundle cannot come to the front on 10.2.
    window.move(520, 150);
    window.show();
    settle(1500);
    report("widgets/shown", window.isVisible() && button->isVisible(),
           QString::fromLatin1("%1x%2").arg(window.width()).arg(window.height()));
    report("widgets/button-size", button->width() > 20 && button->height() > 10,
           QString::fromLatin1("%1x%2").arg(button->width()).arg(button->height()));

    const QPixmap grab = QPixmap::grabWidget(&window);
    const QImage grabbed = grab.toImage();
    report("widgets/grab", !grabbed.isNull() && grabbed.width() == window.width(),
           QString::fromLatin1("%1x%2").arg(grabbed.width()).arg(grabbed.height()));
    grabbed.save(QString::fromLatin1("/tmp/qtgui-grab.png"));
    const QList<QWidget *> children = window.findChildren<QWidget *>();
    for (int i = 0; i < children.size(); ++i) {
        const QWidget *child = children.at(i);
        std::printf("info: %s %d,%d %dx%d visible=%d hint=%dx%d\n", child->metaObject()->className(),
                    child->x(), child->y(), child->width(), child->height(), int(child->isVisible()),
                    child->sizeHint().width(), child->sizeHint().height());
    }

    button->setCheckable(true);
    button->click();
    report("widgets/click", button->isChecked());

    QClipboard *clipboard = QApplication::clipboard();
    // The run script copies this text with pbcopy before the probe starts
    // and checks with pbpaste afterwards that the probe's text arrived.
    const QByteArray expected = qgetenv("QTGUI_PROBE_CLIPBOARD");
    if (!expected.isEmpty())
        report("clipboard/system-import", clipboard->text() == QString::fromLatin1(expected), clipboard->text());
    clipboard->setText(QString::fromLatin1("qtkit-jaguar"));
    settle(200);
    report("clipboard/text-roundtrip", clipboard->text() == QLatin1String("qtkit-jaguar"),
           clipboard->text());

    // --hold keeps the window up for a screenshot.
    const int hold = app.arguments().indexOf(QString::fromLatin1("--hold"));
    if (hold > 0 && hold + 1 < app.arguments().size())
        settle(app.arguments().at(hold + 1).toInt() * 1000);
    QString dragDetail;
    const bool dragOk = checkDragPasteboard(dragDetail);
    report("dnd/drag-pasteboard", dragOk, dragDetail);

    window.close();
    settle(300);
    std::printf("---- qtgui-probe: %d failed ----\n", failures);
    return failures;
}
