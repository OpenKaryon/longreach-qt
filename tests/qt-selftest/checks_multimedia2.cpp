// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// The rest of QtMultimedia: the backend SPI (the *Control/*Interface/*Plugin
// types) that checks_multimedia.cpp deliberately left out as "not meant for
// app code" - which is true for calling them, but a real backend plugin
// author has to subclass and implement every one of these, so a minimal-but-
// real subclass exercising the real public API is exactly the documented,
// non-fake way to reach them (the same pattern already used for sensors'/
// location's backend SPIs). Nothing here requires a working audio/camera/
// radio backend to be present - every check just proves the interface is
// genuinely implementable and wired the way Qt's own backends wire it.
#include "../common/smokecheck.h"

#if !SMOKE_QT5

static void skipModernMultimediaSpi(SmokeReporter &r, const char *name)
{
    r.check(QString::fromLatin1(name), [&](QString &d) {
        r.skip(d, QStringLiteral("the Qt 5 multimedia service/control API has no Qt 4 counterpart here"));
        return false;
    });
}

void checkMultimediaValueTypes2(SmokeReporter &r) { skipModernMultimediaSpi(r, "multimedia/value-types2"); }
void checkAbstractAudioBackendClasses(SmokeReporter &r) { skipModernMultimediaSpi(r, "multimedia/abstract-audio-backend"); }
void checkAudioSelectorRoleControls(SmokeReporter &r) { skipModernMultimediaSpi(r, "multimedia/audio-selector-role-controls"); }
void checkCameraControlSuite(SmokeReporter &r) { skipModernMultimediaSpi(r, "multimedia/camera-control-suite"); }
void checkMediaPlaybackRecordingControls(SmokeReporter &r) { skipModernMultimediaSpi(r, "multimedia/playback-recording-controls"); }
void checkRadioControlSuite(SmokeReporter &r) { skipModernMultimediaSpi(r, "multimedia/radio-control-suite"); }
void checkVideoControlSuite(SmokeReporter &r) { skipModernMultimediaSpi(r, "multimedia/video-control-suite"); }
void checkMediaServiceProviderInterfaces(SmokeReporter &r) { skipModernMultimediaSpi(r, "multimedia/service-provider-interfaces"); }

#else

#if QT_VERSION_MAJOR < 6
#include <QMediaControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QMediaService>
#endif
#if QT_VERSION_MAJOR < 6
#include <QMediaBindableInterface>
#endif
#if QT_VERSION_MAJOR < 6
#include <QMediaServiceProviderPlugin>
#endif
#include <QMediaTimeRange>

#if QT_VERSION_MAJOR < 6
#include <QAbstractAudioDeviceInfo>
#endif
#if QT_VERSION_MAJOR < 6
#include <QAbstractAudioInput>
#endif
#if QT_VERSION_MAJOR < 6
#include <QAbstractAudioOutput>
#endif
#if QT_VERSION_MAJOR < 6
#include <QAbstractPlanarVideoBuffer>
#endif
#include <QAudioFormat>
#if QT_VERSION_MAJOR < 6
#include <QAudioEncoderSettings>
#endif
#if QT_VERSION_MAJOR < 6
#include <QImageEncoderSettings>
#endif
#if QT_VERSION_MAJOR < 6
#include <QImageEncoderControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QVideoEncoderSettings>
#endif

#if QT_VERSION_MAJOR < 6
#include <QAudioDecoderControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QAudioEncoderSettingsControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QAudioInputSelectorControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QAudioOutputSelectorControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QAudioRoleControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QCustomAudioRoleControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QAudioSystemPlugin>
#endif

#if QT_VERSION_MAJOR < 6
#include <QCameraCaptureBufferFormatControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QCameraCaptureDestinationControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QCameraControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QCameraExposureControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QCameraFeedbackControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QCameraFlashControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QCameraFocusControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QCameraImageCaptureControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QCameraImageProcessingControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QCameraInfoControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QCameraLocksControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QCameraViewfinderSettingsControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QCameraViewfinderSettingsControl2>
#endif
#if QT_VERSION_MAJOR < 6
#include <QCameraZoomControl>
#endif
#include <QCamera>
#if QT_VERSION_MAJOR < 6
#include <QCameraExposure>
#endif
#if QT_VERSION_MAJOR < 6
#include <QCameraFocus>
#endif
#if QT_VERSION_MAJOR < 6
#include <QCameraImageCapture>
#endif

#if QT_VERSION_MAJOR < 6
#include <QMediaAudioProbeControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QMediaAvailabilityControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QMediaContainerControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QMediaGaplessPlaybackControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QMediaPlayerControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QMediaRecorderControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QMediaStreamsControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QMediaVideoProbeControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QMetaDataReaderControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QMetaDataWriterControl>
#endif
#include <QMediaPlayer>
#include <QMediaRecorder>
#if QT_VERSION_MAJOR < 6
#include <QMediaContent>
#endif

#if QT_VERSION_MAJOR < 6
#include <QRadioDataControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QRadioTunerControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QRadioTuner>
#endif
#if QT_VERSION_MAJOR < 6
#include <QRadioData>
#endif

#if QT_VERSION_MAJOR < 6
#include <QVideoDeviceSelectorControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QVideoEncoderSettingsControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QVideoProbe>
#endif
#if QT_VERSION_MAJOR < 6
#include <QVideoRendererControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QVideoWindowControl>
#endif
#if QT_VERSION_MAJOR < 6
#include <QAbstractVideoSurface>
#endif

#if QT_VERSION_MAJOR < 6

