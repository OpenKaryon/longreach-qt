// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// painting-lab - focused raster/text/alpha/print-preview smoke app.
#include "../common/smokecheck.h"
#include "../common/crashinfo.h"

#include <QApplication>
#include <QBuffer>
#include <QFontComboBox>
#include <QFontMetrics>
#include <QGradient>
#include <QGridLayout>
#include <QGroupBox>
#include <QImage>
#include <QLabel>
#include <QMainWindow>
#include <QPainter>
#include <QPainterPath>
#include <QPaintEvent>
#include <QPixmap>
#ifndef QT_NO_PRINTER
#include <QPrinter>
#include <QPrinterInfo>
#ifndef QT_NO_PRINTDIALOG
#include <QPrintDialog>
#include <QPageSetupDialog>
#endif
#ifndef QT_NO_PRINTPREVIEWDIALOG
#include <QPrintPreviewDialog>
#endif
#ifndef QT_NO_PRINTPREVIEWWIDGET
#include <QPrintPreviewWidget>
#endif
#endif
#include <QPushButton>
#include <QStatusBar>
#include <QSvgRenderer>
#include <QTabWidget>
#include <QTemporaryFile>
#include <QTextEdit>
#include <QTextDocument>
#include <QTimer>
#include <QEventLoop>
#include <QDir>
#include <QFile>
#include <QVBoxLayout>
#if defined(Q_OS_WIN) && !defined(QT_NO_PRINTDIALOG)
#include <qt_windows.h>
#include <cstring>
#endif

#ifndef QT_NO_PRINTER
static bool paintPrintPage(QPrinter *printer)
{
    QPainter p;
    if (!p.begin(printer)) return false;
    p.drawText(QRect(100, 100, 500, 200), Qt::TextWordWrap,
               QStringLiteral("Print preview smoke\nText, metrics and printer paint engine."));
    p.drawRect(100, 340, 300, 180);
    return p.end();
}
#endif

class PaintingLabConnections : public QObject
{
    Q_OBJECT

public:
    PaintingLabConnections(QTextEdit *sample, QLabel *metrics, QObject *parent)
        : QObject(parent), sample_(sample), metrics_(metrics) {}

public slots:
    void selectFont(const QFont &font)
    {
        QFont displayFont = font;
        displayFont.setPointSize(12);
        sample_->setFont(displayFont);
        const QFontMetrics fm(font);
        metrics_->setText(QStringLiteral("height=%1 ascent=%2 averageWidth=%3")
                          .arg(fm.height()).arg(fm.ascent()).arg(fm.averageCharWidth()));
    }

#ifndef QT_NO_PRINTER
    void paintPreview(QPrinter *printer) { paintPrintPage(printer); }
#endif

private:
    QTextEdit *sample_;
    QLabel *metrics_;
};

#if defined(Q_OS_WIN) && !defined(QT_NO_PRINTER) && !defined(QT_NO_PRINTDIALOG)
// Drives a native print dialog of the GUI thread; never submits a job to
// a printer.
class NativePrintDialogDriver : public QObject
{
    Q_OBJECT
public:
    explicit NativePrintDialogDriver(int command) : command_(command), observed_(false)
    {
        timer_.setInterval(80);
        QObject::connect(&timer_, SIGNAL(timeout()), this, SLOT(tick()));
        timer_.start();
    }
    bool observed() const { return observed_; }
public slots:
    void tick()
    {
        EnumThreadWindows(GetCurrentThreadId(), findDialog, reinterpret_cast<LPARAM>(this));
    }
private:
    static BOOL CALLBACK findDialog(HWND window, LPARAM context)
    {
        NativePrintDialogDriver *driver = reinterpret_cast<NativePrintDialogDriver *>(context);
        char name[32] = {};
        GetClassNameA(window, name, sizeof(name));
        if (!IsWindowVisible(window) || std::strcmp(name, "#32770") != 0
                || !GetDlgItem(window, driver->command_)) return TRUE;
        driver->observed_ = true;
        driver->timer_.stop();
        PostMessageA(window, WM_COMMAND, driver->command_, 0);
        return FALSE;
    }
    int command_;
    bool observed_;
    QTimer timer_;
};
#endif

