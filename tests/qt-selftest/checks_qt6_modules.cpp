// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// The Qt 6 additions scattered across modules the suite already covers, and
// QtSpatialAudio, which it did not cover at all. None of these existed in
// Qt 5, so the files that grew out of the Qt 5 suite had no reason to name
// them.
//
// Everything here constructs and configures without opening a device, a port
// or a capture session: a QScreenCapture that is never started captures
// nothing, a Modbus client that is never connected opens no serial port, and
// the spatial-audio engine is built but not started.
#include "../common/smokecheck.h"

#include <QIODevice>
#include <QBuffer>
#include <QUrl>

#if QT_VERSION_MAJOR >= 6
#include <QAudioBufferInput>
#include <QAudioBufferOutput>
#include <QCameraDevice>
#include <QCameraFormat>
#include <QMediaFormat>
#include <QMediaMetaData>
#include <QMediaDevices>
#include <QScreenCapture>
#include <QVideoFrameInput>
#include <QWaveDecoder>
#include <QWindowCapture>

#include <QModbusPdu>
#include <QModbusRtuSerialClient>
#include <QModbusRtuSerialServer>

#include <QWebSocketHandshakeOptions>
#include <QNmeaSatelliteInfoSource>
#include <QOAuthUriSchemeReplyHandler>
#endif

#ifdef SMOKE_HAVE_SPATIALAUDIO
#include <QAmbientSound>
#include <QAudioEngine>
#include <QAudioListener>
#include <QAudioRoom>
#include <QSpatialSound>
#endif

void checkQt6Multimedia(SmokeReporter &r)
{
    r.check("multimedia/format-metadata-and-camera-format", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        QMediaFormat format(QMediaFormat::MPEG4);
        format.setVideoCodec(QMediaFormat::VideoCodec::H264);
        format.setAudioCodec(QMediaFormat::AudioCodec::AAC);

        QMediaMetaData metadata;
        metadata.insert(QMediaMetaData::Title, QStringLiteral("qt-smoke"));
        metadata.insert(QMediaMetaData::Duration, 1000);

        // A camera format only exists as one of a device's supported modes;
        // with no camera present the list is empty and a default-constructed
        // one is what there is to look at.
        QCameraFormat cameraFormat;
        const QList<QCameraDevice> cameras = QMediaDevices::videoInputs();
        if (!cameras.isEmpty() && !cameras.first().videoFormats().isEmpty())
            cameraFormat = cameras.first().videoFormats().first();

        QStringList misses;
        if (format.fileFormat() != QMediaFormat::MPEG4) misses << QStringLiteral("fileformat");
        if (format.videoCodec() != QMediaFormat::VideoCodec::H264) misses << QStringLiteral("videocodec");
        if (metadata.value(QMediaMetaData::Title).toString() != QStringLiteral("qt-smoke"))
            misses << QStringLiteral("metadata");
        if (metadata.keys().size() != 2) misses << QStringLiteral("metadata-keys");
        if (cameras.isEmpty() && cameraFormat.resolution() != QSize())
            misses << QStringLiteral("cameraformat");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QMediaFormat and QMediaMetaData are Qt 6 only"));
        return false;
#endif
    });

    r.check("multimedia/capture-sources-and-frame-io", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        // Constructed and left alone: start() is what would grab a screen or a
        // window, and neither is appropriate from a test battery.
        QScreenCapture screenCapture;
        QWindowCapture windowCapture;

        QAudioFormat pcm;
        pcm.setSampleRate(8000);
        pcm.setChannelCount(1);
        pcm.setSampleFormat(QAudioFormat::UInt8);
        QAudioBufferInput audioIn(pcm);
        QAudioBufferOutput audioOut(pcm);
        QVideoFrameInput videoIn;

        // QWaveDecoder reads a RIFF header off any QIODevice. open() succeeds
        // and the header is parsed afterwards, reported through formatKnown()
        // or parsingError() - so an empty stream leaves the format invalid
        // rather than making open() fail.
        QByteArray empty;
        QBuffer buffer(&empty);
        buffer.open(QIODevice::ReadOnly);
        QWaveDecoder decoder(&buffer);
        decoder.open(QIODevice::ReadOnly);
        const bool formatKnown = decoder.audioFormat().isValid();

        QStringList misses;
        if (screenCapture.isActive()) misses << QStringLiteral("screencapture");
        if (windowCapture.isActive()) misses << QStringLiteral("windowcapture");
        if (audioIn.format().sampleRate() != 8000) misses << QStringLiteral("audioinput");
        if (audioOut.format().channelCount() != 1) misses << QStringLiteral("audiooutput");
        if (videoIn.format().isValid()) misses << QStringLiteral("videoframeinput");
        if (formatKnown) misses << QStringLiteral("wavedecoder found a format in an empty stream");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("these capture classes are Qt 6 only"));
        return false;
