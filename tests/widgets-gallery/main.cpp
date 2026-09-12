// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// widgets-gallery - visual QWidget showcase + headless behavioural self-test.
//
//   widgets-gallery              show the gallery window (eyeball fonts, styles,
//                                dialogs, message-box background on each OS)
//   widgets-gallery --selftest   run checks and a brief visual page sweep,
//                                save widgets-gallery-pages.png, print
//                                PASS/FAIL and exit non-zero on failure
//
// Both modes are compiled in and reference the same widget classes.
#include "../common/smokecheck.h"
#include "gallery.h"
#include "../common/crashinfo.h"
#include "../common/win95-code-image.h"

#include <QApplication>
#include <QCloseEvent>
#include <QColor>
#include <QFont>
#include <QIcon>
#include <QMainWindow>
#include <QMenu>
#include <QMenuBar>
#include <QMessageBox>
#include <QPixmap>
#include <QPainter>
#include <QPen>
#include <QRectF>
#include <QStyle>
#if QT_VERSION_MAJOR >= 6 && defined(Q_OS_WIN)
#include <QStyleFactory>
#include <cstring>
#endif
#include <QStatusBar>
#include <QSystemTrayIcon>
#include <QTabWidget>
#include <QStringList>

#if !SMOKE_QT5 && defined(QT4_WIN95_ACCESSIBILITY_PROBE)
#include <QtPlugin>
Q_IMPORT_PLUGIN(qtaccessiblewidgets)
#endif

static QIcon qtLogoIcon()
{
    // Do not depend on Qt's private QMessageBox resources. They are present in
    // some shared builds but omitted from this static Qt 4 kit; QIcon(path)
    // can still retain an engine for a missing path and delay the failure until
    // the tray requests a pixmap. Supply the common Windows/tray sizes here.
    QIcon icon;
    const int sizes[] = { 16, 24, 32, 48, 64 };
    for (unsigned i = 0; i < sizeof(sizes) / sizeof(sizes[0]); ++i) {
        const int size = sizes[i];
        QPixmap pixmap(size, size);
        pixmap.fill(Qt::transparent);
        QPainter painter(&pixmap);
        painter.setRenderHint(QPainter::Antialiasing);
        const qreal inset = qMax<qreal>(1.0, size / 12.0);
        painter.setPen(QPen(QColor(38, 128, 54), qMax<qreal>(1.0, size / 22.0)));
        painter.setBrush(QColor(80, 184, 72));
        painter.drawRoundedRect(QRectF(inset, inset, size - 2 * inset, size - 2 * inset),
                                size / 7.0, size / 7.0);
        painter.setPen(Qt::white);
        QFont font = painter.font();
        font.setBold(true);
        font.setPixelSize(qMax(7, size * 7 / 16));
        painter.setFont(font);
        painter.drawText(pixmap.rect(), Qt::AlignCenter, QStringLiteral("Qt"));
        icon.addPixmap(pixmap);
    }
    return icon;
}

// Real slots and string-based connects, so the window builds on Qt 4 too.
class GalleryWindow : public QMainWindow
{
    Q_OBJECT

public:
    GalleryWindow()
    {
        setWindowTitle("Qt Widgets Gallery - " QT_VERSION_STR);
        setWindowIcon(qtLogoIcon());
        menuBar()->setNativeMenuBar(false);
        auto *fileMenu = menuBar()->addMenu("&File");
        m_minimizeToTrayAction = fileMenu->addAction("Minimize to &Tray");
        fileMenu->addSeparator();
        auto *exitAction = fileMenu->addAction("E&xit");
        auto *aboutMenu = menuBar()->addMenu("&About");
        auto *aboutQtAction = aboutMenu->addAction("About &Qt");
        setCentralWidget(buildGallery());
        statusBar()->showMessage("Widgets gallery - visual smoke test");
        resize(760, 560);

        setupTray();
#ifndef QT_NO_SYSTEMTRAYICON
        m_minimizeToTrayAction->setEnabled(m_trayIcon != nullptr);
#else
        m_minimizeToTrayAction->setEnabled(false);
#endif
        connect(m_minimizeToTrayAction, SIGNAL(triggered(bool)), this, SLOT(minimizeToTray()));
        connect(exitAction, SIGNAL(triggered(bool)), this, SLOT(exitApplication()));
        connect(aboutQtAction, SIGNAL(triggered(bool)), this, SLOT(showAboutQt()));
    }

protected:
    void closeEvent(QCloseEvent *event) override
    {
#ifndef QT_NO_SYSTEMTRAYICON
        if (!m_exitRequested && m_trayIcon && m_trayIcon->isVisible()) {
            minimizeToTray();
            event->ignore();
            return;
        }
#endif
        QMainWindow::closeEvent(event);
    }

private:
    QIcon trayIcon() const
    {
        QIcon icon = qApp->windowIcon();
        if (!icon.isNull())
            return icon;

        icon = style()->standardIcon(QStyle::SP_ComputerIcon);
        return icon.isNull() ? qtLogoIcon() : icon;
    }

