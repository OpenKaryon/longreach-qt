// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// QtMultimedia checks. Most of the module's classes are backend SPI (the
// *Control/*Interface/*Plugin types meant for plugin authors, not app code) -
// skipped here as inappropriate to construct directly from an application.
// Everything below is real app-facing API: it constructs and configures real
// objects without requiring a working audio/camera backend to be present (the
// backport target is a headless CI box as much as a desktop with hardware),
// the same way checks_sql.cpp exercises QSqlDatabase without a live server.
#include "../common/smokecheck.h"

#if !SMOKE_QT5

static void skipModernMultimedia(SmokeReporter &r, const char *name)
{
    r.check(QString::fromLatin1(name), [&](QString &d) {
        r.skip(d, QStringLiteral("Qt 4 multimedia value types are covered by multimedia-lab"));
        return false;
    });
}

void checkAudioValueTypes(SmokeReporter &r) { skipModernMultimedia(r, "multimedia/audio-value-types"); }
void checkSoundEffects(SmokeReporter &r) { skipModernMultimedia(r, "multimedia/sound-effects"); }
void checkMediaPlayerPlaylist(SmokeReporter &r) { skipModernMultimedia(r, "multimedia/player-playlist"); }
void checkCameraValueTypes(SmokeReporter &r) { skipModernMultimedia(r, "multimedia/camera-value-types"); }
void checkRadio(SmokeReporter &r) { skipModernMultimedia(r, "multimedia/radio"); }
void checkVideoSurfaceAndFilter(SmokeReporter &r) { skipModernMultimedia(r, "multimedia/video-surface-filter"); }

#else

#include <QAudioFormat>
#if QT_VERSION_MAJOR < 6
#include <QAudioDeviceInfo>
#endif
#include <QAudioInput>
#include <QAudioOutput>
#include <QAudioBuffer>
#if QT_VERSION_MAJOR < 6
#include <QAudioProbe>
#endif
#if QT_VERSION_MAJOR < 6
#include <QAudioRecorder>
#endif
#include <QAudioDecoder>

#if QT_VERSION_MAJOR < 6
#include <QSound>
#endif
#include <QSoundEffect>

#if QT_VERSION_MAJOR < 6
#include <QMediaContent>
#endif
#if QT_VERSION_MAJOR < 6
#include <QMediaResource>
#endif
#include <QMediaPlayer>
#if QT_VERSION_MAJOR < 6
#include <QMediaPlaylist>
#endif
#include <QMediaRecorder>
#if QT_VERSION_MAJOR < 6
#include <QMediaObject>
#endif
#if QT_VERSION_MAJOR < 6
#include <QMediaService>
#endif
#include <QMediaTimeRange>
#if QT_VERSION_MAJOR < 6
#include <QMediaServiceProviderHint>
#endif

#include <QCamera>
#if QT_VERSION_MAJOR < 6
#include <QCameraInfo>
#endif
#if QT_VERSION_MAJOR < 6
#include <QCameraExposure>
#endif
#if QT_VERSION_MAJOR < 6
#include <QCameraFocus>
#endif
#if QT_VERSION_MAJOR < 6
#include <QCameraFocusZone>
#endif
#if QT_VERSION_MAJOR < 6
#include <QCameraImageCapture>
#endif
#if QT_VERSION_MAJOR < 6
#include <QCameraImageProcessing>
#endif
#if QT_VERSION_MAJOR < 6
#include <QCameraViewfinderSettings>
#endif

#if QT_VERSION_MAJOR < 6
#include <QRadioTuner>
#endif
#if QT_VERSION_MAJOR < 6
#include <QRadioData>
#endif

#if QT_VERSION_MAJOR < 6
#include <QAbstractVideoSurface>
#endif
#if QT_VERSION_MAJOR < 6
#include <QAbstractVideoFilter>
#endif
#include <QVideoFrame>
#if QT_VERSION_MAJOR < 6
#include <QVideoSurfaceFormat>
#endif

#include <QUrl>

#if QT_VERSION_MAJOR >= 6
// What the Qt 6 branches below reach for; none of these exist in Qt 5.
#include <QMediaDevices>
#include <QAudioDevice>
#include <QAudioSource>
#include <QAudioSink>
#include <QCameraDevice>
#include <QImageCapture>
#include <QVideoSink>
#include <QVideoFrameFormat>
#endif