namespace {

// --- QMediaBindableInterface + a QMediaControl base touch --------------

class FixedAudioProbeControl : public QMediaAudioProbeControl {
public:
    using QMediaAudioProbeControl::QMediaAudioProbeControl;
};

class FixedBindable : public QObject, public QMediaBindableInterface {
public:
    QMediaObject *mediaObject() const override { return nullptr; }
protected:
    bool setMediaObject(QMediaObject *) override { return true; }
};

// --- abstract audio device/input/output + the plugin factory -----------

class FixedAudioDeviceInfo : public QAbstractAudioDeviceInfo {
public:
    QAudioFormat preferredFormat() const override { return QAudioFormat(); }
    bool isFormatSupported(const QAudioFormat &) const override { return true; }
    QString deviceName() const override { return QStringLiteral("qt-smoke-device"); }
    QStringList supportedCodecs() override { return { QStringLiteral("audio/pcm") }; }
    QList<int> supportedSampleRates() override { return { 8000, 44100 }; }
    QList<int> supportedChannelCounts() override { return { 1, 2 }; }
    QList<int> supportedSampleSizes() override { return { 8, 16 }; }
    QList<QAudioFormat::Endian> supportedByteOrders() override { return { QAudioFormat::LittleEndian }; }
    QList<QAudioFormat::SampleType> supportedSampleTypes() override { return { QAudioFormat::SignedInt }; }
};

class FixedAudioInput : public QAbstractAudioInput {
public:
    void start(QIODevice *) override {}
    QIODevice *start() override { return nullptr; }
    void stop() override {}
    void reset() override {}
    void suspend() override {}
    void resume() override {}
    int bytesReady() const override { return 0; }
    int periodSize() const override { return 0; }
    void setBufferSize(int) override {}
    int bufferSize() const override { return 0; }
    void setNotifyInterval(int) override {}
    int notifyInterval() const override { return 0; }
    qint64 processedUSecs() const override { return 0; }
    qint64 elapsedUSecs() const override { return 0; }
    QAudio::Error error() const override { return QAudio::NoError; }
    QAudio::State state() const override { return QAudio::StoppedState; }
    void setFormat(const QAudioFormat &) override {}
    QAudioFormat format() const override { return QAudioFormat(); }
    void setVolume(qreal) override {}
    qreal volume() const override { return 1.0; }
};

class FixedAudioOutput : public QAbstractAudioOutput {
public:
    void start(QIODevice *) override {}
    QIODevice *start() override { return nullptr; }
    void stop() override {}
    void reset() override {}
    void suspend() override {}
    void resume() override {}
    int bytesFree() const override { return 0; }
    int periodSize() const override { return 0; }
    void setBufferSize(int) override {}
    int bufferSize() const override { return 0; }
    void setNotifyInterval(int) override {}
    int notifyInterval() const override { return 0; }
    qint64 processedUSecs() const override { return 0; }
    qint64 elapsedUSecs() const override { return 0; }
    QAudio::Error error() const override { return QAudio::NoError; }
    QAudio::State state() const override { return QAudio::StoppedState; }
    void setFormat(const QAudioFormat &) override {}
    QAudioFormat format() const override { return QAudioFormat(); }
};

class FixedAudioSystemPlugin : public QAudioSystemPlugin {
public:
    using QAudioSystemPlugin::QAudioSystemPlugin;
    QList<QByteArray> availableDevices(QAudio::Mode) const override { return { "default" }; }
    QAbstractAudioInput *createInput(const QByteArray &) override { return new FixedAudioInput; }
    QAbstractAudioOutput *createOutput(const QByteArray &) override { return new FixedAudioOutput; }
    QAbstractAudioDeviceInfo *createDeviceInfo(const QByteArray &, QAudio::Mode) override { return new FixedAudioDeviceInfo; }
};

class FixedPlanarVideoBuffer : public QAbstractPlanarVideoBuffer {
public:
    FixedPlanarVideoBuffer() : QAbstractPlanarVideoBuffer(NoHandle) {}
    MapMode mapMode() const override { return NotMapped; }
    uchar *map(MapMode, int *numBytes, int *bytesPerLine) override {
        if (numBytes) *numBytes = 0;
        if (bytesPerLine) *bytesPerLine = 0;
        return nullptr;
    }
    void unmap() override {}
    int map(MapMode, int *numBytes, int bytesPerLine[4], uchar *data[4]) override {
        if (numBytes) *numBytes = 0;
        for (int i = 0; i < 4; ++i) { bytesPerLine[i] = 0; data[i] = nullptr; }
        return 0;
    }
};

// --- audio selector/role controls ---------------------------------------

class FixedAudioDecoderControl : public QAudioDecoderControl {
public:
    using QAudioDecoderControl::QAudioDecoderControl;
    QAudioDecoder::State state() const override { return QAudioDecoder::StoppedState; }
    QString sourceFilename() const override { return QString(); }
    void setSourceFilename(const QString &) override {}
    QIODevice *sourceDevice() const override { return nullptr; }
    void setSourceDevice(QIODevice *) override {}
    void start() override {}
    void stop() override {}
    QAudioFormat audioFormat() const override { return QAudioFormat(); }
    void setAudioFormat(const QAudioFormat &) override {}
    QAudioBuffer read() override { return QAudioBuffer(); }
    bool bufferAvailable() const override { return false; }
    qint64 position() const override { return 0; }
    qint64 duration() const override { return 0; }
};

class FixedAudioEncoderSettingsControl : public QAudioEncoderSettingsControl {
public:
    using QAudioEncoderSettingsControl::QAudioEncoderSettingsControl;
    QStringList supportedAudioCodecs() const override { return { QStringLiteral("audio/pcm") }; }
    QString codecDescription(const QString &) const override { return QStringLiteral("PCM"); }
    QList<int> supportedSampleRates(const QAudioEncoderSettings &, bool *continuous) const override {
        if (continuous) *continuous = false;
        return { 44100 };
    }
    QAudioEncoderSettings audioSettings() const override { return QAudioEncoderSettings(); }
    void setAudioSettings(const QAudioEncoderSettings &) override {}
};

class FixedAudioInputSelectorControl : public QAudioInputSelectorControl {
public:
    using QAudioInputSelectorControl::QAudioInputSelectorControl;
    QList<QString> availableInputs() const override { return { QStringLiteral("mic") }; }
    QString inputDescription(const QString &) const override { return QStringLiteral("Microphone"); }
    QString defaultInput() const override { return QStringLiteral("mic"); }
    QString activeInput() const override { return QStringLiteral("mic"); }
    void setActiveInput(const QString &) override {}
};

class FixedAudioOutputSelectorControl : public QAudioOutputSelectorControl {
public:
    using QAudioOutputSelectorControl::QAudioOutputSelectorControl;
    QList<QString> availableOutputs() const override { return { QStringLiteral("speaker") }; }
    QString outputDescription(const QString &) const override { return QStringLiteral("Speaker"); }
    QString defaultOutput() const override { return QStringLiteral("speaker"); }
    QString activeOutput() const override { return QStringLiteral("speaker"); }
    void setActiveOutput(const QString &) override {}
};

class FixedAudioRoleControl : public QAudioRoleControl {
public:
    using QAudioRoleControl::QAudioRoleControl;
    QAudio::Role audioRole() const override { return QAudio::MusicRole; }
    void setAudioRole(QAudio::Role) override {}
    QList<QAudio::Role> supportedAudioRoles() const override { return { QAudio::MusicRole }; }
};

class FixedCustomAudioRoleControl : public QCustomAudioRoleControl {
public:
    using QCustomAudioRoleControl::QCustomAudioRoleControl;
    QString customAudioRole() const override { return QString(); }
    void setCustomAudioRole(const QString &) override {}
    QStringList supportedCustomAudioRoles() const override { return QStringList(); }
};

// --- camera controls -----------------------------------------------------

class FixedCameraControl : public QCameraControl {
public:
    using QCameraControl::QCameraControl;
    QCamera::State state() const override { return QCamera::UnloadedState; }
    void setState(QCamera::State) override {}
    QCamera::Status status() const override { return QCamera::UnloadedStatus; }
    QCamera::CaptureModes captureMode() const override { return QCamera::CaptureStillImage; }
    void setCaptureMode(QCamera::CaptureModes) override {}
    bool isCaptureModeSupported(QCamera::CaptureModes) const override { return true; }
    bool canChangeProperty(PropertyChangeType, QCamera::Status) const override { return true; }
};

class FixedImageEncoderControl : public QImageEncoderControl {
public:
    using QImageEncoderControl::QImageEncoderControl;
    QStringList supportedImageCodecs() const override { return { QStringLiteral("image/jpeg") }; }
    QString imageCodecDescription(const QString &) const override { return QStringLiteral("JPEG"); }
    QList<QSize> supportedResolutions(const QImageEncoderSettings &, bool *continuous) const override {
        if (continuous) *continuous = false;
        return { QSize(1024, 768) };
    }
    QImageEncoderSettings imageSettings() const override { return m_settings; }
    void setImageSettings(const QImageEncoderSettings &settings) override { m_settings = settings; }
private:
    QImageEncoderSettings m_settings;
};

class FixedCameraCaptureBufferFormatControl : public QCameraCaptureBufferFormatControl {
public:
    using QCameraCaptureBufferFormatControl::QCameraCaptureBufferFormatControl;
    QList<QVideoFrame::PixelFormat> supportedBufferFormats() const override { return { QVideoFrame::Format_RGB32 }; }
    QVideoFrame::PixelFormat bufferFormat() const override { return QVideoFrame::Format_RGB32; }
    void setBufferFormat(QVideoFrame::PixelFormat) override {}
};

class FixedCameraCaptureDestinationControl : public QCameraCaptureDestinationControl {
public:
    using QCameraCaptureDestinationControl::QCameraCaptureDestinationControl;
    bool isCaptureDestinationSupported(QCameraImageCapture::CaptureDestinations) const override { return true; }
    QCameraImageCapture::CaptureDestinations captureDestination() const override { return QCameraImageCapture::CaptureToFile; }
    void setCaptureDestination(QCameraImageCapture::CaptureDestinations) override {}
};

class FixedCameraExposureControl : public QCameraExposureControl {
public:
    using QCameraExposureControl::QCameraExposureControl;
    bool isParameterSupported(ExposureParameter) const override { return true; }
    QVariantList supportedParameterRange(ExposureParameter, bool *continuous) const override {
        if (continuous) *continuous = false;
        return QVariantList();
    }
    QVariant requestedValue(ExposureParameter) const override { return QVariant(); }
    QVariant actualValue(ExposureParameter) const override { return QVariant(); }
    bool setValue(ExposureParameter, const QVariant &) override { return true; }
};

class FixedCameraFeedbackControl : public QCameraFeedbackControl {
public:
    using QCameraFeedbackControl::QCameraFeedbackControl;
    bool isEventFeedbackLocked(EventType) const override { return false; }
    bool isEventFeedbackEnabled(EventType) const override { return false; }
    bool setEventFeedbackEnabled(EventType, bool) override { return true; }
    void resetEventFeedback(EventType) override {}
    bool setEventFeedbackSound(EventType, const QString &) override { return true; }
};

class FixedCameraFlashControl : public QCameraFlashControl {
public:
    using QCameraFlashControl::QCameraFlashControl;
    QCameraExposure::FlashModes flashMode() const override { return QCameraExposure::FlashOff; }
    void setFlashMode(QCameraExposure::FlashModes) override {}
    bool isFlashModeSupported(QCameraExposure::FlashModes) const override { return true; }
    bool isFlashReady() const override { return false; }
};

class FixedCameraFocusControl : public QCameraFocusControl {
public:
    using QCameraFocusControl::QCameraFocusControl;
    QCameraFocus::FocusModes focusMode() const override { return QCameraFocus::AutoFocus; }
    void setFocusMode(QCameraFocus::FocusModes) override {}
    bool isFocusModeSupported(QCameraFocus::FocusModes) const override { return true; }
    QCameraFocus::FocusPointMode focusPointMode() const override { return QCameraFocus::FocusPointAuto; }
    void setFocusPointMode(QCameraFocus::FocusPointMode) override {}
    bool isFocusPointModeSupported(QCameraFocus::FocusPointMode) const override { return true; }
    QPointF customFocusPoint() const override { return QPointF(0.5, 0.5); }
    void setCustomFocusPoint(const QPointF &) override {}
    QCameraFocusZoneList focusZones() const override { return QCameraFocusZoneList(); }
};

class FixedCameraImageCaptureControl : public QCameraImageCaptureControl {
public:
    using QCameraImageCaptureControl::QCameraImageCaptureControl;
    bool isReadyForCapture() const override { return false; }
    QCameraImageCapture::DriveMode driveMode() const override { return QCameraImageCapture::SingleImageCapture; }
    void setDriveMode(QCameraImageCapture::DriveMode) override {}
    int capture(const QString &) override { return 0; }
    void cancelCapture() override {}
};

class FixedCameraImageProcessingControl : public QCameraImageProcessingControl {
public:
    using QCameraImageProcessingControl::QCameraImageProcessingControl;
    bool isParameterSupported(ProcessingParameter) const override { return true; }
    bool isParameterValueSupported(ProcessingParameter, const QVariant &) const override { return true; }
    QVariant parameter(ProcessingParameter) const override { return QVariant(); }
    void setParameter(ProcessingParameter, const QVariant &) override {}
};

class FixedCameraInfoControl : public QCameraInfoControl {
public:
    using QCameraInfoControl::QCameraInfoControl;
    QCamera::Position cameraPosition(const QString &) const override { return QCamera::UnspecifiedPosition; }
    int cameraOrientation(const QString &) const override { return 0; }
};

class FixedCameraLocksControl : public QCameraLocksControl {
public:
    using QCameraLocksControl::QCameraLocksControl;
    QCamera::LockTypes supportedLocks() const override { return QCamera::LockFocus; }
    QCamera::LockStatus lockStatus(QCamera::LockType) const override { return QCamera::Unlocked; }
    void searchAndLock(QCamera::LockTypes) override {}
    void unlock(QCamera::LockTypes) override {}
};

class FixedCameraViewfinderSettingsControl : public QCameraViewfinderSettingsControl {
public:
    using QCameraViewfinderSettingsControl::QCameraViewfinderSettingsControl;
    bool isViewfinderParameterSupported(ViewfinderParameter) const override { return true; }
    QVariant viewfinderParameter(ViewfinderParameter) const override { return QVariant(); }
    void setViewfinderParameter(ViewfinderParameter, const QVariant &) override {}
};

class FixedCameraViewfinderSettingsControl2 : public QCameraViewfinderSettingsControl2 {
public:
    using QCameraViewfinderSettingsControl2::QCameraViewfinderSettingsControl2;
    QList<QCameraViewfinderSettings> supportedViewfinderSettings() const override { return {}; }
    QCameraViewfinderSettings viewfinderSettings() const override { return QCameraViewfinderSettings(); }
    void setViewfinderSettings(const QCameraViewfinderSettings &) override {}
};

class FixedCameraZoomControl : public QCameraZoomControl {
public:
    using QCameraZoomControl::QCameraZoomControl;
    qreal maximumOpticalZoom() const override { return 1.0; }
    qreal maximumDigitalZoom() const override { return 1.0; }
    qreal requestedOpticalZoom() const override { return 1.0; }
    qreal requestedDigitalZoom() const override { return 1.0; }
    qreal currentOpticalZoom() const override { return 1.0; }
    qreal currentDigitalZoom() const override { return 1.0; }
    void zoomTo(qreal, qreal) override {}
};

// --- media player/recorder/container/streams controls -------------------

class FixedMediaContainerControl : public QMediaContainerControl {
public:
    using QMediaContainerControl::QMediaContainerControl;
    QStringList supportedContainers() const override { return { QStringLiteral("mp4") }; }
    QString containerFormat() const override { return QStringLiteral("mp4"); }
    void setContainerFormat(const QString &) override {}
    QString containerDescription(const QString &) const override { return QStringLiteral("MPEG-4"); }
};

class FixedMediaGaplessPlaybackControl : public QMediaGaplessPlaybackControl {
public:
    using QMediaGaplessPlaybackControl::QMediaGaplessPlaybackControl;
    QMediaContent nextMedia() const override { return QMediaContent(); }
    void setNextMedia(const QMediaContent &) override {}
    bool isCrossfadeSupported() const override { return false; }
    qreal crossfadeTime() const override { return 0; }
    void setCrossfadeTime(qreal) override {}
};

class FixedMediaPlayerControl : public QMediaPlayerControl {
public:
    using QMediaPlayerControl::QMediaPlayerControl;
    QMediaPlayer::State state() const override { return QMediaPlayer::StoppedState; }
    QMediaPlayer::MediaStatus mediaStatus() const override { return QMediaPlayer::NoMedia; }
    qint64 duration() const override { return 0; }
    qint64 position() const override { return 0; }
    void setPosition(qint64) override {}
    int volume() const override { return 100; }
    void setVolume(int) override {}
    bool isMuted() const override { return false; }
    void setMuted(bool) override {}
    int bufferStatus() const override { return 0; }
    bool isAudioAvailable() const override { return false; }
    bool isVideoAvailable() const override { return false; }
    bool isSeekable() const override { return false; }
    QMediaTimeRange availablePlaybackRanges() const override { return QMediaTimeRange(); }
    qreal playbackRate() const override { return 1.0; }
    void setPlaybackRate(qreal) override {}
    QMediaContent media() const override { return m_media; }
    const QIODevice *mediaStream() const override { return nullptr; }
    void setMedia(const QMediaContent &media, QIODevice *) override { m_media = media; }
    void play() override {}
    void pause() override {}
    void stop() override {}
private:
    QMediaContent m_media;
};

class FixedMediaRecorderControl : public QMediaRecorderControl {
public:
    using QMediaRecorderControl::QMediaRecorderControl;
    QUrl outputLocation() const override { return QUrl(); }
    bool setOutputLocation(const QUrl &) override { return true; }
    QMediaRecorder::State state() const override { return QMediaRecorder::StoppedState; }
    QMediaRecorder::Status status() const override { return QMediaRecorder::UnloadedStatus; }
    qint64 duration() const override { return 0; }
    bool isMuted() const override { return false; }
    qreal volume() const override { return 1.0; }
    void applySettings() override {}
    void setState(QMediaRecorder::State) override {}
    void setMuted(bool) override {}
    void setVolume(qreal) override {}
};

class FixedMediaStreamsControl : public QMediaStreamsControl {
public:
    using QMediaStreamsControl::QMediaStreamsControl;
    int streamCount() override { return 1; }
    StreamType streamType(int) override { return AudioStream; }
    QVariant metaData(int, const QString &) override { return QVariant(); }
    bool isActive(int) override { return true; }
    void setActive(int, bool) override {}
};

class FixedMediaVideoProbeControl : public QMediaVideoProbeControl {
public:
    using QMediaVideoProbeControl::QMediaVideoProbeControl;
};

class FixedMetaDataReaderControl : public QMetaDataReaderControl {
public:
    using QMetaDataReaderControl::QMetaDataReaderControl;
    bool isMetaDataAvailable() const override { return false; }
    QVariant metaData(const QString &) const override { return QVariant(); }
    QStringList availableMetaData() const override { return QStringList(); }
};

class FixedMetaDataWriterControl : public QMetaDataWriterControl {
public:
    using QMetaDataWriterControl::QMetaDataWriterControl;
    bool isWritable() const override { return false; }
    bool isMetaDataAvailable() const override { return false; }
    QVariant metaData(const QString &) const override { return QVariant(); }
    void setMetaData(const QString &, const QVariant &) override {}
    QStringList availableMetaData() const override { return QStringList(); }
};

class FixedMediaAvailabilityControl : public QMediaAvailabilityControl {
public:
    using QMediaAvailabilityControl::QMediaAvailabilityControl;
    QMultimedia::AvailabilityStatus availability() const override { return QMultimedia::Available; }
};

// --- radio controls -------------------------------------------------------

class FixedRadioTunerControl : public QRadioTunerControl {
public:
    using QRadioTunerControl::QRadioTunerControl;
    QRadioTuner::State state() const override { return QRadioTuner::StoppedState; }
    QRadioTuner::Band band() const override { return QRadioTuner::FM; }
    void setBand(QRadioTuner::Band) override {}
    bool isBandSupported(QRadioTuner::Band) const override { return true; }
    int frequency() const override { return 100000000; }
    int frequencyStep(QRadioTuner::Band) const override { return 100000; }
    QPair<int, int> frequencyRange(QRadioTuner::Band) const override { return { 87500000, 108000000 }; }
    void setFrequency(int) override {}
    bool isStereo() const override { return true; }
    QRadioTuner::StereoMode stereoMode() const override { return QRadioTuner::Auto; }
    void setStereoMode(QRadioTuner::StereoMode) override {}
    int signalStrength() const override { return 0; }
    int volume() const override { return 50; }
    void setVolume(int) override {}
    bool isMuted() const override { return false; }
    void setMuted(bool) override {}
    bool isSearching() const override { return false; }
    void searchForward() override {}
    void searchBackward() override {}
    void searchAllStations(QRadioTuner::SearchMode) override {}
    void cancelSearch() override {}
    void start() override {}
    void stop() override {}
    QRadioTuner::Error error() const override { return QRadioTuner::NoError; }
    QString errorString() const override { return QString(); }
};

class FixedRadioDataControl : public QRadioDataControl {
public:
    using QRadioDataControl::QRadioDataControl;
    QString stationId() const override { return QString(); }
    QRadioData::ProgramType programType() const override { return QRadioData::Undefined; }
    QString programTypeName() const override { return QString(); }
    QString stationName() const override { return QString(); }
    QString radioText() const override { return QString(); }
    void setAlternativeFrequenciesEnabled(bool) override {}
    bool isAlternativeFrequenciesEnabled() const override { return false; }
    QRadioData::Error error() const override { return QRadioData::NoError; }
    QString errorString() const override { return QString(); }
};

// --- video controls ---------------------------------------------------

class FixedVideoDeviceSelectorControl : public QVideoDeviceSelectorControl {
public:
    using QVideoDeviceSelectorControl::QVideoDeviceSelectorControl;
    int deviceCount() const override { return 1; }
    QString deviceName(int) const override { return QStringLiteral("device0"); }
    QString deviceDescription(int) const override { return QStringLiteral("Default device"); }
    int defaultDevice() const override { return 0; }
    int selectedDevice() const override { return 0; }
    void setSelectedDevice(int) override {}
};

class FixedVideoEncoderSettingsControl : public QVideoEncoderSettingsControl {
public:
    using QVideoEncoderSettingsControl::QVideoEncoderSettingsControl;
    QList<QSize> supportedResolutions(const QVideoEncoderSettings &, bool *continuous) const override {
        if (continuous) *continuous = false;
        return { QSize(640, 480) };
    }
    QList<qreal> supportedFrameRates(const QVideoEncoderSettings &, bool *continuous) const override {
        if (continuous) *continuous = false;
        return { 30.0 };
    }
    QStringList supportedVideoCodecs() const override { return { QStringLiteral("video/raw") }; }
    QString videoCodecDescription(const QString &) const override { return QStringLiteral("Raw video"); }
    QVideoEncoderSettings videoSettings() const override { return QVideoEncoderSettings(); }
    void setVideoSettings(const QVideoEncoderSettings &) override {}
};

class FixedVideoRendererControl : public QVideoRendererControl {
public:
    using QVideoRendererControl::QVideoRendererControl;
    QAbstractVideoSurface *surface() const override { return m_surface; }
    void setSurface(QAbstractVideoSurface *surface) override { m_surface = surface; }
private:
    QAbstractVideoSurface *m_surface = nullptr;
};

class FixedVideoWindowControl : public QVideoWindowControl {
public:
    using QVideoWindowControl::QVideoWindowControl;
    WId winId() const override { return 0; }
    void setWinId(WId) override {}
    QRect displayRect() const override { return m_rect; }
    void setDisplayRect(const QRect &rect) override { m_rect = rect; }
    bool isFullScreen() const override { return false; }
    void setFullScreen(bool) override {}
    void repaint() override {}
    QSize nativeSize() const override { return QSize(640, 480); }
    Qt::AspectRatioMode aspectRatioMode() const override { return Qt::KeepAspectRatio; }
    void setAspectRatioMode(Qt::AspectRatioMode) override {}
    int brightness() const override { return 0; }
    void setBrightness(int) override {}
    int contrast() const override { return 0; }
    void setContrast(int) override {}
    int hue() const override { return 0; }
    void setHue(int) override {}
    int saturation() const override { return 0; }
    void setSaturation(int) override {}
private:
    QRect m_rect;
};

// --- the service-provider plugin, implementing several interfaces at once
// (exactly how a real backend plugin, e.g. Qt's own gstreamer/directshow
// ones, mixes QMediaServiceProviderFactoryInterface with whichever of the
// optional capability interfaces it supports) --------------------------

class FixedServiceProviderPlugin : public QMediaServiceProviderPlugin,
                                    public QMediaServiceSupportedFormatsInterface,
                                    public QMediaServiceSupportedDevicesInterface,
                                    public QMediaServiceDefaultDeviceInterface,
                                    public QMediaServiceCameraInfoInterface,
                                    public QMediaServiceFeaturesInterface {
public:
    QMediaService *create(const QString &) override { return nullptr; }
    void release(QMediaService *) override {}
    QMultimedia::SupportEstimate hasSupport(const QString &, const QStringList &) const override {
        return QMultimedia::MaybeSupported;
    }
    QStringList supportedMimeTypes() const override { return { QStringLiteral("audio/pcm") }; }
    QList<QByteArray> devices(const QByteArray &) const override { return { "default" }; }
    QString deviceDescription(const QByteArray &, const QByteArray &) override { return QStringLiteral("Default"); }
    QByteArray defaultDevice(const QByteArray &) const override { return "default"; }
    QCamera::Position cameraPosition(const QByteArray &) const override { return QCamera::UnspecifiedPosition; }
    int cameraOrientation(const QByteArray &) const override { return 0; }
    QMediaServiceProviderHint::Features supportedFeatures(const QByteArray &) const override {
        return QMediaServiceProviderHint::Features();
    }
};

} // namespace

