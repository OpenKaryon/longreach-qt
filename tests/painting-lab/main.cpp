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
#include <QProcess>
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
#include <tlhelp32.h>
#include <cstring>
// The ANSI process entry: Windows 9x has no Process32FirstW.
#ifdef UNICODE
#undef PROCESSENTRY32
#endif
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
// Drives a native print dialog of the GUI thread, or on Windows 11 the
// window of PrintDialog.exe; never submits a job to a printer. It polls from
// its own thread, as Qt's timers need not run inside a native modal dialog.
// Windows 11 opens PrintDlgEx in PrintDialog.exe, where Qt 4's dialogs do not
// always return, so Qt 4 skips them there.
static bool qt4OnOutOfProcessPrintDialogs()
{
#if QT_VERSION < 0x050000
    static const char app[] = "\\SystemApps\\Windows.PrintDialog_cw5n1h2txyewy\\PrintDialog.exe";
    char path[MAX_PATH] = {};
    const UINT length = GetWindowsDirectoryA(path, MAX_PATH - sizeof(app));
    if (!length || length >= MAX_PATH - sizeof(app)) return false;
    lstrcatA(path, app);
    return GetFileAttributesA(path) != INVALID_FILE_ATTRIBUTES;
#else
    return false;
#endif
}

class NativePrintDialogDriver
{
public:
    explicit NativePrintDialogDriver(int command)
        : command_(command), guiThread_(GetCurrentThreadId()),
          stop_(0), done_(0), observed_(0), outOfProcess_(0), timedOut_(0)
    {
        GetSystemTimeAsFileTime(&started_);
        DWORD id = 0;
        thread_ = CreateThread(0, 0, run, this, 0, &id);
    }
    ~NativePrintDialogDriver()
    {
        InterlockedExchange(&stop_, 1);
        if (thread_) {
            WaitForSingleObject(thread_, 5000);
            CloseHandle(thread_);
        }
        // A PrintDialog.exe can outlive its dialog, and Windows hands the
        // next dialog to it; see printDialogRunning().
        printDialogProcesses(&started_, true);
    }
    // A PrintDialog.exe that is already running: Windows 11 hands it the next
    // dialog, the driver cannot tell it from another program's, and
    // PrintDlgEx may then never return, even after that process is ended.
    // The check then skips.
    static bool printDialogRunning() { return printDialogProcesses(0, false) > 0; }
    static void endPrintDialogsSince(const FILETIME &since) { printDialogProcesses(&since, true); }
    bool observed() const { return observed_ != 0; }
    // Windows 11 shows the PrintDlgEx dialog from PrintDialog.exe, outside
    // this process. It has no dialog items to post to, so the driver closes
    // it, which the caller sees as a cancel.
    bool outOfProcess() const { return outOfProcess_ != 0; }
    // A dialog that did not close within about 20 s: the driver then closes
    // this thread's dialogs and ends its PrintDialog.exe, so exec() returns
    // and the check can skip instead of hanging the suite.
    bool timedOut() const { return timedOut_ != 0; }
private:
    static DWORD WINAPI run(LPVOID context)
    {
        NativePrintDialogDriver *driver = static_cast<NativePrintDialogDriver *>(context);
        for (int polls = 0; !driver->stop_; ++polls) {
            if (polls == 250) {
                InterlockedExchange(&driver->timedOut_, 1);
                std::printf("no answer within 20 s: closing the dialog, ending PrintDialog.exe\n");
                std::fflush(stdout);
            }
            if (driver->timedOut_) {
                EnumThreadWindows(driver->guiThread_, closeDialog, 0);
                printDialogProcesses(&driver->started_, true);
            } else if (!driver->done_) {
                // The GUI thread's own dialog first: a PrintDialog.exe left
                // over from an earlier run can still have a window up.
                EnumThreadWindows(driver->guiThread_, findDialog, reinterpret_cast<LPARAM>(driver));
                if (!driver->done_)
                    EnumWindows(findOutOfProcessDialog, reinterpret_cast<LPARAM>(driver));
            }
            Sleep(80);
        }
        return 0;
    }
    static BOOL CALLBACK findOutOfProcessDialog(HWND window, LPARAM context)
    {
        // Looked up at run time: Windows 9x and XP have no such function.
        typedef BOOL (WINAPI *QueryImageName)(HANDLE, DWORD, LPWSTR, PDWORD);
        static const QueryImageName query = reinterpret_cast<QueryImageName>(
            GetProcAddress(GetModuleHandleA("kernel32.dll"), "QueryFullProcessImageNameW"));
        if (!query) return FALSE;
        NativePrintDialogDriver *driver = reinterpret_cast<NativePrintDialogDriver *>(context);
        DWORD pid = 0;
        GetWindowThreadProcessId(window, &pid);
        HANDLE process = OpenProcess(0x1000 /* PROCESS_QUERY_LIMITED_INFORMATION */, FALSE, pid);
        if (!process) return TRUE;
        // Only a PrintDialog.exe started for this dialog: one left over from
        // an earlier run is not ours. Its window can stay hidden, so that is
        // not required.
        typedef BOOL (WINAPI *ProcessTimes)(HANDLE, LPFILETIME, LPFILETIME, LPFILETIME, LPFILETIME);
        static const ProcessTimes times = reinterpret_cast<ProcessTimes>(
            GetProcAddress(GetModuleHandleA("kernel32.dll"), "GetProcessTimes"));
        FILETIME created, exited, kernel, user;
        if (!times || !times(process, &created, &exited, &kernel, &user)
                || CompareFileTime(&created, &driver->started_) < 0) {
            CloseHandle(process);
            return TRUE;
        }
        wchar_t path[MAX_PATH] = {};
        DWORD size = MAX_PATH;
        static const char suffix[] = "\\printdialog.exe";
        const DWORD length = sizeof(suffix) - 1;
        bool match = query(process, 0, path, &size) && size >= length;
        for (DWORD i = 0; match && i < length; ++i) {
            wchar_t c = path[size - length + i];
            if (c >= L'A' && c <= L'Z') c = wchar_t(c - L'A' + L'a');
            match = c == wchar_t(suffix[i]);
        }
        CloseHandle(process);
        if (!match) return TRUE;
        InterlockedExchange(&driver->observed_, 1);
        if (!InterlockedExchange(&driver->outOfProcess_, 1)) {
            std::printf("dialog found in PrintDialog.exe %lu\n", pid);
            std::fflush(stdout);
        }
        // Repeated on every poll until the dialog returns: the window may not
        // take WM_CLOSE before it has finished loading.
        PostMessageA(window, WM_CLOSE, 0, 0);
        return TRUE;
    }
    // By process rather than by window: PrintDialog.exe can have no top-level
    // window that EnumWindows sees. Counts the PrintDialog.exe processes (with
    // since, only those started since then) and with end, ends them and waits
    // until they have gone.
    static int printDialogProcesses(const FILETIME *since, bool end)
    {
        typedef BOOL (WINAPI *ProcessTimes)(HANDLE, LPFILETIME, LPFILETIME, LPFILETIME, LPFILETIME);
        static const ProcessTimes times = reinterpret_cast<ProcessTimes>(
            GetProcAddress(GetModuleHandleA("kernel32.dll"), "GetProcessTimes"));
        // NT 4 has no Toolhelp in kernel32: all of it is looked up too.
        HMODULE kernel = GetModuleHandleA("kernel32.dll");
        typedef HANDLE (WINAPI *Snapshot)(DWORD, DWORD);
        typedef BOOL (WINAPI *Walk)(HANDLE, PROCESSENTRY32 *);
        static const Snapshot snap = reinterpret_cast<Snapshot>(GetProcAddress(kernel, "CreateToolhelp32Snapshot"));
        static const Walk first = reinterpret_cast<Walk>(GetProcAddress(kernel, "Process32First"));
        static const Walk next = reinterpret_cast<Walk>(GetProcAddress(kernel, "Process32Next"));
        if (!times || !snap || !first || !next) return 0;
        HANDLE snapshot = snap(TH32CS_SNAPPROCESS, 0);
        if (snapshot == INVALID_HANDLE_VALUE) return 0;
        int found = 0;
        PROCESSENTRY32 entry;
        entry.dwSize = sizeof(entry);
        for (BOOL more = first(snapshot, &entry); more; more = next(snapshot, &entry)) {
            if (lstrcmpiA(entry.szExeFile, "PrintDialog.exe") != 0) continue;
            HANDLE process = OpenProcess(PROCESS_TERMINATE | SYNCHRONIZE | 0x1000, FALSE, entry.th32ProcessID);
            if (!process) continue;
            FILETIME created, exited, kernel, user;
            const bool counted = WaitForSingleObject(process, 0) == WAIT_TIMEOUT
                    && (!since || (times(process, &created, &exited, &kernel, &user)
                                   && CompareFileTime(&created, since) >= 0));
            if (counted) {
                ++found;
                if (end && TerminateProcess(process, 1))
                    WaitForSingleObject(process, 5000);
            }
            CloseHandle(process);
        }
        CloseHandle(snapshot);
        return found;
    }
    static BOOL CALLBACK closeDialog(HWND window, LPARAM)
    {
        char name[32] = {};
        GetClassNameA(window, name, sizeof(name));
        if (IsWindowVisible(window) && std::strcmp(name, "#32770") == 0) {
            PostMessageA(window, WM_COMMAND, IDCANCEL, 0);
            PostMessageA(window, WM_CLOSE, 0, 0);
        }
        return TRUE;
    }
    static BOOL CALLBACK findDialog(HWND window, LPARAM context)
    {
        NativePrintDialogDriver *driver = reinterpret_cast<NativePrintDialogDriver *>(context);
        char name[32] = {};
        GetClassNameA(window, name, sizeof(name));
        if (!IsWindowVisible(window) || std::strcmp(name, "#32770") != 0
                || !GetDlgItem(window, driver->command_)) return TRUE;
        InterlockedExchange(&driver->observed_, 1);
        InterlockedExchange(&driver->outOfProcess_, 0);
        InterlockedExchange(&driver->done_, 1);
        PostMessageA(window, WM_COMMAND, driver->command_, 0);
        return FALSE;
    }
    int command_;
    DWORD guiThread_;
    FILETIME started_;
    HANDLE thread_;
    volatile LONG stop_;
    volatile LONG done_;
    volatile LONG observed_;
    volatile LONG outOfProcess_;
    volatile LONG timedOut_;
};