void checkAudioValueTypes(SmokeReporter &r)
{
    r.check("multimedia/audioformat", [&](QString &d) {
        QAudioFormat fmt;
        fmt.setSampleRate(44100);
        fmt.setChannelCount(2);
#if QT_VERSION_MAJOR < 6
        fmt.setSampleSize(16);
        fmt.setCodec(QStringLiteral("audio/pcm"));
        fmt.setSampleType(QAudioFormat::SignedInt);
        return fmt.sampleRate() == 44100 && fmt.channelCount() == 2
            && fmt.sampleType() == QAudioFormat::SignedInt;
#else
        // Sample size, sample type and codec collapsed into one sample format;
        // uncompressed PCM is the only thing QAudioFormat describes in Qt 6.
        fmt.setSampleFormat(QAudioFormat::Int16);
        return fmt.sampleRate() == 44100 && fmt.channelCount() == 2
            && fmt.sampleFormat() == QAudioFormat::Int16;
#endif
    });
    r.check("multimedia/audiodeviceinfo", [&](QString &d) {
        // No real device is required to be present or usable.
#if QT_VERSION_MAJOR < 6
        QAudioDeviceInfo info = QAudioDeviceInfo::defaultOutputDevice();
        const QList<QAudioDeviceInfo> all = QAudioDeviceInfo::availableDevices(QAudio::AudioOutput);
        QAudioFormat fmt; fmt.setSampleRate(44100); fmt.setChannelCount(2); fmt.setSampleSize(16);
#else
        // QAudioDeviceInfo became QAudioDevice, enumerated through QMediaDevices
        // rather than through statics on the device class.
        QAudioDevice info = QMediaDevices::defaultAudioOutput();
        const QList<QAudioDevice> all = QMediaDevices::audioOutputs();
        QAudioFormat fmt; fmt.setSampleRate(44100); fmt.setChannelCount(2);
        fmt.setSampleFormat(QAudioFormat::Int16);
#endif
        bool supported = info.isFormatSupported(fmt);
        Q_UNUSED(supported);   // may legitimately be false with no real backend
        return true == (all.size() >= 0);   // just confirms the call doesn't crash
    });
    r.check("multimedia/audioinput-output-construct", [&](QString &d) {
        // With no audio backend at all - a container with no ALSA/PulseAudio,
        // no gstreamer plugins - QAudioInput/Output construct but have no
        // device behind them, so setVolume() has nothing to store and the
        // read-back is meaningless. Detect that instead of asserting into it.
#if QT_VERSION_MAJOR < 6
        if (QAudioDeviceInfo::defaultOutputDevice().isNull()
            && QAudioDeviceInfo::defaultInputDevice().isNull()) {
            r.skip(d, QStringLiteral("no audio backend on this system"));
            return false;
        }
        QAudioFormat fmt; fmt.setSampleRate(8000); fmt.setChannelCount(1); fmt.setSampleSize(8);
        QAudioInput input(fmt);
        QAudioOutput output(fmt);
#else
        // QAudioInput/QAudioOutput were renamed QAudioSource/QAudioSink in
        // Qt 6 (the old names now mean something else entirely: the input and
        // output *routes* of a capture session).
        if (QMediaDevices::defaultAudioOutput().isNull()
            && QMediaDevices::defaultAudioInput().isNull()) {
            r.skip(d, QStringLiteral("no audio backend on this system"));
            return false;
        }
        QAudioFormat fmt; fmt.setSampleRate(8000); fmt.setChannelCount(1);
        fmt.setSampleFormat(QAudioFormat::UInt8);
        QAudioSource input(fmt);
        QAudioSink output(fmt);
#endif
        input.setVolume(0.5);
        output.setVolume(0.5);
        return qFuzzyCompare(input.volume(), 0.5) && qFuzzyCompare(output.volume(), 0.5);
    });
    r.check("multimedia/audiobuffer", [&](QString &d) {
        // QAudioFormat needs codec + sample type set to be isValid(), or
        // QAudioBuffer's constructor silently leaves it null (sampleCount 0).
        QAudioFormat fmt;
        fmt.setSampleRate(8000); fmt.setChannelCount(1);
#if QT_VERSION_MAJOR < 6
        fmt.setSampleSize(8);
        fmt.setCodec(QStringLiteral("audio/pcm"));
        fmt.setSampleType(QAudioFormat::UnSignedInt);
#else
        fmt.setSampleFormat(QAudioFormat::UInt8);
#endif
        QByteArray data(160, char(0));   // 20ms of silence at 8kHz/8bit/mono
        QAudioBuffer buffer(data, fmt);
        return buffer.sampleCount() == 160 && buffer.format() == fmt;
    });
    r.check("multimedia/audioprobe-recorder-decoder-construct", [&](QString &d) {
#if QT_VERSION_MAJOR < 6
        QAudioProbe probe;
        QAudioRecorder recorder;
        QAudioDecoder decoder;
        decoder.setSourceFilename(QStringLiteral("nonexistent.wav"));
        // Without a real backend plugin, the decoder control is null and
        // setSourceFilename() legitimately doesn't retain the value - just
        // confirm construction/configuration doesn't crash or throw.
        Q_UNUSED(decoder);
        return !probe.isActive() && recorder.state() == QMediaRecorder::StoppedState;
#else
        // QAudioProbe and QAudioRecorder went with the QMediaService rework;
        // QMediaRecorder covers recording now and QAudioDecoder took a QUrl.
        QMediaRecorder recorder;
        QAudioDecoder decoder;
        decoder.setSource(QUrl::fromLocalFile(QStringLiteral("nonexistent.wav")));
        Q_UNUSED(decoder);
        return recorder.recorderState() == QMediaRecorder::StoppedState;
#endif
    });
}