void checkMultimediaValueTypes2(SmokeReporter &r)
{
    r.check("multimedia/timeinterval", [&](QString &d) {
        QMediaTimeInterval iv(10, 20);
        QMediaTimeInterval iv2(iv);
        return iv.start() == 10 && iv.end() == 20 && iv.contains(15) && iv2 == iv;
    });
    r.check("multimedia/encoder-settings-values", [&](QString &d) {
        QAudioEncoderSettings audio;
        audio.setCodec(QStringLiteral("audio/pcm"));
        audio.setBitRate(128000);
        QVideoEncoderSettings video;
        video.setResolution(640, 480);
        video.setFrameRate(30.0);
        QImageEncoderSettings image;
        image.setResolution(1024, 768);
        image.setQuality(QMultimedia::HighQuality);
        return audio.codec() == QStringLiteral("audio/pcm") && audio.bitRate() == 128000
            && video.resolution() == QSize(640, 480) && image.resolution() == QSize(1024, 768);
    });
}

void checkAbstractAudioBackendClasses(SmokeReporter &r)
{
    r.check("multimedia/abstract-audio-io-plugin", [&](QString &d) {
        FixedAudioSystemPlugin plugin;
        // Reached through the real base every audio system plugin derives from.
        QAudioSystemFactoryInterface *factoryBase = &plugin;
        QAbstractAudioInput *input = factoryBase->createInput("default");
        QAbstractAudioOutput *output = factoryBase->createOutput("default");
        QAbstractAudioDeviceInfo *info = factoryBase->createDeviceInfo("default", QAudio::AudioOutput);
        bool ok = input != nullptr && output != nullptr && info != nullptr
            && info->deviceName() == QStringLiteral("qt-smoke-device");
        delete input; delete output; delete info;
        return ok;
    });
    r.check("multimedia/planar-video-buffer", [&](QString &d) {
        FixedPlanarVideoBuffer buffer;
        int numBytes = -1, lines[4];
        uchar *data[4];
        int planes = buffer.map(QAbstractVideoBuffer::NotMapped, &numBytes, lines, data);
        return planes == 0 && numBytes == 0;
    });
}