#endif
    });

    r.check("spatialaudio/engine-listener-room-and-sounds", [&](QString &d) {
#ifdef SMOKE_HAVE_SPATIALAUDIO
        // The engine is built but never started: start() is what opens an
        // output device, and there is none in a container.
        QAudioEngine engine(44100);
        engine.setMasterVolume(0.5f);

        QAudioListener listener(&engine);
        listener.setPosition(QVector3D(0, 0, 0));

        QAudioRoom room(&engine);
        room.setDimensions(QVector3D(4, 3, 2.5f));
        room.setWallMaterial(QAudioRoom::LeftWall, QAudioRoom::BrickBare);

        QSpatialSound sound(&engine);
        sound.setPosition(QVector3D(1, 0, 0));
        sound.setVolume(0.25f);

        QAmbientSound ambient(&engine);
        ambient.setVolume(0.1f);

        QStringList misses;
        if (!qFuzzyCompare(engine.masterVolume(), 0.5f)) misses << QStringLiteral("engine");
        if (engine.sampleRate() != 44100) misses << QStringLiteral("samplerate");
        if (listener.position() != QVector3D(0, 0, 0)) misses << QStringLiteral("listener");
        if (room.wallMaterial(QAudioRoom::LeftWall) != QAudioRoom::BrickBare)
            misses << QStringLiteral("room");
        if (!qFuzzyCompare(sound.volume(), 0.25f)) misses << QStringLiteral("spatialsound");
        if (!qFuzzyCompare(ambient.volume(), 0.1f)) misses << QStringLiteral("ambientsound");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QtSpatialAudio is not in this SDK"));
        return false;
#endif
    });
}

void checkQt6ProtocolTypes(SmokeReporter &r)
{
    r.check("serialbus/modbus-pdu-types", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        // A PDU is the wire form of a Modbus message: function code plus data,
        // with request and response as the two directions and an exception
        // response as the error case. All three are value types.
        QModbusRequest request(QModbusPdu::ReadHoldingRegisters,
                               quint16(0), quint16(2));
        QModbusResponse response(QModbusPdu::ReadHoldingRegisters,
                                 quint8(4), quint16(1), quint16(2));
        QModbusExceptionResponse exception(QModbusPdu::ReadHoldingRegisters,
                                           QModbusExceptionResponse::IllegalDataAddress);
        QModbusPdu *pduBase = &request;

        QStringList misses;
        if (request.functionCode() != QModbusPdu::ReadHoldingRegisters)
            misses << QStringLiteral("request");
        if (response.dataSize() != 5) misses << QStringLiteral("response");
        if (exception.exceptionCode() != QModbusExceptionResponse::IllegalDataAddress)
            misses << QStringLiteral("exception");
        if (!exception.isException()) misses << QStringLiteral("isexception");
        if (pduBase->isValid() != request.isValid()) misses << QStringLiteral("pdubase");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("the Modbus PDU types are Qt 6 only"));
        return false;
#endif
    });

    r.check("serialbus/modbus-rtu-serial-endpoints", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        // Neither is connected, so no serial port is opened. In Qt 5 these
        // were named ...SerialMaster and ...SerialSlave.
        QModbusRtuSerialClient client;
        client.setTimeout(250);
        QModbusRtuSerialServer server;
        server.setServerAddress(7);

        bool ok = client.timeout() == 250
            && client.state() == QModbusDevice::UnconnectedState
            && server.serverAddress() == 7
            && server.state() == QModbusDevice::UnconnectedState;
        if (!ok)
            d = QStringLiteral("Modbus RTU endpoints did not keep their settings");
        return ok;
#else
        r.skip(d, QStringLiteral("QModbusRtuSerialClient/Server are the Qt 6 names"));
        return false;
#endif
    });

    r.check("net/handshake-options-nmea-satellites-oauth-uri", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        QWebSocketHandshakeOptions handshake;
        handshake.setSubprotocols({ QStringLiteral("qt-smoke") });

        // Simulation mode reads NMEA sentences from a device rather than from
        // hardware, so no GPS is required.
        QNmeaSatelliteInfoSource satellites(QNmeaSatelliteInfoSource::UpdateMode::SimulationMode);

        // No URI scheme is registered with the OS: the handler is constructed
        // and its redirect URL read back, nothing is listened for.
        QOAuthUriSchemeReplyHandler oauth(QUrl(QStringLiteral("qtsmoke://callback")));

        QStringList misses;
        if (handshake.subprotocols().value(0) != QStringLiteral("qt-smoke"))
            misses << QStringLiteral("handshakeoptions");
        if (satellites.updateMode() != QNmeaSatelliteInfoSource::UpdateMode::SimulationMode)
            misses << QStringLiteral("nmeasatellites");
        if (oauth.redirectUrl().scheme() != QStringLiteral("qtsmoke"))
            misses << QStringLiteral("oauthurischeme");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("these classes are Qt 6 only"));
        return false;
#endif
    });
}