    void setupTray()
    {
#ifndef QT_NO_SYSTEMTRAYICON
        if (!QSystemTrayIcon::isSystemTrayAvailable())
            return;

        QApplication::setQuitOnLastWindowClosed(false);
        m_trayIcon = new QSystemTrayIcon(trayIcon(), this);
        auto *trayMenu = new QMenu(this);
        auto *restoreAction = trayMenu->addAction("&Restore");
        trayMenu->addSeparator();
        auto *exitAction = trayMenu->addAction("E&xit");
        m_trayIcon->setContextMenu(trayMenu);
        m_trayIcon->setToolTip("Qt Widgets Gallery");
        m_trayIcon->show();

        connect(restoreAction, SIGNAL(triggered(bool)), this, SLOT(restoreFromTray()));
        connect(exitAction, SIGNAL(triggered(bool)), this, SLOT(exitApplication()));
        connect(m_trayIcon, SIGNAL(activated(QSystemTrayIcon::ActivationReason)),
                this, SLOT(onTrayActivated(QSystemTrayIcon::ActivationReason)));
#endif
    }

private slots:
    void showAboutQt()
    {
        QMessageBox::aboutQt(this, "About Qt");
    }

#ifndef QT_NO_SYSTEMTRAYICON
    void onTrayActivated(QSystemTrayIcon::ActivationReason reason)
    {
        if (reason == QSystemTrayIcon::Trigger || reason == QSystemTrayIcon::DoubleClick)
            restoreFromTray();
    }
#endif

    void minimizeToTray()
    {
#ifndef QT_NO_SYSTEMTRAYICON
        if (!m_trayIcon)
            return;
        hide();
        statusBar()->showMessage("Hidden in system tray");
#endif
    }

    void restoreFromTray()
    {
        showNormal();
        raise();
        activateWindow();
        statusBar()->showMessage("Restored from system tray", 3000);
    }

    void exitApplication()
    {
        m_exitRequested = true;
#ifndef QT_NO_SYSTEMTRAYICON
        if (m_trayIcon)
            m_trayIcon->hide();
#endif
        qApp->quit();
    }

private:
    QAction *m_minimizeToTrayAction = nullptr;
#ifndef QT_NO_SYSTEMTRAYICON
    QSystemTrayIcon *m_trayIcon = nullptr;
#endif
    bool m_exitRequested = false;
};