void checkAudioSelectorRoleControls(SmokeReporter &r)
{
    r.check("multimedia/audio-decoder-encoder-controls", [&](QString &d) {
        FixedAudioDecoderControl decoder;
        FixedAudioEncoderSettingsControl encoder;
        bool cont = true;
        encoder.supportedSampleRates(QAudioEncoderSettings(), &cont);
        return decoder.state() == QAudioDecoder::StoppedState && !cont
            && encoder.supportedAudioCodecs().contains(QStringLiteral("audio/pcm"));
    });
    r.check("multimedia/audio-selector-role-controls", [&](QString &d) {
        FixedAudioInputSelectorControl inSel;
        FixedAudioOutputSelectorControl outSel;
        FixedAudioRoleControl role;
        FixedCustomAudioRoleControl customRole;
        return inSel.activeInput() == QStringLiteral("mic") && outSel.activeOutput() == QStringLiteral("speaker")
            && role.audioRole() == QAudio::MusicRole && customRole.supportedCustomAudioRoles().isEmpty();
    });
}

void checkCameraControlSuite(SmokeReporter &r)
{
    r.check("multimedia/camera-core-controls", [&](QString &d) {
        FixedCameraControl camera;
        FixedCameraInfoControl info;
        FixedCameraLocksControl locks;
        bool ok = camera.state() == QCamera::UnloadedState
            && camera.canChangeProperty(QCameraControl::Viewfinder, QCamera::UnloadedStatus)
            && info.cameraPosition(QString()) == QCamera::UnspecifiedPosition
            && locks.supportedLocks() == QCamera::LockFocus;
        return ok;
    });
    r.check("multimedia/camera-exposure-flash-focus-controls", [&](QString &d) {
        FixedCameraExposureControl exposure;
        FixedCameraFlashControl flash;
        FixedCameraFocusControl focus;
        bool ok = exposure.setValue(QCameraExposureControl::ISO, 100)
            && flash.isFlashModeSupported(QCameraExposure::FlashOff)
            && focus.focusZones().isEmpty();
        return ok;
    });
    r.check("multimedia/camera-capture-controls", [&](QString &d) {
        FixedCameraImageCaptureControl capture;
        FixedCameraCaptureBufferFormatControl bufferFormat;
        FixedCameraCaptureDestinationControl destination;
        FixedImageEncoderControl imageEncoder;
        QImageEncoderSettings settings;
        settings.setResolution(1024, 768);
        imageEncoder.setImageSettings(settings);
        bool ok = capture.capture(QStringLiteral("out.jpg")) == 0
            && bufferFormat.bufferFormat() == QVideoFrame::Format_RGB32
            && destination.captureDestination() == QCameraImageCapture::CaptureToFile
            && imageEncoder.imageSettings().resolution() == QSize(1024, 768)
            && imageEncoder.supportedImageCodecs().contains(QStringLiteral("image/jpeg"));
        return ok;
    });
    r.check("multimedia/camera-imageprocessing-viewfinder-zoom-feedback", [&](QString &d) {
        FixedCameraImageProcessingControl imaging;
        FixedCameraViewfinderSettingsControl vf1;
        FixedCameraViewfinderSettingsControl2 vf2;
        FixedCameraZoomControl zoom;
        FixedCameraFeedbackControl feedback;
        bool ok = imaging.isParameterSupported(QCameraImageProcessingControl::Contrast)
            && vf1.isViewfinderParameterSupported(QCameraViewfinderSettingsControl::Resolution)
            && vf2.supportedViewfinderSettings().isEmpty()
            && qFuzzyCompare(zoom.maximumOpticalZoom(), 1.0)
            && !feedback.isEventFeedbackLocked(QCameraFeedbackControl::ImageCaptured);
        return ok;
    });
}