class PaintCanvas : public QWidget
{
public:
    explicit PaintCanvas(QWidget *parent = nullptr) : QWidget(parent)
    {
        setMinimumSize(520, 360);
    }

protected:
    void paintEvent(QPaintEvent *) override
    {
        QPainter p(this);
        p.fillRect(rect(), QColor(250, 250, 250));
        p.setRenderHint(QPainter::Antialiasing);

        QLinearGradient gradient(0, 0, width(), 0);
        gradient.setColorAt(0, QColor(40, 110, 180));
        gradient.setColorAt(0.5, QColor(230, 230, 240));
        gradient.setColorAt(1, QColor(180, 80, 60));
        p.fillRect(QRect(20, 20, width() - 40, 70), gradient);

        p.setPen(QPen(Qt::black, 2));
        p.setBrush(QColor(255, 255, 255, 170));
        p.drawRoundedRect(QRect(40, 50, 180, 90), 8, 8);

        QPainterPath path;
        path.moveTo(260, 120);
        path.cubicTo(320, 20, 420, 220, 500, 80);
        p.setPen(QPen(QColor(20, 90, 120), 4));
        p.drawPath(path);

        QImage alpha(120, 120, QImage::Format_ARGB32_Premultiplied);
        alpha.fill(0);
        QPainter alphaPainter(&alpha);
        alphaPainter.setRenderHint(QPainter::Antialiasing);
        alphaPainter.setBrush(QColor(30, 150, 90, 180));
        alphaPainter.drawEllipse(10, 10, 80, 80);
        alphaPainter.setBrush(QColor(200, 40, 80, 150));
        alphaPainter.drawEllipse(45, 35, 70, 70);
        alphaPainter.end();
        p.drawImage(50, 190, alpha);

        p.setPen(Qt::black);
        QFont f = font();
        f.setPointSize(14);
        p.setFont(f);
        p.drawText(QRect(190, 190, width() - 220, 90),
                   Qt::AlignLeft | Qt::TextWordWrap,
                   QStringLiteral("Text: Latin, Cyrillic, CJK, 12345, symbols <> &"));
    }
};

static QWidget *makeCanvasTab()
{
    auto *w = new QWidget;
    auto *layout = new QVBoxLayout(w);
    layout->addWidget(new PaintCanvas);
    return w;
}

static QWidget *makeTextTab()
{
    auto *w = new QWidget;
    auto *layout = new QVBoxLayout(w);
    auto *combo = new QFontComboBox;
    auto *sample = new QTextEdit;
    sample->setPlainText(QString::fromUtf8("Font smoke\nLatin ABC xyz\nKazakh: Сәлем, әлем\nCJK: 世界\n0123456789"));
    layout->addWidget(combo);
    layout->addWidget(sample);
    auto *metrics = new QLabel;
    auto *connections = new PaintingLabConnections(sample, metrics, w);
    QObject::connect(combo, SIGNAL(currentFontChanged(QFont)),
                     connections, SLOT(selectFont(QFont)));
    combo->setCurrentFont(QApplication::font());
    connections->selectFont(combo->currentFont());
    layout->addWidget(metrics);
    return w;
}

static QWidget *makeImagesTab()
{
    auto *w = new QWidget;
    auto *grid = new QGridLayout(w);
    QImage img(180, 120, QImage::Format_ARGB32_Premultiplied);
    img.fill(0);
    QPainter p(&img);
    p.fillRect(0, 0, 180, 120, QColor(245, 245, 245));
    p.setBrush(QColor(40, 100, 180, 180));
    p.drawRect(20, 20, 80, 70);
    p.setBrush(QColor(180, 80, 50, 150));
    p.drawEllipse(70, 35, 80, 60);
    p.end();
    auto *imageLabel = new QLabel;
    imageLabel->setPixmap(QPixmap::fromImage(img));
    grid->addWidget(imageLabel, 0, 0);

    QByteArray svg("<svg xmlns='http://www.w3.org/2000/svg' width='180' height='120'>"
                   "<rect width='180' height='120' fill='#f8f8f8'/>"
                   "<circle cx='70' cy='60' r='45' fill='#2870b8'/>"
                   "<text x='45' y='68' font-size='24' fill='white'>SVG</text></svg>");
    QSvgRenderer renderer(svg);
    QPixmap svgPixmap(180, 120);
    svgPixmap.fill(Qt::transparent);
    QPainter svgPainter(&svgPixmap);
    renderer.render(&svgPainter);
    auto *svgLabel = new QLabel;
    svgLabel->setPixmap(svgPixmap);
    grid->addWidget(svgLabel, 0, 1);
    return w;
}