// The native dialog checks. Each runs in a child painting-lab (see
// runNativeDialogCheck()) and returns 0 on a pass, 1 on a failure and 77 on
// a skip, with the detail or the reason in d. Each step is printed first, so
// a child that has to be ended shows where it stopped.
static void nativeDialogStep(const char *step)
{
    std::printf("%s\n", step);
    std::fflush(stdout);
}

// Whether a native dialog check can run here; if not, the reason is in d.
static bool nativeDialogPossible(const QPrinter &printer, QString &d)
{
    if (qt4OnOutOfProcessPrintDialogs())
        d = QStringLiteral("Qt 4's native print dialogs open in Windows 11's PrintDialog.exe and do not always return");
    else if (!printer.isValid() || printer.outputFormat() != QPrinter::NativeFormat)
        d = QStringLiteral("no configured native printer");
    else if (NativePrintDialogDriver::printDialogRunning())
        d = QStringLiteral("a PrintDialog.exe started before this check is running, and Windows would hand it the dialog");
    else
        return true;
    return false;
}

static int nativeDialogCancel(QString &d)
{
    QPrinter printer;
    if (!nativeDialogPossible(printer, d)) return 77;
    nativeDialogStep("print dialog, to be cancelled");
    QPrintDialog dialog(&printer);
    NativePrintDialogDriver driver(IDCANCEL);
    const int result = dialog.exec();
    if (driver.timedOut()) {
        d = QStringLiteral("the native print dialog did not respond within 20 s");
        return 77;
    }
    d = QStringLiteral("observed=%1 result=%2").arg(driver.observed()).arg(result);
    return driver.observed() && result == QDialog::Rejected && printer.isValid() ? 0 : 1;
}