void checkMediaPlaybackRecordingControls(SmokeReporter &r)
{
    r.check("multimedia/media-player-recorder-controls", [&](QString &d) {
        FixedMediaPlayerControl player;
        FixedMediaRecorderControl recorder;
        player.setMedia(QMediaContent(QUrl(QStringLiteral("file:///clip.mp4"))), nullptr);
        recorder.setVolume(0.7);
        return player.media().canonicalUrl() == QUrl(QStringLiteral("file:///clip.mp4"))
            && recorder.state() == QMediaRecorder::StoppedState;
    });
    r.check("multimedia/media-container-gapless-streams-controls", [&](QString &d) {
        FixedMediaContainerControl container;
        FixedMediaGaplessPlaybackControl gapless;
        FixedMediaStreamsControl streams;
        return container.containerFormat() == QStringLiteral("mp4")
            && !gapless.isCrossfadeSupported() && streams.streamCount() == 1
            && streams.streamType(0) == QMediaStreamsControl::AudioStream;
    });
    r.check("multimedia/metadata-probe-availability-controls", [&](QString &d) {
        FixedMetaDataReaderControl reader;
        FixedMetaDataWriterControl writer;
        FixedAudioProbeControl audioProbe;
        FixedMediaVideoProbeControl videoProbe;
        FixedMediaAvailabilityControl availability;
        return !reader.isMetaDataAvailable() && !writer.isWritable()
            && availability.availability() == QMultimedia::Available;
    });
    r.check("multimedia/bindable-interface", [&](QString &d) {
        FixedBindable bindable;
        return bindable.mediaObject() == nullptr;
    });
}

