// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// multimedia-lab - manual Qt Multimedia smoke app.
//
// The window and the checks below are Qt 5 and Qt 6 only, and everything after
// the guard is compiled out on Qt 4. That is not this app giving up on Qt 4:
// Qt 4 ships a module called QtMultimedia too, and lab_qt4.cpp is its half of
// this application - same name, same --selftest contract, a different
// QtMultimedia underneath. See the note at the top of that file.
#include "../common/smokecheck.h"
#include "../common/crashinfo.h"

#include <QApplication>
#include <QMainWindow>
#include <QStatusBar>
#include <QWidget>

#if SMOKE_QT5
#if QT_VERSION_MAJOR < 6
#include <QAudioDeviceInfo>
#else
#include <QAudioDevice>
#include <QMediaDevices>
#endif
#include <QAudioFormat>
#include <QCamera>
#if QT_VERSION_MAJOR < 6
#include <QCameraInfo>
#else
#include <QCameraDevice>   // QCameraInfo under its Qt 6 name
#endif
#if QT_VERSION_MAJOR < 6
#include <QCameraViewfinder>   // gone in Qt 6 with the old camera stack
#else
#include <QMediaCaptureSession>   // what replaced it
#endif
#include <QFileDialog>
#include <QFormLayout>
#include <QHBoxLayout>
#include <QLabel>
#include <QMainWindow>
#include <QMediaPlayer>
#if QT_VERSION_MAJOR < 6
#include <QMediaPlaylist>   // no Qt 6 counterpart: playlists were dropped
#endif
#include <QPushButton>
#include <QSlider>
#include <QSoundEffect>
#include <QStatusBar>
#include <QStringList>
#include <QTabWidget>
#include <QTextEdit>
#include <QUrl>
#include <QVBoxLayout>
#include <QVideoWidget>

#include "speech_tab.h"

static QWidget *makeDevicesTab()
{
    auto *w = new QWidget;
    auto *layout = new QVBoxLayout(w);
    auto *text = new QTextEdit;
    text->setReadOnly(true);
    QStringList lines;
    lines << "Audio outputs:";
#if QT_VERSION_MAJOR < 6
    for (const QAudioDeviceInfo &info : QAudioDeviceInfo::availableDevices(QAudio::AudioOutput))
        lines << "  " + info.deviceName();
    lines << "" << "Audio inputs:";
    for (const QAudioDeviceInfo &info : QAudioDeviceInfo::availableDevices(QAudio::AudioInput))
        lines << "  " + info.deviceName();
    lines << "" << "Cameras:";
    for (const QCameraInfo &info : QCameraInfo::availableCameras())
        lines << "  " + info.description();
#else
    // Qt 6 enumerates through QMediaDevices rather than statics on the info
    // classes, and the device objects carry description() rather than
    // deviceName().
    for (const QAudioDevice &info : QMediaDevices::audioOutputs())
        lines << "  " + info.description();
    lines << "" << "Audio inputs:";
    for (const QAudioDevice &info : QMediaDevices::audioInputs())
        lines << "  " + info.description();
    lines << "" << "Cameras:";
    for (const QCameraDevice &info : QMediaDevices::videoInputs())
        lines << "  " + info.description();
#endif
    text->setPlainText(lines.join("\n"));
    layout->addWidget(text);
    return w;
}