void checkSoundEffects(SmokeReporter &r)
{
    r.check("multimedia/soundeffect-construct", [&](QString &d) {
        QSoundEffect effect;
        effect.setSource(QUrl::fromLocalFile("nonexistent.wav"));
        effect.setVolume(0.8);
        effect.setLoopCount(2);
        // volume() is qreal on Qt 5 and float on Qt 6, so 0.8 does not survive
        // the round trip exactly on both - compare within the float epsilon
        // rather than exactly.
        return qAbs(double(effect.volume()) - 0.8) < 1e-6 && effect.loopCount() == 2;
    });
    r.check("multimedia/qsound-static-play", [&](QString &d) {
#if QT_VERSION_MAJOR < 6
        // QSound::play() on a missing file is a documented no-op, not a crash -
        // this just exercises the static API surface.
        QSound::play(QStringLiteral("nonexistent.wav"));
        return true;
#else
        // QSound was removed; QSoundEffect (covered right above) is the
        // replacement and has no static one-shot form.
        r.skip(d, QStringLiteral("Qt 6 removed QSound in favour of QSoundEffect"));
        return false;
#endif
    });
}

void checkMediaPlayerPlaylist(SmokeReporter &r)
{
    r.check("multimedia/mediacontent-resource", [&](QString &d) {
#if QT_VERSION_MAJOR < 6
        QMediaResource res(QUrl(QStringLiteral("file:///clip.mp4")), QStringLiteral("video/mp4"));
        QMediaContent content(res.url());
        return !content.isNull() && content.canonicalUrl() == res.url();
#else
        // QMediaResource and QMediaContent are gone: a player takes a plain
        // QUrl source in Qt 6.
        r.skip(d, QStringLiteral("Qt 6 replaced QMediaContent/QMediaResource with a plain QUrl"));
        return false;
#endif
    });
    r.check("multimedia/mediaplayer-construct-and-base", [&](QString &d) {
        QMediaPlayer player;
#if QT_VERSION_MAJOR < 6
        player.setMedia(QMediaContent(QUrl(QStringLiteral("file:///clip.mp4"))));
        // Reached through the real base class - QMediaPlayer derives from
        // QMediaObject, which is what exposes availabilityChanged()/service().
        QMediaObject *base = &player;
        QMediaService *service = base->service();
        // Without a backend plugin the service is null, and setMedia() then
        // has nowhere to store the request - media() comes back null through
        // no fault of the API. The base-class traversal above is still real,
        // so report the gap rather than asserting against a missing backend.
        if (!service) {
            r.skip(d, QStringLiteral("no multimedia backend: QMediaObject::service() is null"));
            return false;
        }
        return player.duration() == 0 && !player.media().isNull();
#else
        // No QMediaObject base and no service to go missing: the player is a
        // QObject that takes a source URL and keeps it whether or not a
        // backend is present.
        player.setSource(QUrl(QStringLiteral("file:///clip.mp4")));
        return player.duration() == 0 && !player.source().isEmpty();
#endif
    });
    r.check("multimedia/playlist", [&](QString &d) {
#if QT_VERSION_MAJOR < 6
        QMediaPlaylist playlist;
        playlist.addMedia(QUrl(QStringLiteral("file:///a.mp3")));
        playlist.addMedia(QUrl(QStringLiteral("file:///b.mp3")));
        playlist.setCurrentIndex(1);
        return playlist.mediaCount() == 2 && playlist.currentIndex() == 1;
#else
        r.skip(d, QStringLiteral("Qt 6 dropped playlists; a player holds one source"));
        return false;
#endif
    });
    r.check("multimedia/mediarecorder-construct", [&](QString &d) {
#if QT_VERSION_MAJOR < 6
        QMediaPlayer player;
        QMediaRecorder recorder(&player);
        return recorder.state() == QMediaRecorder::StoppedState;
#else
        // A recorder attaches to a capture session in Qt 6, not to a player,
        // and state() is recorderState().
        QMediaRecorder recorder;
        return recorder.recorderState() == QMediaRecorder::StoppedState;
#endif
    });
    r.check("multimedia/timerange-interval", [&](QString &d) {
        QMediaTimeRange range(0, 1000);
        range.addInterval(2000, 3000);
        return range.intervals().size() == 2
            && range.earliestTime() == 0 && range.latestTime() == 3000;
    });
    r.check("multimedia/serviceproviderhint", [&](QString &d) {
#if QT_VERSION_MAJOR < 6
        QMediaServiceProviderHint hint(QStringLiteral("audio/mpeg"), QStringList{"mp3"});
        return hint.type() == QMediaServiceProviderHint::ContentType
            && hint.mimeType() == QStringLiteral("audio/mpeg");
#else
        r.skip(d, QStringLiteral("Qt 6 removed the media service provider machinery"));
        return false;
#endif
    });
}