static int runSelfTest()
{
    SmokeReporter r("widgets-gallery");
    r.setTrace(true);
    checkWidgets(r);
    checkItemViewWidgets(r);
    checkLayoutsAndWindows(r);
    checkDialogs(r);
    checkGraphicsScene(r);
    checkGraphicsExtensionPoints(r);
#ifdef SMOKE_HAVE_WINEXTRAS
    checkWinExtras(r);
#else
    // Report the gap instead of quietly dropping it, so a Linux/macOS run says
    // why the winextras checks are absent rather than just showing a shorter
    // list than the Windows run.
    r.check("winextras/module-available", [&](QString &d) {
        r.skip(d, QStringLiteral("QtWinExtras is Windows-only and not in this SDK"));
        return false;
    });
#endif
    checkStyleOptions(r);
    checkAbstractBasesViaConcrete(r);
    checkGestures(r);
    checkUndoFramework(r);
    checkPrinting(r);
    checkMdiMovieTrayMisc(r);
    checkDragDropEvents(r);
    checkGraphicsExtras(r);
    checkEventCatalogue(r);
    checkModelBasesAndFileModels(r);
    checkMiscQtBaseTail(r);
#if SMOKE_QT5
    checkAccessibilityAndModelHelpers(r);
    checkQtBaseWidgetsTail2(r);
    checkMultimediaWidgets(r);
#else
    // checks_qtbase_tail2.cpp itself is out of the Qt 4 build, but its subject
    // is not: checks_qtbase_tail2_qt4.cpp carries the same check names over the
    // part of it Qt 4.8.7 has. See tests/widgets-gallery/CMakeLists.txt for the split.
    addQtBaseWidgetsTail2Qt4Checks(r);
    // The other two files are out of the Qt 4 build with nothing behind them;
    // say so rather than let a Qt 4 run just print a shorter list.
    r.check("multimediawidgets/module-available", [&](QString &d) {
        r.skip(d, QStringLiteral("QtMultimediaWidgets is Qt 5 and later"));
        return false;
    });
    // Qt 5 redesigned QAccessibleInterface, so this is a rewrite rather than the
    // same file guarded - see checks_accessibility_qt4.cpp.
    addAccessibilityQt4Checks(r);
    addQt3SupportChecks(r);
    addQtBaseQt4Checks(r);
    addPlatform4Checks(r);
#endif
#if defined(Q_OS_WIN) && defined(QT_WIN95_SUPPORT)
    if (QCoreApplication::arguments().contains("--code-image-trace")) {
        r.check("win95/code-image/after-behaviour", [&](QString &d) {
            const int result = verifyWin95CodeImage();
            d = QString::fromLatin1("loaded code/file comparison result %1").arg(result);
            return result == 0;
        });
    }
#endif
    checkGalleryRendering(r);
    return r.summary();
}

int main(int argc, char *argv[])
{
#ifdef Q_OS_WIN
    SmokeCrashInfo::install();
#endif
#if defined(Q_OS_WIN) && defined(QT_WIN95_SUPPORT)
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--code-image-selftest") == 0) {
            const int result = verifyWin95CodeImage();
            std::printf("---- widgets-code-image: %d passed, %d failed, 0 skipped ----\n",
                        result == 0 ? 1 : 0, result == 0 ? 0 : 1);
            std::fflush(stdout);
            return result;
        }
    }
#endif
#if QT_VERSION_MAJOR >= 6 && defined(Q_OS_WIN)
    // Qt 6 chooses Windows11 on that OS, while Qt 5's gallery uses
    // WindowsVista. Keep the visual comparison on the same widget style.
    // Respect the normal Qt -style option and QT_STYLE_OVERRIDE.
    bool explicitStyle = qEnvironmentVariableIsSet("QT_STYLE_OVERRIDE");
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "-style") == 0
                || std::strncmp(argv[i], "-style=", 7) == 0)
            explicitStyle = true;
    }
#endif
    QApplication app(argc, argv);
#if QT_VERSION_MAJOR >= 6 && defined(Q_OS_WIN)
    if (!explicitStyle
            && QStyleFactory::keys().contains(QStringLiteral("windowsvista"),
                                              Qt::CaseInsensitive))
        QApplication::setStyle(QStringLiteral("windowsvista"));
#endif
    app.setWindowIcon(qtLogoIcon());

#if !SMOKE_QT5
    if (app.arguments().contains("--accessibility-selftest")) {
        SmokeReporter reporter("accessibility-qt4");
        reporter.setTrace(true);
        addAccessibilityQt4Checks(reporter);
        return reporter.summary();
    }
#endif
    if (app.arguments().contains("--gallery-selftest")) {
        SmokeReporter reporter("widgets-gallery-render-only");
        reporter.setTrace(true);
        checkGalleryRendering(reporter);
        return reporter.summary();
    }
    if (app.arguments().contains("--selftest"))
        return runSelfTest();

    GalleryWindow win;
    win.show();
    return app.exec();
}

#include "main.moc"   // GalleryWindow's Q_OBJECT lives in this .cpp
