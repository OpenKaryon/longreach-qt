// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// graphics - visual 2D/animation/effects showcase + headless self-test.
//
//   graphics              show the gallery window (eyeball painting, gradients,
//                         text, running animations, graphics effects, and a
//                         shaped/translucent window - all backport-sensitive)
//   graphics --selftest   run the behavioural checks, print PASS/FAIL, exit
//                         non-zero on failure (renders into QImage, no window)
#include "../common/smokecheck.h"
#include "graphics.h"
#include "../common/crashinfo.h"

#include <QApplication>
#include <QMainWindow>
#include <QMenuBar>
#include <QStatusBar>
#include <QTabWidget>
#include <QPainter>
#include <QDir>
#include <QEventLoop>
#include <QTimer>

class GraphicsGalleryActions : public QObject
{
    Q_OBJECT
public:
    explicit GraphicsGalleryActions(QWidget *window) : QObject(window), window_(window) {}
public slots:
    void showShape() { showShapedWindow(window_); }
private:
    QWidget *window_;
};

static QAction *configureWindow(QMainWindow &win)
{
    win.setWindowTitle("Qt Graphics Gallery - " QT_VERSION_STR);
    QMenu *file = win.menuBar()->addMenu("&File");
    GraphicsGalleryActions *actions = new GraphicsGalleryActions(&win);
    QAction *shape = file->addAction("&Shaped window...");
    QObject::connect(shape, SIGNAL(triggered()), actions, SLOT(showShape()));
    QObject::connect(file->addAction("E&xit"), SIGNAL(triggered()), &win, SLOT(close()));
    win.setCentralWidget(buildGraphicsGallery());
    win.statusBar()->showMessage("Graphics gallery - visual smoke test "
                                "(File > Shaped window for the window-region/alpha test)");
    win.resize(560, 460);
    return shape;
}

static void checkGalleryPages(SmokeReporter &r)
{
    QMainWindow win;
    QAction *shape = configureWindow(win);
    win.show();
    QTabWidget *tabs = static_cast<QTabWidget *>(win.centralWidget());
    QImage sheet(380 * tabs->count(), 340, QImage::Format_RGB32);
    sheet.fill(0xffffffff);
    for (int index = 0; index < tabs->count(); ++index) {
        r.check(QStringLiteral("graphics/page-render-%1").arg(tabs->tabText(index)),
                [&win, tabs, index, &sheet](QString &) {
            tabs->setCurrentIndex(index);
            QApplication::processEvents();
            // Allow the actual tile animation to advance before rendering it.
            QEventLoop loop;
            QTimer::singleShot(80, &loop, SLOT(quit()));
            loop.exec();
            QImage page(win.size(), QImage::Format_RGB32);
            page.fill(0xffff00ff);
            QPainter painter(&page);
            win.render(&painter);
            painter.end();
            int varied = 0;
            QRgb corner = page.pixel(0, 0);
            for (int y = 0; y < page.height(); y += 4)
                for (int x = 0; x < page.width(); x += 4)
                    if (page.pixel(x, y) != corner) ++varied;
            QPainter contact(&sheet);
            contact.drawText(index * 380 + 8, 18, tabs->tabText(index));
            contact.drawImage(QRect(index * 380, 25, 380, 315), page);
            return varied > 20;
        });
    }
    r.check("graphics/page-contact-sheet", [&sheet](QString &d) {
        d = QDir(QCoreApplication::applicationDirPath()).filePath("graphics-gallery-pages.png");
        return sheet.save(d, "PNG");
    });
    r.check("graphics/shaped-window-menu", [&win, shape](QString &d) {
        shape->trigger();
        QApplication::processEvents();
        QWidget *shaped = win.findChild<QWidget *>("graphics-shaped-window");
        if (!shaped || !shaped->isVisible() || !shaped->isWindow()) return false;
        bool modeValid = shaped->testAttribute(Qt::WA_TranslucentBackground);
#if defined(Q_OS_WIN) && !SMOKE_QT5
        if (QSysInfo::WindowsVersion < QSysInfo::WV_2000)
            modeValid = !shaped->mask().isEmpty()
                && !shaped->mask().contains(QPoint(0, 0))
                && shaped->mask().contains(shaped->rect().center());
#endif
        QImage image(shaped->size(), QImage::Format_ARGB32_Premultiplied);
        image.fill(0);
        QPainter painter(&image);
        shaped->render(&painter);
        painter.end();
        d = QDir(QCoreApplication::applicationDirPath()).filePath("graphics-shaped-window.png");
        const bool saved = image.save(d, "PNG");
        shaped->close();
        QCoreApplication::sendPostedEvents(0, QEvent::DeferredDelete);
        return modeValid && saved && !win.findChild<QWidget *>("graphics-shaped-window");
    });
}

static int runSelfTest()
{
    SmokeReporter r("graphics");
    r.setTrace(true);
    checkPainter(r);
    checkPaths(r);
    checkTransforms(r);
    checkImageOps(r);
    checkAnimations(r);
    checkStateMachine(r);
    checkGraphicsEffectsAndItems(r);
    checkGalleryPages(r);
    return r.summary();
}

int main(int argc, char *argv[])
{
#ifdef Q_OS_WIN
    SmokeCrashInfo::install();
#endif
    QApplication app(argc, argv);

    if (app.arguments().contains("--selftest"))
        return runSelfTest();

    QMainWindow win;
    configureWindow(win);
    win.show();
    return app.exec();
}

#include "main.moc"
