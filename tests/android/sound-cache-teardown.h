// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef LONGREACH_SOUND_CACHE_TEARDOWN_H
#define LONGREACH_SOUND_CACHE_TEARDOWN_H

// Included only by the Qt5/Qt6 Android extended/full selftest. The normal smoke
// profiles do not call this diagnostic or acquire an audio device for it.
#include <cstdio>
#include <QByteArray>
#include <QCoreApplication>
#include <QDataStream>
#include <QDir>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QFile>
#include <QSoundEffect>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTextStream>
#include <QThread>
#include <QUrl>

namespace SmokeSoundCacheTeardown {

inline int fail(QTextStream &out, const char *reason)
{
    out << "FAIL: sound-cache-teardown - " << reason << '\n';
    out.flush();
    return 1;
}

template <typename Predicate>
bool waitFor(Predicate done, int milliseconds)
{
    QElapsedTimer timer;
    timer.start();
    while (!done() && timer.elapsed() < milliseconds) {
        // An Android dispatcher can itself block during suspension. The host
        // runner's outer deadline remains necessary even with this local timer.
        QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
        QThread::msleep(5);
    }
    return done();
}

inline int run()
{
    QTextStream out(stdout);
    out << "SOUND_CACHE: protocol=1\n";
    out.flush();

    const QString cache = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    if (cache.isEmpty() || !QDir(cache).exists())
        return fail(out, "application cache directory is unavailable");
    QTemporaryDir temporary(QDir(cache).filePath(QStringLiteral("longreach-sound-cache-XXXXXX")));
    if (!temporary.isValid())
        return fail(out, "cannot create a temporary directory in the application cache");

    // One second of valid silent PCM, not a missing-file/error-path request.
    QByteArray pcm;
    QDataStream wave(&pcm, QIODevice::WriteOnly);
    wave.setByteOrder(QDataStream::LittleEndian);
    wave.writeRawData("RIFF", 4);
    wave << quint32(36 + 16000);
    wave.writeRawData("WAVEfmt ", 8);
    wave << quint32(16) << quint16(1) << quint16(1) << quint32(8000)
         << quint32(16000) << quint16(2) << quint16(16);
    wave.writeRawData("data", 4);
    wave << quint32(16000);
    for (int i = 0; i < 8000; ++i)
        wave << qint16(0);
    if (wave.status() != QDataStream::Ok || pcm.size() != 16044)
        return fail(out, "cannot construct a complete PCM WAV");

    const QString path = QDir(temporary.path()).filePath(QStringLiteral("sample.wav"));
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly) || file.write(pcm) != pcm.size() || !file.flush())
        return fail(out, "cannot write the complete local PCM WAV");
    file.close();
    out << "SOUND_CACHE: wav=pcm-s16le-8000-mono\n";
    out.flush();

    {
        QSoundEffect effect;
        effect.setVolume(0.0);
        effect.setLoopCount(1);
        effect.setSource(QUrl::fromLocalFile(path));
        if (!waitFor([&] { return effect.status() == QSoundEffect::Ready
                                 || effect.status() == QSoundEffect::Error; }, 5000)
                || effect.status() != QSoundEffect::Ready)
            return fail(out, "local sample did not become Ready");
        out << "SOUND_CACHE: ready=1\n";
        out.flush();

        effect.play();
        if (!waitFor([&] { return effect.isPlaying()
                                 || effect.status() == QSoundEffect::Error; }, 5000)
                || !effect.isPlaying() || effect.status() == QSoundEffect::Error)
            return fail(out, "local sample did not start playing");
        QElapsedTimer playing;
        playing.start();
        while (playing.elapsed() < 100) {
            QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
            QThread::msleep(5);
        }
        if (!effect.isPlaying() || effect.status() != QSoundEffect::Ready)
            return fail(out, "sample stopped or failed before the playback observation");
        out << "SOUND_CACHE: playing=1\n";
        out.flush();
        effect.stop();
    }
    out << "SOUND_CACHE: destroyed=1\n";
    out.flush();
    // Global cache/application destruction and the Android exit path still
    // follow this return. Only the host's separate exit proof can accept them.
    out << "SOUND_CACHE: return=0\n";
    out.flush();
    return 0;
}

} // namespace SmokeSoundCacheTeardown
#endif
