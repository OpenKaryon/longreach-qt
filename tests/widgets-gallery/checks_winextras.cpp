// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// QtWinExtras checks - Windows-only shell integration (taskbar progress/
// thumbnail toolbar/jump lists), which is exactly what this backport targets.
// These need a real native window handle, which is why they live here rather
// than in the console app: winId() forces the native window to exist without
// showing it, giving windowHandle() something real to attach to.
#include "../common/smokecheck.h"

#include <QMainWindow>
#include <QIcon>
#include <QMimeData>

#include <QWinTaskbarButton>
#include <QWinTaskbarProgress>
#include <QWinThumbnailToolBar>
#include <QWinThumbnailToolButton>
#include <QWinJumpList>
#include <QWinJumpListCategory>
#include <QWinJumpListItem>
#include <QWinEvent>
#include <QWinMime>

void checkWinExtras(SmokeReporter &r)
{
    r.check("winextras/taskbar-button-progress", [&](QString &d) {
        QMainWindow win;
        win.winId();   // force a native window without showing it
        QWinTaskbarButton button;
        button.setWindow(win.windowHandle());
        QWinTaskbarProgress *progress = button.progress();
        progress->setRange(0, 100);
        progress->setValue(50);
        progress->show();
        return button.window() == win.windowHandle() && progress->value() == 50 && progress->isVisible();
    });
    r.check("winextras/thumbnail-toolbar-button", [&](QString &d) {
        QMainWindow win;
        win.winId();
        QWinThumbnailToolBar bar;
        bar.setWindow(win.windowHandle());
        auto *button = new QWinThumbnailToolButton(&bar);
        button->setIcon(QIcon());
        button->setToolTip(QStringLiteral("Play"));
        bar.addButton(button);
        return bar.window() == win.windowHandle() && bar.buttons().contains(button);
    });
    r.check("winextras/jumplist", [&](QString &d) {
        QWinJumpList jumpList;
        auto *category = new QWinJumpListCategory(QStringLiteral("Recent"));
        auto *item = new QWinJumpListItem(QWinJumpListItem::Link);
        item->setTitle(QStringLiteral("Reopen"));
        category->addItem(item);
        jumpList.addCategory(category);
        return jumpList.categories().contains(category) && category->items().contains(item);
    });
    r.check("winextras/event-types", [&](QString &d) {
        QWinColorizationChangeEvent colorEvent(QColor(Qt::blue).rgb(), true);
        QWinCompositionChangeEvent compEvent(true);
        return colorEvent.color() == QColor(Qt::blue).rgb() && compEvent.isCompositionEnabled();
    });
    r.check("winextras/custom-mime-converter", [&](QString &d) {
        // QWinMime lets an application add its own clipboard format;
        // registerMimeType() exercises it without OLE.
        class FixedMime : public QWinMime {
        public:
            bool canConvertFromMime(const FORMATETC &, const QMimeData *) const override { return false; }
            bool convertFromMime(const FORMATETC &, const QMimeData *, STGMEDIUM *) const override {
                return false;
            }
            QVector<FORMATETC> formatsForMime(const QString &, const QMimeData *) const override {
                return {};
            }
            bool canConvertToMime(const QString &, IDataObject *) const override { return false; }
            QVariant convertToMime(const QString &, IDataObject *, QVariant::Type) const override {
                return QVariant();
            }
            QString mimeForFormat(const FORMATETC &) const override { return QString(); }
        };
        FixedMime mime;
        int format = QWinMime::registerMimeType(QStringLiteral("application/x-qt-smoke-test"));
        return format != 0 && !mime.canConvertToMime(QStringLiteral("text/plain"), nullptr);
    });
}