void checkRadioControlSuite(SmokeReporter &r)
{
    r.check("multimedia/radio-tuner-data-controls", [&](QString &d) {
        FixedRadioTunerControl tuner;
        FixedRadioDataControl data;
        tuner.setFrequency(100000000);
        return tuner.band() == QRadioTuner::FM
            && data.programType() == QRadioData::Undefined;
    });
}

void checkVideoControlSuite(SmokeReporter &r)
{
    r.check("multimedia/video-device-encoder-controls", [&](QString &d) {
        FixedVideoDeviceSelectorControl selector;
        FixedVideoEncoderSettingsControl encoder;
        bool cont = true;
        encoder.supportedResolutions(QVideoEncoderSettings(), &cont);
        return selector.deviceCount() == 1 && !cont;
    });
    r.check("multimedia/video-renderer-window-controls", [&](QString &d) {
        class RecordingSurface : public QAbstractVideoSurface {
        public:
            QList<QVideoFrame::PixelFormat> supportedPixelFormats(QAbstractVideoBuffer::HandleType) const override {
                return { QVideoFrame::Format_RGB32 };
            }
            bool present(const QVideoFrame &) override { return true; }
        };
        RecordingSurface surface;
        FixedVideoRendererControl renderer;
        renderer.setSurface(&surface);
        FixedVideoWindowControl window;
        window.setDisplayRect(QRect(0, 0, 320, 240));
        return renderer.surface() == &surface && window.displayRect() == QRect(0, 0, 320, 240);
    });
    r.check("multimedia/video-probe", [&](QString &d) {
        QVideoProbe probe;
        return !probe.isActive();
    });
}

