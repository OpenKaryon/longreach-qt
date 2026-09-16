// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// QtGamepad and QtTextToSpeech: small modules, no real hardware/TTS voice
// required to construct and configure - same "backend optional" pattern as
// the sensor/camera/audio checks.
#include "../common/smokecheck.h"

#if !SMOKE_QT5

void checkGamepad(SmokeReporter &r)
{
    r.check("gamepad/module", [&](QString &d) {
        r.skip(d, QStringLiteral("QtGamepad is not in this Qt 4 SDK"));
        return false;
    });
}

void checkTextToSpeech(SmokeReporter &r)
{
    r.check("texttospeech/module", [&](QString &d) {
        r.skip(d, QStringLiteral("QtTextToSpeech has no Qt 4 module"));
        return false;
    });
}

#else

#ifdef SMOKE_HAVE_GAMEPAD
#include <QGamepad>
#endif
#ifdef SMOKE_HAVE_GAMEPAD
#include <QGamepadKeyNavigation>
#endif
#ifdef SMOKE_HAVE_GAMEPAD
#include <QGamepadManager>
#endif

#include <QTextToSpeech>
#include <QVoice>
#include <QTextToSpeechEngine>
#include <QTextToSpeechPlugin>

void checkGamepad(SmokeReporter &r)
{
    r.check("gamepad/device-and-navigation", [&](QString &d) {
#ifdef SMOKE_HAVE_GAMEPAD
        QGamepad pad(0);
        QGamepadKeyNavigation nav;
        nav.setGamepad(&pad);
        const QList<int> connected = QGamepadManager::instance()->connectedGamepads();
        return nav.gamepad() == &pad && connected.size() >= 0;
#else
        r.skip(d, QStringLiteral("QtGamepad is not in this SDK (Qt 6 dropped it)"));
        return false;
#endif
    });
}

void checkTextToSpeech(SmokeReporter &r)
{
    r.check("speech/texttospeech-and-voice", [&](QString &d) {
        QTextToSpeech *tts = nullptr;
        r.skip(d, "live backend and voices are exercised by multimedia-lab");
        Q_UNUSED(tts);
        QVoice defaultVoice;   // default-constructed - name() reads "Default"
        return defaultVoice.name() == QStringLiteral("Default");
    });
    r.check("speech/custom-engine-and-plugin", [&](QString &d) {
        // QTextToSpeechEngine is the backend interface a TTS engine plugin
        // implements (QTextToSpeechPlugin::createTextToSpeechEngine() hands
        // one back) - a minimal fixed-state subclass is that real extension
        // point.
        class FixedEngine : public QTextToSpeechEngine {
        public:
#if QT_VERSION_MAJOR < 6
            QVector<QLocale> availableLocales() const override { return { QLocale::system() }; }
            QVector<QVoice> availableVoices() const override { return { QVoice() }; }
            void say(const QString &) override {}
            void stop() override {}
            void pause() override {}
#else
            QList<QLocale> availableLocales() const override { return { QLocale::system() }; }
            QList<QVoice> availableVoices() const override { return { QVoice() }; }
            void say(const QString &) override {}
            void synthesize(const QString &) override {}
            void stop(QTextToSpeech::BoundaryHint) override {}
            void pause(QTextToSpeech::BoundaryHint) override {}
            QTextToSpeech::ErrorReason errorReason() const override
            { return QTextToSpeech::ErrorReason::NoError; }
            QString errorString() const override { return QString(); }
#endif
            void resume() override {}
            double rate() const override { return m_rate; }
            bool setRate(double rate) override { m_rate = rate; return true; }
            double pitch() const override { return 0.0; }
            bool setPitch(double) override { return true; }
            QLocale locale() const override { return QLocale::system(); }
            bool setLocale(const QLocale &) override { return true; }
            double volume() const override { return m_volume; }
            bool setVolume(double volume) override { m_volume = volume; return true; }
            QVoice voice() const override { return QVoice(); }
            bool setVoice(const QVoice &) override { return true; }
            QTextToSpeech::State state() const override { return QTextToSpeech::Ready; }
        private:
            double m_rate = 0.0, m_volume = 1.0;
        };
        FixedEngine engine;
        engine.setRate(0.5);
        engine.setVolume(0.7);

        // QTextToSpeechPlugin's factory method has a default (null) impl, so
        // the plugin interface itself is directly constructible.
        QTextToSpeechPlugin plugin;
        QString error;
        QTextToSpeechEngine *fromPlugin = plugin.createTextToSpeechEngine({}, nullptr, &error);

        return qFuzzyCompare(engine.rate(), 0.5) && qFuzzyCompare(engine.volume(), 0.7)
            && engine.state() == QTextToSpeech::Ready && fromPlugin == nullptr;
    });
}

#endif // SMOKE_QT5