static int nativeDialogAcceptAndFile(QString &d)
{
    QPrinter printer;
    if (!nativeDialogPossible(printer, d)) return 77;
    {
        nativeDialogStep("page setup dialog, to be accepted");
        QPageSetupDialog setup(&printer);
        NativePrintDialogDriver driver(IDOK);
        const int result = setup.exec();
        if (driver.timedOut()) {
            d = QStringLiteral("the native page setup dialog did not respond within 20 s");
            return 77;
        }
        if (!driver.observed() || result != QDialog::Accepted) {
            d = QStringLiteral("page setup observed=%1 result=%2").arg(driver.observed()).arg(result);
            return 1;
        }
    }
    {
        nativeDialogStep("print dialog, to be accepted");
        QPrintDialog dialog(&printer);
        NativePrintDialogDriver driver(IDOK);
        const int result = dialog.exec();
        if (driver.timedOut() || driver.outOfProcess()) {
            d = driver.timedOut()
                ? QStringLiteral("the native print dialog did not respond within 20 s")
                : QStringLiteral("the Windows 11 print dialog runs in PrintDialog.exe and cannot be accepted from here");
            return 77;
        }
        if (!driver.observed() || result != QDialog::Accepted) {
            d = QStringLiteral("print dialog observed=%1 result=%2").arg(driver.observed()).arg(result);
            return 1;
        }
    }
    const QString path = QDir(QCoreApplication::applicationDirPath()).filePath("painting-dialog-native.prn");
    if (QFile::exists(path) && !QFile::remove(path)) {
        d = QStringLiteral("could not remove previous native output");
        return 1;
    }
    nativeDialogStep("printing to a file");
    printer.setOutputFileName(path); // only now submit a job, explicitly to a local file
    if (!printer.isValid() || printer.outputFormat() != QPrinter::NativeFormat
            || !paintPrintPage(&printer)) {
        d = QStringLiteral("could not print to %1").arg(path);
        return 1;
    }
    QFile output(path);
    if (!output.open(QIODevice::ReadOnly)) {
        d = QStringLiteral("could not open %1").arg(path);
        return 1;
    }
    d = QStringLiteral("printer=%1 bytes=%2 state=%3")
        .arg(printer.printerName()).arg(output.size()).arg(int(printer.printerState()));
    return output.size() > 100 && printer.printerState() == QPrinter::Idle ? 0 : 1;
}