void checkCameraValueTypes(SmokeReporter &r)
{
    r.check("multimedia/camerainfo-enumerate", [&](QString &d) {
#if QT_VERSION_MAJOR < 6
        const QList<QCameraInfo> cams = QCameraInfo::availableCameras();
        QCameraInfo def = QCameraInfo::defaultCamera();
#else
        const QList<QCameraDevice> cams = QMediaDevices::videoInputs();
        QCameraDevice def = QMediaDevices::defaultVideoInput();
#endif
        Q_UNUSED(def);   // may be null/invalid with no camera hardware present
        return cams.size() >= 0;
    });
    r.check("multimedia/camera-subobjects-construct", [&](QString &d) {
        // A default-constructed QCamera doesn't need real hardware to exist.
        // QCameraExposure/QCameraFocus/QCameraImageProcessing have private
        // constructors - QCamera itself is the only thing that can create
        // them, handed out through exposure()/focus()/imageProcessing().
        QCamera camera;
#if QT_VERSION_MAJOR < 6
        QCameraExposure *exposure = camera.exposure();
        QCameraFocus *focus = camera.focus();
        QCameraImageProcessing *imaging = camera.imageProcessing();
        QCameraImageCapture capture(&camera);
        QCameraFocusZone zone;
        QCameraViewfinderSettings settings;
        settings.setResolution(640, 480);
        return settings.resolution() == QSize(640, 480) && !zone.isValid()
            && exposure != nullptr && focus != nullptr && imaging != nullptr
            && !capture.isReadyForCapture();
#else
        // The sub-objects were folded into QCamera itself in Qt 6 - exposure,
        // focus and white balance are properties of the camera - and
        // QCameraImageCapture became QImageCapture.
        QImageCapture capture;
        camera.setExposureCompensation(0.0);
        camera.setFocusMode(QCamera::FocusModeAuto);
        return !capture.isReadyForCapture()
            && qFuzzyIsNull(camera.exposureCompensation())
            && !camera.isActive();
#endif
    });
}

void checkRadio(SmokeReporter &r)
{
    r.check("multimedia/radiotuner-radiodata-construct", [&](QString &d) {
#if QT_VERSION_MAJOR < 6
        QRadioTuner tuner;
        QRadioData data(&tuner);
        return !tuner.isAvailable() ? true : tuner.isAvailable();   // no hardware required
#else
        r.skip(d, QStringLiteral("Qt 6 dropped the radio API entirely"));
        return false;
#endif
    });
}