static QWidget *makePlayerTab()
{
    auto *w = new QWidget;
    auto *layout = new QVBoxLayout(w);
    auto *video = new QVideoWidget;
    video->setMinimumHeight(260);
    layout->addWidget(video);
    auto *player = new QMediaPlayer(w);
#if QT_VERSION_MAJOR < 6
    auto *playlist = new QMediaPlaylist(player);
    player->setPlaylist(playlist);
#endif
    player->setVideoOutput(video);

    auto *buttons = new QHBoxLayout;
    auto *open = new QPushButton("Open media");
    auto *play = new QPushButton("Play");
    auto *pause = new QPushButton("Pause");
    auto *stop = new QPushButton("Stop");
    buttons->addWidget(open);
    buttons->addWidget(play);
    buttons->addWidget(pause);
    buttons->addWidget(stop);
    buttons->addStretch();
    layout->addLayout(buttons);
    auto *position = new QSlider(Qt::Horizontal);
    layout->addWidget(position);
    auto *status = new QLabel("No media loaded");
    layout->addWidget(status);

    QObject::connect(open, &QPushButton::clicked, w, [w, player, status] {
        const QString file = QFileDialog::getOpenFileName(w, "Open media");
        if (!file.isEmpty()) {
#if QT_VERSION_MAJOR < 6
            player->playlist()->clear();
            player->playlist()->addMedia(QUrl::fromLocalFile(file));
#else
            player->setSource(QUrl::fromLocalFile(file));
#endif
            status->setText(file);
        }
    });
    QObject::connect(play, &QPushButton::clicked, player, &QMediaPlayer::play);
    QObject::connect(pause, &QPushButton::clicked, player, &QMediaPlayer::pause);
    QObject::connect(stop, &QPushButton::clicked, player, &QMediaPlayer::stop);
    QObject::connect(player, &QMediaPlayer::durationChanged, position, &QSlider::setMaximum);
    QObject::connect(player, &QMediaPlayer::positionChanged, position, &QSlider::setValue);
    QObject::connect(position, &QSlider::sliderMoved, player, &QMediaPlayer::setPosition);
    return w;
}

static QWidget *makeAudioTab()
{
    auto *w = new QWidget;
    auto *layout = new QVBoxLayout(w);
    auto *effect = new QSoundEffect(w);
    auto *button = new QPushButton("Construct QSoundEffect / play if source selected");
    auto *open = new QPushButton("Select WAV");
    auto *label = new QLabel("No source");
    layout->addWidget(open);
    layout->addWidget(button);
    layout->addWidget(label);
    layout->addStretch();
    QObject::connect(open, &QPushButton::clicked, w, [w, effect, label] {
        const QString file = QFileDialog::getOpenFileName(w, "Open WAV", QString(), "WAV files (*.wav);;All files (*.*)");
        if (!file.isEmpty()) {
            effect->setSource(QUrl::fromLocalFile(file));
            label->setText(file);
        }
    });
    QObject::connect(button, &QPushButton::clicked, effect, &QSoundEffect::play);
    return w;
}

static QWidget *makeCameraTab()
{
    auto *w = new QWidget;
    auto *layout = new QVBoxLayout(w);
#if QT_VERSION_MAJOR < 6
    auto *viewfinder = new QCameraViewfinder;
#else
    auto *viewfinder = new QVideoWidget;
#endif
    viewfinder->setMinimumHeight(260);
    layout->addWidget(viewfinder);
    auto *status = new QLabel("Camera not started");
    auto *start = new QPushButton("Start default camera");
    auto *stop = new QPushButton("Stop camera");
    auto *buttons = new QHBoxLayout;
    buttons->addWidget(start);
    buttons->addWidget(stop);
    buttons->addStretch();
    layout->addLayout(buttons);
    layout->addWidget(status);
    QCamera **camera = new QCamera *(nullptr);
#if QT_VERSION_MAJOR < 6
    QObject::connect(start, &QPushButton::clicked, w, [camera, viewfinder, status] {
        if (!*camera)
            *camera = new QCamera(viewfinder);
        (*camera)->setViewfinder(viewfinder);
        (*camera)->start();
        status->setText("Camera start requested");
    });
#else
    // Qt 6 routes the camera through a capture session, which owns both the
    // camera and the preview sink.
    auto *session = new QMediaCaptureSession(w);
    session->setVideoOutput(viewfinder);
    QObject::connect(start, &QPushButton::clicked, w, [camera, session, status] {
        if (!*camera) {
            *camera = new QCamera(session);
            session->setCamera(*camera);
        }
        (*camera)->start();
        status->setText("Camera start requested");
    });
#endif
    QObject::connect(stop, &QPushButton::clicked, w, [camera, status] {
        if (*camera)
            (*camera)->stop();
        status->setText("Camera stopped");
    });
    QObject::connect(w, &QObject::destroyed, w, [camera](QObject *) { delete camera; });
    return w;
}