// The child's side: runs one check and prints its detail as the last line.
static int runNativeDialogChild(const QString &name)
{
    QString d;
    int result = 1;
    if (name == QLatin1String("cancel"))
        result = nativeDialogCancel(d);
    else if (name == QLatin1String("accept-and-file"))
        result = nativeDialogAcceptAndFile(d);
    else
        d = QStringLiteral("unknown native dialog check %1").arg(name);
    std::printf("%s\n", qPrintable(d));
    std::fflush(stdout);
    return result;
}

// Windows 11's PrintDialog.exe can close its dialog and still never answer
// PrintDlgEx, which then waits for good, even after PrintDialog.exe has been
// ended. So each check runs in a child painting-lab, which is ended if it has
// not finished within 60 s (the driver gives up on a dialog after about 20 s);
// the check then skips.
static bool runNativeDialogCheck(SmokeReporter &r, const QString &name, QString &d)
{
    FILETIME started;
    GetSystemTimeAsFileTime(&started);
    QProcess child;
    child.setProcessChannelMode(QProcess::MergedChannels);
    child.start(QCoreApplication::applicationFilePath(),
                QStringList() << QStringLiteral("--native-dialog-check") << name);
    if (!child.waitForStarted(30000)) {
        d = QStringLiteral("could not start the check: %1").arg(child.errorString());
        return false;
    }
    // Qt 4 returns false when waitForFinished() is called after the child has
    // already exited.
    const bool finished = child.state() == QProcess::NotRunning || child.waitForFinished(60000);
    if (!finished) {
        child.kill();
        child.waitForFinished(5000);
        NativePrintDialogDriver::endPrintDialogsSince(started);
    }
    QString output = QString::fromLocal8Bit(child.readAll());
    output.replace(QLatin1String("\r\n"), QLatin1String("\n"));
    output = output.trimmed();
    if (!output.isEmpty())
        qDebug("%s", qPrintable(output));
    const QString last = output.section(QLatin1Char('\n'), -1);
    if (!finished) {
        r.skip(d, QStringLiteral("the native dialog did not return within 60 s, and its process was ended; last: %1")
                      .arg(last.isEmpty() ? QStringLiteral("no output") : last));
        return false;
    }
    if (child.exitStatus() != QProcess::NormalExit) {
        d = QStringLiteral("the check crashed with 0x%1").arg(uint(child.exitCode()), 8, 16, QLatin1Char('0'));
        return false;
    }
    if (child.exitCode() == 77) {
        r.skip(d, last);
        return false;
    }
    d = last;
    return child.exitCode() == 0;
}
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
        // A spooled driver (Microsoft Print to PDF on Windows 11) writes the
        // file after the job is handed over rather than inside end().
        QFile output(path);
        QByteArray data;
        for (int waited = 0; waited <= 15000 && data.size() <= 100; waited += 250) {
            if (output.open(QIODevice::ReadOnly)) {
                data = output.readAll();
                output.close();
            }
            if (data.size() <= 100) {
                QEventLoop pause;
                QTimer::singleShot(250, &pause, SLOT(quit()));
                pause.exec();
            }
        }
        d += QStringLiteral(" bytes=%1 state=%2").arg(data.size()).arg(int(printer.printerState()));
        qDebug("%s", qPrintable(d));
        return data.size() > 100 && printer.printerState() == QPrinter::Idle;
    });