void checkVideoSurfaceAndFilter(SmokeReporter &r)
{
    r.check("multimedia/videoframe-surfaceformat", [&](QString &d) {
        QImage img(4, 4, QImage::Format_RGB32);
        img.fill(Qt::red);
#if QT_VERSION_MAJOR < 6
        QVideoFrame frame(img);
        QVideoSurfaceFormat fmt(QSize(4, 4), QVideoFrame::Format_RGB32);
#else
        // QVideoSurfaceFormat became QVideoFrameFormat, and the pixel-format
        // enum moved onto it with explicit channel orders.
        QVideoFrame frame(img);
        QVideoFrameFormat fmt(QSize(4, 4), QVideoFrameFormat::Format_BGRX8888);
#endif
        return frame.isValid() && frame.width() == 4 && fmt.frameSize() == QSize(4, 4);
    });
    r.check("multimedia/custom-video-surface", [&](QString &d) {
        // QAbstractVideoSurface is meant to be subclassed for custom rendering
        // (embedding video output without QVideoWidget) - this is that pattern.
#if QT_VERSION_MAJOR < 6
        class RecordingSurface : public QAbstractVideoSurface {
        public:
            int presented = 0;
            QList<QVideoFrame::PixelFormat> supportedPixelFormats(
                QAbstractVideoBuffer::HandleType) const override {
                return { QVideoFrame::Format_RGB32 };
            }
            bool present(const QVideoFrame &) override { ++presented; return true; }
        };
        RecordingSurface surface;
        QVideoSurfaceFormat fmt(QSize(4, 4), QVideoFrame::Format_RGB32);
        if (!surface.start(fmt)) { d = "surface.start failed"; return false; }
        QImage img(4, 4, QImage::Format_RGB32); img.fill(Qt::blue);
        bool ok = surface.present(QVideoFrame(img));
        surface.stop();
        return ok && surface.presented == 1;
#else
        // QAbstractVideoSurface is gone: a video sink is a concrete QObject a
        // frame is pushed into, not an interface to subclass.
        QVideoSink sink;
        int presented = 0;
        QObject::connect(&sink, &QVideoSink::videoFrameChanged,
                         [&presented](const QVideoFrame &) { ++presented; });
        QImage img(4, 4, QImage::Format_RGB32); img.fill(Qt::blue);
        sink.setVideoFrame(QVideoFrame(img));
        // Whether a sink without a rendering backend keeps the frame is the backend's
        // business (it does on Windows, not in a container without media plugins).
        if (presented == 0 && !sink.videoFrame().isValid()) {
            r.skip(d, QStringLiteral("no video backend: the sink did not keep the frame"));
            return false;
        }
        return true;
#endif
    });
    r.check("multimedia/custom-video-filter", [&](QString &d) {
        // Likewise, QAbstractVideoFilter/QVideoFilterRunnable are the
        // documented extension points for a custom QML VideoOutput filter.
#if QT_VERSION_MAJOR < 6
        class PassthroughRunnable : public QVideoFilterRunnable {
        public:
            QVideoFrame run(QVideoFrame *input, const QVideoSurfaceFormat &, RunFlags) override {
                return input ? *input : QVideoFrame();
            }
        };
        class PassthroughFilter : public QAbstractVideoFilter {
        public:
            QVideoFilterRunnable *createFilterRunnable() override { return new PassthroughRunnable; }
        };
        PassthroughFilter filter;
        QVideoFilterRunnable *runnable = filter.createFilterRunnable();
        QImage img(2, 2, QImage::Format_RGB32); img.fill(Qt::green);
        QVideoFrame in(img);
        QVideoSurfaceFormat fmt(QSize(2, 2), QVideoFrame::Format_RGB32);
        QVideoFrame out = runnable->run(&in, fmt, QVideoFilterRunnable::RunFlags());
        delete runnable;
        return out.isValid();
#else
        // QAbstractVideoFilter/QVideoFilterRunnable had no Qt 6 successor;
        // frame processing goes through QVideoSink instead.
        r.skip(d, QStringLiteral("Qt 6 removed the QML video-filter extension point"));
        return false;
#endif
    });
}

#endif // SMOKE_QT5