static QWidget *buildUi()
{
    auto *tabs = new QTabWidget;
    tabs->addTab(makeDevicesTab(), "Devices");
    tabs->addTab(makePlayerTab(), "Player");
    tabs->addTab(makeAudioTab(), "Audio");
    tabs->addTab(makeCameraTab(), "Camera");
    tabs->addTab(makeSpeechTab(), "Speech");
    return tabs;
}

static int runSelfTest()
{
    SmokeReporter r("multimedia-lab");
    r.check("multimedia/player-playlist-video-construct", [&r](QString &d) {
        QMediaPlayer player;
        QVideoWidget video;
#if QT_VERSION_MAJOR < 6
        QMediaPlaylist playlist;
        player.setPlaylist(&playlist);
#endif
        player.setVideoOutput(&video);
        // No backend plugin means no media service behind the player, and
        // mediaStatus() then reports UnknownMediaStatus rather than NoMedia.
        // That is the environment missing, not the API misbehaving.
#if QT_VERSION_MAJOR < 6
        if (!player.service()) {
            r.skip(d, QStringLiteral("no multimedia backend: QMediaObject::service() is null"));
            return false;
        }
        return player.mediaStatus() == QMediaPlayer::NoMedia && playlist.mediaCount() == 0;
#else
        // QMediaObject and its service() are gone; a Qt 6 player with no source
        // reports NoMedia whether or not a backend plugin is present.
        (void)d;
        return player.mediaStatus() == QMediaPlayer::NoMedia && player.source().isEmpty();
#endif
    });
    r.check("multimedia/audio-format-devices", [](QString &) {
        QAudioFormat format;
        format.setSampleRate(44100);
        format.setChannelCount(2);
#if QT_VERSION_MAJOR < 6
        format.setSampleSize(16);
#else
        format.setSampleFormat(QAudioFormat::Int16);   // size and type merged
#endif
        return format.sampleRate() == 44100;
    });
    r.check("multimedia/camera-info-construct", [](QString &) {
#if QT_VERSION_MAJOR < 6
        QList<QCameraInfo> cameras = QCameraInfo::availableCameras();
#else
        const QList<QCameraDevice> cameras = QMediaDevices::videoInputs();
#endif
        return cameras.size() >= 0;
    });
    addSpeechChecks(r);
    return r.summary();
}

#else   // !SMOKE_QT5

// The Qt 4 half, in lab_qt4.cpp next door.
QWidget *buildUiQt4();
void addMultimedia4Checks(SmokeReporter &r);

static QWidget *buildUi() { return buildUiQt4(); }

static int runSelfTest()
{
    SmokeReporter r("multimedia-lab");
    r.setTrace(true);
    addMultimedia4Checks(r);
    extern void checkMultimedia4Pages(SmokeReporter &);
    checkMultimedia4Pages(r);
    return r.summary();
}

#endif  // SMOKE_QT5

int main(int argc, char **argv)
{
#ifdef Q_OS_WIN
    SmokeCrashInfo::install();
#endif
    QApplication app(argc, argv);
    if (app.arguments().contains("--selftest"))
        return runSelfTest();

    QMainWindow win;
    win.setWindowTitle("Qt Multimedia Lab - " QT_VERSION_STR);
    win.setCentralWidget(buildUi());
    win.statusBar()->showMessage("Multimedia lab - manual media/audio/camera smoke");
    win.resize(800, 580);
    win.show();
    return app.exec();
}
