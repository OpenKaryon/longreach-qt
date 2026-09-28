// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// The Qt 4 half of multimedia-lab: its window and its checks.
//
// Qt 4 and Qt 5 both ship a module called QtMultimedia, and they share the name
// and nothing else. Qt 4's is the low-level layer alone - audio devices,
// formats, a stream of samples, a video frame and a surface to draw it on. The
// player, the playlist, the camera and the video widget this app is built
// around arrived in Qt 5; in the Qt 4 era they lived in Qt Mobility's
// QtMultimediaKit, a separate project this kit does not build.
//
// So main.cpp's window and checks are compiled only on Qt 5 and Qt 6, and this
// file supplies the Qt 4 ones. Same application, same name, same --selftest
// contract; what differs is which QtMultimedia it is talking to.
//
// Nothing here is played or recorded. These run on build machines with no sound
// card, so a check that needed a working device would fail for the wrong
// reason. Where a device really is required, the check skips.

#include "../common/smokecheck.h"

#include <QAbstractVideoBuffer>
#include <QAbstractVideoSurface>
#include <QAudio>
#include <QAudioDeviceInfo>
#include <QAudioFormat>
#include <QAudioInput>
#include <QAudioEngineFactoryInterface>
#include <QAudioEnginePlugin>
#include <QAudioOutput>
#include <QImage>
#include <QList>
#include <QSize>
#include <QString>
#include <QStringList>
#include <QVideoFrame>
#include <QVideoSurfaceFormat>

#include <QLabel>
#include <QTabWidget>
#include <QTextEdit>
#include <QVBoxLayout>
#include <QWidget>
#include <QApplication>
#include <QCoreApplication>
#include <QDir>
#include <QPainter>

namespace {

// A QAbstractVideoSurface is pure virtual on both counts, so the only way to
// check it is to implement one. This accepts a single format and records the
// last frame it was handed.
class RecordingVideoSurface : public QAbstractVideoSurface
{
    Q_OBJECT

public:
    explicit RecordingVideoSurface(QObject *parent = 0)
        : QAbstractVideoSurface(parent), m_presented(0) {}

    QList<QVideoFrame::PixelFormat> supportedPixelFormats(
        QAbstractVideoBuffer::HandleType handleType = QAbstractVideoBuffer::NoHandle) const
    {
        QList<QVideoFrame::PixelFormat> formats;
        if (handleType == QAbstractVideoBuffer::NoHandle)
            formats << QVideoFrame::Format_RGB32;
        return formats;
    }

    bool present(const QVideoFrame &frame)
    {
        ++m_presented;
        m_lastSize = frame.size();
        return true;
    }

    int presented() const { return m_presented; }
    QSize lastSize() const { return m_lastSize; }

private:
    int m_presented;
    QSize m_lastSize;
};

// The format every check below asks for: CD-quality signed 16-bit PCM, which is
// the one combination a device is most likely to support if it supports
// anything at all.
QAudioFormat pcmFormat()
{
    QAudioFormat format;
    format.setSampleRate(44100);
    format.setChannelCount(2);
    format.setSampleSize(16);
    format.setCodec(QLatin1String("audio/pcm"));
    format.setByteOrder(QAudioFormat::LittleEndian);
    format.setSampleType(QAudioFormat::SignedInt);
    return format;
}

} // namespace