static QWidget *makePrintTab()
{
#if !defined(QT_NO_PRINTER) && !defined(QT_NO_PRINTPREVIEWWIDGET)
    auto *preview = new QPrintPreviewWidget;
    auto *connections = new PaintingLabConnections(nullptr, nullptr, preview);
    QObject::connect(preview, SIGNAL(paintRequested(QPrinter*)),
                     connections, SLOT(paintPreview(QPrinter*)));
    return preview;
#else
    auto *label = new QLabel("Print preview is unavailable in this Qt SDK.");
    label->setAlignment(Qt::AlignCenter);
    return label;
#endif
}

static QWidget *buildUi()
{
    auto *tabs = new QTabWidget;
    tabs->addTab(makeCanvasTab(), "Painter");
    tabs->addTab(makeTextTab(), "Text");
    tabs->addTab(makeImagesTab(), "Images/SVG");
    tabs->addTab(makePrintTab(), "Print Preview");
    return tabs;
}

static int runSelfTest()
{
    SmokeReporter r("painting-lab");
    r.setTrace(true);
    if (!r.setLogFile(QDir(QCoreApplication::applicationDirPath()).filePath("painting-selftest.log")))
        return 2;
    r.check("painting/image-alpha-text", [](QString &) {
        QImage image(220, 140, QImage::Format_ARGB32_Premultiplied);
        image.fill(0);
        QPainter p(&image);
        p.fillRect(QRect(0, 0, 100, 100), QColor(10, 120, 200, 180));
        p.drawText(QRect(0, 0, 220, 140), Qt::AlignCenter, QStringLiteral("Qt"));
        p.end();
        // pixelColor() arrived in Qt 5.6; QColor(QRgb) reads the same pixel.
#if QT_VERSION >= QT_VERSION_CHECK(5, 6, 0)
        return !image.isNull() && image.pixelColor(10, 10).alpha() > 0;
#else
        return !image.isNull() && qAlpha(image.pixel(10, 10)) > 0;
#endif
    });
    r.check("painting/svg-renderer", [](QString &) {
        QSvgRenderer renderer(QByteArray("<svg xmlns='http://www.w3.org/2000/svg' width='20' height='20'><rect width='20' height='20' fill='#2870b8'/></svg>"));
        QImage image(20, 20, QImage::Format_ARGB32_Premultiplied);
        image.fill(0);
        QPainter painter(&image);
        renderer.render(&painter);
        painter.end();
        return renderer.isValid() && image.pixel(10, 10) == qRgb(40, 112, 184);
    });
    r.check("painting/png-roundtrip", [](QString &) {
        QImage original(20, 20, QImage::Format_ARGB32);
        original.fill(qRgba(40, 80, 120, 160));
        QByteArray data;
        QBuffer buffer(&data);
        if (!buffer.open(QIODevice::WriteOnly) || !original.save(&buffer, "PNG"))
            return false;
        QImage decoded;
        return decoded.loadFromData(data, "PNG") && decoded.size() == original.size()
            && decoded.pixel(10, 10) == original.pixel(10, 10);
    });
    r.check("painting/unicode-text-document", [](QString &) {
        QTextDocument doc(QString::fromUtf8("Latin / Привет / Сәлем / 世界"));
        doc.setTextWidth(320);
        QImage image(320, 120, QImage::Format_RGB32);
        image.fill(0xffffffff);
        QPainter painter(&image);
        doc.drawContents(&painter);
        painter.end();
        int ink = 0;
        for (int y = 0; y < image.height(); ++y)
            for (int x = 0; x < image.width(); ++x)
                if (image.pixel(x, y) != qRgb(255, 255, 255)) ++ink;
        // Font glyph availability is a separate property of the installed fonts.
        return doc.toPlainText().contains(QString::fromUtf8("Привет")) && ink > 20;
    });
    r.check("painting/printer-construct", [&r](QString &d) {
#ifndef QT_NO_PRINTER
        QPrinter printer;
        d = QStringLiteral("printer=%1 valid=%2 format=%3 resolution=%4")
            .arg(printer.printerName()).arg(printer.isValid()).arg(int(printer.outputFormat()))
            .arg(printer.resolution());
        qDebug("%s", qPrintable(d));
        if (printer.resolution() <= 0) {
            r.skip(d, QStringLiteral("printer backend unavailable"));
            return false;
        }
        return true;
#else
        r.skip(d, QStringLiteral("Qt SDK was built without printer support"));
        return false;
#endif
    });
    r.check("painting/printer-render", [&r](QString &d) {
#ifndef QT_NO_PRINTER
        QTemporaryFile output;
        if (!output.open()) {
            d = QStringLiteral("could not create temporary print output");
            return false;
        }
        const QString outputName = output.fileName();
        output.close();

        QPrinter printer;
        printer.setOutputFormat(QPrinter::PdfFormat);
        printer.setOutputFileName(outputName);
        if (!paintPrintPage(&printer)) {
            d = QStringLiteral("PDF painter could not begin or finish the page");
            return false;
        }

        if (!output.open()) {
            d = QStringLiteral("could not reopen rendered print output");
            return false;
        }
        const QByteArray data = output.readAll();
        d = QStringLiteral("rendered %1 bytes").arg(data.size());
        if (!data.startsWith("%PDF-") || !data.contains("%%EOF")) return false;
        QFile artifact(QDir(QCoreApplication::applicationDirPath()).filePath("painting-sample.pdf"));
        if (!artifact.open(QIODevice::WriteOnly)) return false;
        return artifact.write(data) == data.size() && data.size() > 100;
#else
        r.skip(d, QStringLiteral("Qt SDK was built without printer support"));
        return false;
#endif
    });
#if defined(Q_OS_WIN) && !defined(QT_NO_PRINTER)
    r.check("painting/native-printer-file", [&r](QString &d) {
        const QPrinterInfo info = QPrinterInfo::defaultPrinter();
        if (info.isNull()) {
            r.skip(d, QStringLiteral("no configured native printer"));
            return false;
        }
        const QString path = QDir(QCoreApplication::applicationDirPath()).filePath("painting-native.prn");
        if (QFile::exists(path) && !QFile::remove(path)) {
            d = QStringLiteral("could not remove previous native output");
            return false;
        }
        QPrinter printer(info);
        printer.setOutputFormat(QPrinter::NativeFormat);
        // .prn preserves NativeFormat; .pdf/.ps would switch Qt's backend.
        // An explicit local filename keeps the job away from physical ports.
        printer.setOutputFileName(path);
        printer.setDocName(QStringLiteral("Qt native printer selftest"));
        d = QStringLiteral("printer=%1 format=%2 output=%3")
            .arg(printer.printerName()).arg(int(printer.outputFormat())).arg(path);
        qDebug("%s", qPrintable(d));
        if (!printer.isValid() || printer.outputFormat() != QPrinter::NativeFormat
                || !paintPrintPage(&printer)) return false;
        QFile output(path);
        if (!output.open(QIODevice::ReadOnly)) return false;
        const QByteArray data = output.readAll();
        d += QStringLiteral(" bytes=%1 state=%2").arg(data.size()).arg(int(printer.printerState()));
        qDebug("%s", qPrintable(d));
        return data.size() > 100 && printer.printerState() == QPrinter::Idle;
    });
#endif
#if defined(Q_OS_WIN) && !defined(QT_NO_PRINTER) && !defined(QT_NO_PRINTDIALOG)
    r.check("painting/native-dialog-cancel", [&r](QString &d) {
        QPrinter printer;
        if (!printer.isValid() || printer.outputFormat() != QPrinter::NativeFormat) {
            r.skip(d, QStringLiteral("no configured native printer"));
            return false;
        }
        QPrintDialog dialog(&printer);
        NativePrintDialogDriver driver(IDCANCEL);
        const int result = dialog.exec();
        d = QStringLiteral("observed=%1 result=%2").arg(driver.observed()).arg(result);
        return driver.observed() && result == QDialog::Rejected && printer.isValid();
    });
    r.check("painting/native-dialog-accept-and-file", [&r](QString &d) {
        QPrinter printer;
        if (!printer.isValid() || printer.outputFormat() != QPrinter::NativeFormat) {
            r.skip(d, QStringLiteral("no configured native printer"));
            return false;
        }
        {
            QPageSetupDialog setup(&printer);
            NativePrintDialogDriver driver(IDOK);
            const int result = setup.exec();
            if (!driver.observed() || result != QDialog::Accepted) {
                d = QStringLiteral("page setup observed=%1 result=%2").arg(driver.observed()).arg(result);
                return false;
            }
        }
        {
            QPrintDialog dialog(&printer);
            NativePrintDialogDriver driver(IDOK);
            const int result = dialog.exec();
            if (!driver.observed() || result != QDialog::Accepted) {
                d = QStringLiteral("print dialog observed=%1 result=%2").arg(driver.observed()).arg(result);
                return false;
            }
        }
        const QString path = QDir(QCoreApplication::applicationDirPath()).filePath("painting-dialog-native.prn");
        if (QFile::exists(path) && !QFile::remove(path)) return false;
        printer.setOutputFileName(path); // only now submit a job, explicitly to a local file
        if (!printer.isValid() || printer.outputFormat() != QPrinter::NativeFormat
                || !paintPrintPage(&printer)) return false;
        QFile output(path);
        if (!output.open(QIODevice::ReadOnly)) return false;
        d = QStringLiteral("printer=%1 bytes=%2 state=%3")
            .arg(printer.printerName()).arg(output.size()).arg(int(printer.printerState()));
        qDebug("%s", qPrintable(d));
        return output.size() > 100 && printer.printerState() == QPrinter::Idle;
    });
#endif
#if !defined(QT_NO_PRINTER) && !defined(QT_NO_PRINTPREVIEWDIALOG) && !defined(QT_NO_PRINTPREVIEWWIDGET)
    r.check("painting/preview-dialog", [](QString &d) {
        QPrinter printer;
        QPrintPreviewDialog dialog(&printer);
        PaintingLabConnections connections(nullptr, nullptr, &dialog);
        QObject::connect(&dialog, SIGNAL(paintRequested(QPrinter*)), &connections, SLOT(paintPreview(QPrinter*)));
        dialog.resize(760, 500);
        dialog.show();
        QApplication::processEvents();
        QPrintPreviewWidget *preview = dialog.findChild<QPrintPreviewWidget *>();
        if (!preview || preview->pageCount() != 1) return false;
        QImage image(dialog.size(), QImage::Format_RGB32);
        image.fill(0xffffffff);
        QPainter painter(&image);
        dialog.render(&painter);
        painter.end();
        d = QDir(QCoreApplication::applicationDirPath()).filePath("painting-preview-dialog.png");
        const bool saved = image.save(d, "PNG");
        dialog.reject();
        return saved && dialog.result() == QDialog::Rejected;
    });
#endif
    QTabWidget *tabs = static_cast<QTabWidget *>(buildUi());
    tabs->resize(760, 500);
    tabs->show();
    r.check("painting/printer-discovery", [&r](QString &d) {
#ifndef QT_NO_PRINTER
        const QList<QPrinterInfo> printers = QPrinterInfo::availablePrinters();
        const QPrinterInfo defaultPrinter = QPrinterInfo::defaultPrinter();
        d = QStringLiteral("printers=%1 default=%2").arg(printers.size()).arg(defaultPrinter.printerName());
        for (const QPrinterInfo &printer : printers)
            if (printer.printerName().isEmpty()) return false;
        return defaultPrinter.isNull() || !defaultPrinter.printerName().isEmpty();
#else
        r.skip(d, QStringLiteral("Qt SDK was built without printer support"));
        return false;
#endif
    });
    r.check("painting/preview-pages", [&r, tabs](QString &d) {
#if !defined(QT_NO_PRINTER) && !defined(QT_NO_PRINTPREVIEWWIDGET)
        QPrintPreviewWidget *preview = tabs->findChild<QPrintPreviewWidget *>();
        if (!preview) return false;
        tabs->setCurrentWidget(preview);
        QApplication::processEvents();
        preview->updatePreview();
        QApplication::processEvents();
        const int portraitPages = preview->pageCount();
        preview->setLandscapeOrientation();
        preview->updatePreview();
        QApplication::processEvents();
        const int landscapePages = preview->pageCount();
        preview->setPortraitOrientation();
        preview->fitInView();
        d = QStringLiteral("portrait=%1 landscape=%2 zoom=%3")
            .arg(portraitPages).arg(landscapePages).arg(preview->zoomFactor());
        const bool pagesOk = portraitPages == 1 && landscapePages == 1;
        // The zoom factor comes from the printer's resolution, which is 0 without an
        // installed printer. QPrinterInfo is asked rather than another QPrinter (a
        // second printerless QPrinter corrupted the heap on Qt 4 / NT 4.0).
        if (pagesOk && preview->zoomFactor() <= 0 && QPrinterInfo::availablePrinters().isEmpty()) {
            r.skip(d, QStringLiteral("no configured native printer; pages checked, zoom needs its resolution"));
            return false;
        }
        return pagesOk && preview->zoomFactor() > 0;
#else
        r.skip(d, QStringLiteral("Qt SDK was built without print preview support"));
        return false;
#endif
    });
    r.check("painting/font-selection", [tabs](QString &) {
        QFontComboBox *combo = tabs->findChild<QFontComboBox *>();
        QTextEdit *text = tabs->findChild<QTextEdit *>();
        if (!combo || !text || combo->count() == 0) return false;
        QFont font = combo->currentFont();
        font.setBold(!font.bold());
        combo->setCurrentFont(font);
        return text->font().bold() == font.bold() && text->font().pointSize() == 12;
    });
    const int tileWidth = 380, tileHeight = 270;
    QImage sheet(tileWidth * 2, tileHeight * 2, QImage::Format_RGB32);
    sheet.fill(0xffffffff);
    for (int index = 0; index < tabs->count(); ++index) {
        r.check(QStringLiteral("painting/page-render-%1").arg(tabs->tabText(index)),
                [tabs, index, &sheet](QString &d) {
            tabs->setCurrentIndex(index);
            QApplication::processEvents();
            QImage page(tabs->size(), QImage::Format_RGB32);
            page.fill(0xffff00ff);
            QPainter painter(&page);
            tabs->render(&painter);
            painter.end();
            if (index == 3) {
                d = QDir(QCoreApplication::applicationDirPath()).filePath("painting-preview.png");
                if (!page.save(d, "PNG")) return false;
            }
            int varied = 0;
            const QRgb corner = page.pixel(0, 0);
            for (int y = 0; y < page.height(); y += 4)
                for (int x = 0; x < page.width(); x += 4)
                    if (page.pixel(x, y) != corner) ++varied;
            QPainter contact(&sheet);
            const int left = (index % 2) * 380, top = (index / 2) * 270;
            contact.drawText(left + 8, top + 18, tabs->tabText(index));
            contact.drawImage(QRect(left, top + 25, 380, 245), page);
            return varied > 20;
        });
    }
    r.check("painting/page-contact-sheet", [&sheet](QString &d) {
        d = QDir(QCoreApplication::applicationDirPath()).filePath("painting-lab-pages.png");
        return sheet.save(d, "PNG");
    });
    delete tabs;
    r.check("painting/event-loop-timer", [](QString &) {
        QEventLoop loop;
        QTimer::singleShot(30, &loop, SLOT(quit()));
        loop.exec();
        return true;
    });
    return r.summary();
}

int main(int argc, char **argv)
{
#ifdef Q_OS_WIN
    SmokeCrashInfo::install();
#endif
    int result = 0;
    bool selftest = false;
    {
        QApplication app(argc, argv);
        selftest = app.arguments().contains("--selftest");
        if (selftest) {
            result = runSelfTest();
            std::printf("Painting selftest returned %d; destroying QApplication\n", result);
            std::fflush(stdout);
        } else {
            QMainWindow win;
            win.setWindowTitle("Qt Painting Lab - " QT_VERSION_STR);
            win.setCentralWidget(buildUi());
            win.statusBar()->showMessage("Painting lab - raster/text/alpha/print preview smoke");
            win.resize(760, 560);
            win.show();
            result = app.exec();
        }
    }
    if (selftest) {
        std::printf("QApplication destroyed; returning %d from main\n", result);
        std::fflush(stdout);
    }
    return result;
}

#include "main.moc"