void checkMediaServiceProviderInterfaces(SmokeReporter &r)
{
    r.check("multimedia/service-provider-plugin-interfaces", [&](QString &d) {
        FixedServiceProviderPlugin plugin;
        // Reached through the real interface bases a backend plugin mixes in -
        // this is the actual documented multiple-inheritance pattern Qt's own
        // gstreamer/directshow backend plugins use.
        QMediaServiceProviderFactoryInterface *factory = &plugin;
        QMediaServiceSupportedFormatsInterface *formats = &plugin;
        QMediaServiceSupportedDevicesInterface *devices = &plugin;
        QMediaServiceDefaultDeviceInterface *defaultDev = &plugin;
        QMediaServiceCameraInfoInterface *cameraInfo = &plugin;
        QMediaServiceFeaturesInterface *features = &plugin;
        bool ok = factory->create(QStringLiteral("x")) == nullptr
            && formats->supportedMimeTypes().contains(QStringLiteral("audio/pcm"))
            && devices->devices("service").contains(QByteArray("default"))
            && defaultDev->defaultDevice("service") == QByteArray("default")
            && cameraInfo->cameraPosition("device") == QCamera::UnspecifiedPosition
            && features->supportedFeatures("service") == QMediaServiceProviderHint::Features();
        return ok;
    });
}