void addMultimedia4Checks(SmokeReporter &r)
{
    r.check("multimedia4/audio-format", [](QString &d) {
        const QAudioFormat format = pcmFormat();
        // Qt 4.7 renamed frequency/channels to sampleRate/channelCount and kept
        // both spellings. Reading back through the old names is what proves
        // they are the same underlying field rather than two settings.
        d = QString::fromLatin1("%1 Hz, %2 ch, %3 bit, %4")
                .arg(format.sampleRate()).arg(format.channelCount())
                .arg(format.sampleSize()).arg(format.codec());
        return format.sampleRate() == 44100 && format.channelCount() == 2
            && format.sampleSize() == 16 && format.codec() == QLatin1String("audio/pcm")
            && format.byteOrder() == QAudioFormat::LittleEndian
            && format.sampleType() == QAudioFormat::SignedInt
            && format.frequency() == format.sampleRate()
            && format.channels() == format.channelCount();
    });

    r.check("multimedia4/audio-device-info", [&r](QString &d) {
        const QList<QAudioDeviceInfo> outputs =
            QAudioDeviceInfo::availableDevices(QAudio::AudioOutput);
        if (outputs.isEmpty()) {
            r.skip(d, QLatin1String("this machine reports no audio output device"));
            return true;
        }
        const QAudioDeviceInfo device = QAudioDeviceInfo::defaultOutputDevice();
        // nearestFormat() must answer with something it also calls supported -
        // that is the contract, and it holds whatever the hardware is.
        const QAudioFormat nearest = device.nearestFormat(pcmFormat());
        d = QString::fromLatin1("%1 device(s), default \"%2\", nearest %3 Hz")
                .arg(outputs.count()).arg(device.deviceName()).arg(nearest.sampleRate());
        return !device.isNull() && !device.deviceName().isEmpty()
            && device.isFormatSupported(nearest)
            && !device.supportedCodecs().isEmpty();
    });

    r.check("multimedia4/audio-output-construct", [&r](QString &d) {
        if (QAudioDeviceInfo::availableDevices(QAudio::AudioOutput).isEmpty()) {
            r.skip(d, QLatin1String("this machine reports no audio output device"));
            return true;
        }
        const QAudioDeviceInfo device = QAudioDeviceInfo::defaultOutputDevice();
        if (device.isNull()) {
            r.skip(d, QLatin1String("no default audio output device"));
            return true;
        }
        // Constructed and interrogated, never started: a build machine has no
        // speaker, and start() would be checking the host rather than Qt.
        QAudioOutput output(device, device.nearestFormat(pcmFormat()));
        output.setBufferSize(8192);
        d = QString::fromLatin1("state %1, error %2, buffer %3")
                .arg(int(output.state())).arg(int(output.error())).arg(output.bufferSize());
        return output.state() == QAudio::StoppedState
            && output.error() == QAudio::NoError
            && output.bufferSize() == 8192
            && output.elapsedUSecs() == 0;
    });

    r.check("multimedia4/audio-input-construct", [&r](QString &d) {
        const QList<QAudioDeviceInfo> inputs =
            QAudioDeviceInfo::availableDevices(QAudio::AudioInput);
        if (inputs.isEmpty()) {
            r.skip(d, QLatin1String("this machine reports no audio input device"));
            return true;
        }
        const QAudioDeviceInfo device = QAudioDeviceInfo::defaultInputDevice();
        QAudioInput input(device, device.nearestFormat(pcmFormat()));
        d = QString::fromLatin1("%1 input(s), state %2")
                .arg(inputs.count()).arg(int(input.state()));
        return input.state() == QAudio::StoppedState
            && input.error() == QAudio::NoError
            && input.format().sampleRate() > 0;
    });

    r.check("multimedia4/audio-engine-plugin-api", [](QString &d) {
        // The interfaces Qt 4 loads an audio backend through; nothing to construct,
        // so their declarations are checked.
        d = QLatin1String("QAudioEnginePlugin is a QObject, factory interface declared");
        return sizeof(QAudioEngineFactoryInterface) > 0
            && sizeof(QAudioEnginePlugin) >= sizeof(QObject);
    });

    r.check("multimedia4/video-frame", [](QString &d) {
        QImage image(8, 4, QImage::Format_RGB32);
        image.fill(0xff204080);
        QVideoFrame frame(image);
        const bool mapped = frame.map(QAbstractVideoBuffer::ReadOnly);
        const int bytesPerLine = mapped ? frame.bytesPerLine() : -1;
        const bool haveBits = mapped && frame.bits() != 0;
        if (mapped)
            frame.unmap();
        d = QString::fromLatin1("%1x%2, format %3, %4 bytes/line")
                .arg(frame.width()).arg(frame.height())
                .arg(int(frame.pixelFormat())).arg(bytesPerLine);
        return frame.isValid() && frame.size() == QSize(8, 4)
            && frame.pixelFormat() == QVideoFrame::Format_RGB32
            && mapped && haveBits && bytesPerLine >= 8 * 4
            && !frame.isMapped();
    });

    r.check("multimedia4/video-surface-format", [](QString &d) {
        QVideoSurfaceFormat format(QSize(320, 240), QVideoFrame::Format_RGB32);
        format.setFrameRate(25.0);
        format.setScanLineDirection(QVideoSurfaceFormat::TopToBottom);
        d = QString::fromLatin1("%1x%2 @ %3 fps")
                .arg(format.frameWidth()).arg(format.frameHeight()).arg(format.frameRate());
        return format.isValid() && format.frameSize() == QSize(320, 240)
            && format.pixelFormat() == QVideoFrame::Format_RGB32
            && format.scanLineDirection() == QVideoSurfaceFormat::TopToBottom
            && qFuzzyCompare(format.frameRate(), 25.0)
            && format.handleType() == QAbstractVideoBuffer::NoHandle;
    });

    r.check("multimedia4/video-surface-present", [](QString &d) {
        RecordingVideoSurface surface;
        const QVideoSurfaceFormat format(QSize(8, 4), QVideoFrame::Format_RGB32);
        const bool supported = surface.isFormatSupported(format);
        const bool started = surface.start(format);

        QImage image(8, 4, QImage::Format_RGB32);
        image.fill(0xff000000);
        const bool presented = surface.present(QVideoFrame(image));
        const bool activeWhileStarted = surface.isActive();
        // Read the format before stopping: Qt 4's stop() clears it back to an
        // invalid QVideoSurfaceFormat, so asking afterwards answers about the
        // stopped surface rather than about the one that ran.
        const bool formatKept =
            surface.surfaceFormat().pixelFormat() == QVideoFrame::Format_RGB32;
        surface.stop();

        d = QString::fromLatin1("supported=%1 started=%2 presented=%3 last=%4x%5")
                .arg(int(supported)).arg(int(started)).arg(surface.presented())
                .arg(surface.lastSize().width()).arg(surface.lastSize().height());
        return supported && started && presented && activeWhileStarted && formatKept
            && surface.presented() == 1 && surface.lastSize() == QSize(8, 4)
            && !surface.isActive();
    });
}