#endif
#if defined(Q_OS_WIN) && !defined(QT_NO_PRINTER) && !defined(QT_NO_PRINTDIALOG)
    r.check("painting/native-dialog-cancel", [&r](QString &d) {
        return runNativeDialogCheck(r, QStringLiteral("cancel"), d);
    });
    r.check("painting/native-dialog-accept-and-file", [&r](QString &d) {
        return runNativeDialogCheck(r, QStringLiteral("accept-and-file"), d);
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
        // The zoom factor comes from the printer's resolution, which is 0 without a
        // default printer (Qt 4 on Windows 11 can find printers but no default one).
        // QPrinterInfo is asked rather than another QPrinter (a second printerless
        // QPrinter corrupted the heap on Qt 4 / NT 4.0).
        if (pagesOk && preview->zoomFactor() <= 0 && QPrinterInfo::defaultPrinter().isNull()) {
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
#if defined(Q_OS_WIN) && !defined(QT_NO_PRINTER) && !defined(QT_NO_PRINTDIALOG)
        const int nativeDialog = app.arguments().indexOf(QStringLiteral("--native-dialog-check"));
        if (nativeDialog > 0 && nativeDialog + 1 < app.arguments().size())
            return runNativeDialogChild(app.arguments().at(nativeDialog + 1));
#endif
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