#else   // the checks above have no counterpart to run against

void checkMultimediaValueTypes2(SmokeReporter &r)
{
    r.check("multimedia/value-types2", [&](QString &d) {
        r.skip(d, QStringLiteral("Qt 6 replaced QMediaService and its control interfaces outright"));
        return false;
    });
}

void checkAbstractAudioBackendClasses(SmokeReporter &r)
{
    r.check("multimedia/abstract-audio-backend", [&](QString &d) {
        r.skip(d, QStringLiteral("Qt 6 replaced QMediaService and its control interfaces outright"));
        return false;
    });
}

void checkAudioSelectorRoleControls(SmokeReporter &r)
{
    r.check("multimedia/audio-selector-role-controls", [&](QString &d) {
        r.skip(d, QStringLiteral("Qt 6 replaced QMediaService and its control interfaces outright"));
        return false;
    });
}

void checkCameraControlSuite(SmokeReporter &r)
{
    r.check("multimedia/camera-control-suite", [&](QString &d) {
        r.skip(d, QStringLiteral("Qt 6 replaced QMediaService and its control interfaces outright"));
        return false;
    });
}

void checkMediaPlaybackRecordingControls(SmokeReporter &r)
{
    r.check("multimedia/playback-recording-controls", [&](QString &d) {
        r.skip(d, QStringLiteral("Qt 6 replaced QMediaService and its control interfaces outright"));
        return false;
    });
}

void checkRadioControlSuite(SmokeReporter &r)
{
    r.check("multimedia/radio-control-suite", [&](QString &d) {
        r.skip(d, QStringLiteral("Qt 6 replaced QMediaService and its control interfaces outright"));
        return false;
    });
}

void checkVideoControlSuite(SmokeReporter &r)
{
    r.check("multimedia/video-control-suite", [&](QString &d) {
        r.skip(d, QStringLiteral("Qt 6 replaced QMediaService and its control interfaces outright"));
        return false;
    });
}

void checkMediaServiceProviderInterfaces(SmokeReporter &r)
{
    r.check("multimedia/service-provider-interfaces", [&](QString &d) {
        r.skip(d, QStringLiteral("Qt 6 replaced QMediaService and its control interfaces outright"));
        return false;
    });
}

#endif

#endif // SMOKE_QT5