// ---------------------------------------------------------------------------
// The window: audio devices, the format one agrees to, and a video frame
// through a surface (Qt 4's QtMultimedia has no player or camera).
// ---------------------------------------------------------------------------

static QWidget *makeQt4DevicesTab()
{
    QWidget *w = new QWidget;
    QVBoxLayout *layout = new QVBoxLayout(w);
    QTextEdit *text = new QTextEdit;
    text->setReadOnly(true);

    QStringList lines;
    lines << QLatin1String("Audio outputs:");
    const QList<QAudioDeviceInfo> outputs =
        QAudioDeviceInfo::availableDevices(QAudio::AudioOutput);
    for (int i = 0; i < outputs.count(); ++i)
        lines << QLatin1String("  ") + outputs.at(i).deviceName();
    if (outputs.isEmpty())
        lines << QLatin1String("  (none)");

    lines << QString() << QLatin1String("Audio inputs:");
    const QList<QAudioDeviceInfo> inputs =
        QAudioDeviceInfo::availableDevices(QAudio::AudioInput);
    for (int i = 0; i < inputs.count(); ++i)
        lines << QLatin1String("  ") + inputs.at(i).deviceName();
    if (inputs.isEmpty())
        lines << QLatin1String("  (none)");

    // No camera list: Qt 4 has no camera API at all, and saying so beats an
    // empty heading that looks like a machine with no camera.
    lines << QString()
          << QLatin1String("Cameras: Qt 4's QtMultimedia has no camera API.");

    text->setPlainText(lines.join(QLatin1String("\n")));
    layout->addWidget(text);
    return w;
}

