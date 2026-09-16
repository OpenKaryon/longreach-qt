// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// The QtMultimedia classes that live in QtMultimediaWidgets rather than
// QtMultimedia proper - they need a real widget/graphics-item base, so they
// belong in the widgets gallery rather than the headless console suite that
// covers the rest of the module.
//
// Qt 6 removed the QMediaObject/QMediaControl architecture this file was
// written against: a backend no longer implements a control interface that the
// front end binds to, it plugs into QMediaCaptureSession directly. So the two
// checks that exist to exercise that SPI have no Qt 6 counterpart to be ported
// to, and are guarded rather than rewritten. QVideoWidget is what a Qt 6
// application would use, and is covered from multimedia-lab.
#include "../common/smokecheck.h"

#include <QGraphicsScene>
#include <QGraphicsVideoItem>

#if QT_VERSION_MAJOR < 6
#include <QCameraViewfinder>        // gone in Qt 6 with the old camera stack
#include <QMediaBindableInterface>  // the QMediaObject binding SPI
#include <QVideoWidgetControl>      // the QMediaControl stack
#else
#include <QVideoWidget>
#endif

#if QT_VERSION_MAJOR < 6
namespace {

// A minimal, real backend implementation of the widget-hosting video control -
// the same "backend plugin author" pattern used for the rest of the
// QMediaControl SPI family, just with a QWidget for the payload this time.
class FixedVideoWidgetControl : public QVideoWidgetControl {
public:
    using QVideoWidgetControl::QVideoWidgetControl;
    QWidget *videoWidget() override { return &m_widget; }
    Qt::AspectRatioMode aspectRatioMode() const override { return Qt::KeepAspectRatio; }
    void setAspectRatioMode(Qt::AspectRatioMode) override {}
    bool isFullScreen() const override { return false; }
    void setFullScreen(bool) override {}
    int brightness() const override { return 0; }
    void setBrightness(int) override {}
    int contrast() const override { return 0; }
    void setContrast(int) override {}
    int hue() const override { return 0; }
    void setHue(int) override {}
    int saturation() const override { return 0; }
    void setSaturation(int) override {}
private:
    QWidget m_widget;
};

} // namespace
#endif

void checkMultimediaWidgets(SmokeReporter &r)
{
    r.check("multimediawidgets/graphicsvideoitem", [&](QString &d) {
        QGraphicsScene scene;
        auto *item = new QGraphicsVideoItem;
        item->setSize(QSizeF(160, 120));
        scene.addItem(item);
        bool bindableOk = true;
#if QT_VERSION_MAJOR < 6
        // Reached through the real base every QMediaObject-hosting graphics
        // item derives from. Qt 6 has no such base: the item is attached to a
        // QMediaPlayer or QMediaCaptureSession as a video output instead.
        QMediaBindableInterface *bindable = item;
        bindableOk = bindable->mediaObject() == nullptr;
#endif
        return scene.items().size() == 1 && item->size() == QSizeF(160, 120)
            && bindableOk;
    });
    r.check("multimediawidgets/cameraviewfinder", [&](QString &d) {
#if QT_VERSION_MAJOR < 6
        QCameraViewfinder viewfinder;
        viewfinder.resize(320, 240);
        return viewfinder.size() == QSize(320, 240);
#else
        // QVideoWidget is what replaced it as the widget a camera renders into.
        QVideoWidget videoWidget;
        videoWidget.resize(320, 240);
        return videoWidget.size() == QSize(320, 240);
#endif
    });
    r.check("multimediawidgets/videowidgetcontrol", [&](QString &d) {
#if QT_VERSION_MAJOR < 6
        FixedVideoWidgetControl control;
        control.setBrightness(10);
        QWidget *w = control.videoWidget();
        return w != nullptr && control.aspectRatioMode() == Qt::KeepAspectRatio;
#else
        // No counterpart: Qt 6 has no control SPI for a backend to implement.
        // The aspect-ratio behaviour this exercised now lives on QVideoWidget.
        QVideoWidget videoWidget;
        videoWidget.setAspectRatioMode(Qt::KeepAspectRatio);
        return videoWidget.aspectRatioMode() == Qt::KeepAspectRatio;
#endif
    });
}