static QWidget *makeQt4FormatTab()
{
    QWidget *w = new QWidget;
    QVBoxLayout *layout = new QVBoxLayout(w);
    QTextEdit *text = new QTextEdit;
    text->setReadOnly(true);

    const QAudioFormat asked = pcmFormat();
    QStringList lines;
    lines << QString::fromLatin1("Asked for: %1 Hz, %2 channels, %3 bit, %4")
                 .arg(asked.sampleRate()).arg(asked.channelCount())
                 .arg(asked.sampleSize()).arg(asked.codec());

    const QAudioDeviceInfo device = QAudioDeviceInfo::defaultOutputDevice();
    if (device.isNull()) {
        lines << QString() << QLatin1String("No default output device on this machine.");
    } else {
        const QAudioFormat nearest = device.nearestFormat(asked);
        lines << QString()
              << QLatin1String("Default output: ") + device.deviceName()
              << QString::fromLatin1("Nearest format: %1 Hz, %2 channels, %3 bit, %4")
                     .arg(nearest.sampleRate()).arg(nearest.channelCount())
                     .arg(nearest.sampleSize()).arg(nearest.codec())
              << QString::fromLatin1("Device calls it supported: %1")
                     .arg(device.isFormatSupported(nearest) ? QLatin1String("yes")
                                                            : QLatin1String("no"))
              << QString() << QLatin1String("Supported codecs:");
        const QStringList codecs = device.supportedCodecs();
        for (int i = 0; i < codecs.count(); ++i)
            lines << QLatin1String("  ") + codecs.at(i);
    }

    text->setPlainText(lines.join(QLatin1String("\n")));
    layout->addWidget(text);
    return w;
}

static QWidget *makeQt4VideoTab()
{
    QWidget *w = new QWidget;
    QVBoxLayout *layout = new QVBoxLayout(w);
    QLabel *result = new QLabel;
    result->setWordWrap(true);

    // Done once, when the tab is built: a surface is handed one frame and the
    // tab reports what it saw. There is nothing to press - a button would need
    // a slot and a second Q_OBJECT for a result that never changes.
    RecordingVideoSurface *surface = new RecordingVideoSurface(w);

    QImage image(64, 48, QImage::Format_RGB32);
    image.fill(0xff2060a0);
    const QVideoSurfaceFormat format(image.size(), QVideoFrame::Format_RGB32);
    const bool started = surface->start(format);
    const bool presented = started && surface->present(QVideoFrame(image));
    result->setText(QString::fromLatin1(
                        "surface started: %1\npresented: %2\nlast frame: %3x%4\n"
                        "pixel format: %5")
                        .arg(started ? QLatin1String("yes") : QLatin1String("no"))
                        .arg(presented ? QLatin1String("yes") : QLatin1String("no"))
                        .arg(surface->lastSize().width()).arg(surface->lastSize().height())
                        .arg(int(surface->surfaceFormat().pixelFormat())));
    surface->stop();

    layout->addWidget(result);
    layout->addStretch();
    return w;
}

QWidget *buildUiQt4()
{
    QTabWidget *tabs = new QTabWidget;
    tabs->addTab(makeQt4DevicesTab(), QLatin1String("Devices"));
    tabs->addTab(makeQt4FormatTab(), QLatin1String("Audio format"));
    tabs->addTab(makeQt4VideoTab(), QLatin1String("Video frame"));
    return tabs;
}

void checkMultimedia4Pages(SmokeReporter &r)
{
    QTabWidget *tabs = static_cast<QTabWidget *>(buildUiQt4());
    tabs->resize(760, 500);
    tabs->show();
    QImage sheet(380 * tabs->count(), 270, QImage::Format_RGB32);
    sheet.fill(0xffffffff);
    for (int index = 0; index < tabs->count(); ++index) {
        r.check(QStringLiteral("multimedia4/page-render-%1").arg(tabs->tabText(index)),
                [tabs, index, &sheet](QString &) {
            tabs->setCurrentIndex(index);
            QApplication::processEvents();
            QImage page(tabs->size(), QImage::Format_RGB32);
            page.fill(0xffff00ff);
            QPainter painter(&page);
            tabs->render(&painter);
            painter.end();
            int varied = 0;
            const QRgb corner = page.pixel(0, 0);
            for (int y = 0; y < page.height(); y += 4)
                for (int x = 0; x < page.width(); x += 4)
                    if (page.pixel(x, y) != corner) ++varied;
            QPainter contact(&sheet);
            contact.drawText(index * 380 + 8, 18, tabs->tabText(index));
            contact.drawImage(QRect(index * 380, 25, 380, 245), page);
            return varied > 20;
        });
    }
    r.check("multimedia4/page-contact-sheet", [&sheet](QString &d) {
        d = QDir(QCoreApplication::applicationDirPath()).filePath("multimedia-lab-pages.png");
        return sheet.save(d, "PNG");
    });
    delete tabs;
}

#include "lab_qt4.moc"   // RecordingVideoSurface's Q_OBJECT lives here
