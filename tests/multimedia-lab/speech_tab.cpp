// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

#include "speech_tab.h"

#include "../common/smokecheck.h"

#include <QComboBox>
#include <QEventLoop>
#include <QSignalBlocker>
#include <QTimer>
#include <QVariant>
#include <QFormLayout>
#include <QHBoxLayout>
#include <QLabel>
#include <QPushButton>
#include <QSlider>
#include <QStringList>
#include <QTextEdit>
#include <QTextToSpeech>
#include <QVBoxLayout>
#include <QVoice>

#if QT_VERSION_MAJOR < 6
Q_DECLARE_METATYPE(QVoice)
#endif

namespace {

QString stateName(QTextToSpeech::State state)
{
    switch (state) {
    case QTextToSpeech::Ready: return QStringLiteral("Ready");
    case QTextToSpeech::Speaking: return QStringLiteral("Speaking");
    case QTextToSpeech::Paused: return QStringLiteral("Paused");
#if QT_VERSION_MAJOR < 6
    case QTextToSpeech::BackendError: return QStringLiteral("Backend error");
#else
    case QTextToSpeech::Error: return QStringLiteral("Backend error");
    case QTextToSpeech::Synthesizing: return QStringLiteral("Synthesizing");
#endif
    }
    return QStringLiteral("Unknown");
}

bool backendFailed(const QTextToSpeech &speech)
{
#if QT_VERSION_MAJOR < 6
    return speech.state() == QTextToSpeech::BackendError;
#else
    return speech.state() == QTextToSpeech::Error;
#endif
}

} // namespace

QWidget *makeSpeechTab()
{
    QWidget *page = new QWidget;
    QVBoxLayout *layout = new QVBoxLayout(page);
    QTextToSpeech *speech = new QTextToSpeech(page);

    QLabel *backend = new QLabel;
    backend->setWordWrap(true);
    const QStringList engines = QTextToSpeech::availableEngines();
    backend->setText(engines.isEmpty()
        ? QStringLiteral("No text-to-speech backend is available in this static SDK.")
        : QStringLiteral("Engines: %1").arg(engines.join(QStringLiteral(", "))));
    layout->addWidget(backend);

    QComboBox *voices = new QComboBox;
    QTextEdit *text = new QTextEdit;
    text->setPlainText(QStringLiteral(
        "Qt can read this text using the operating system's installed voice."));
    text->setMinimumHeight(120);

    QSlider *rate = new QSlider(Qt::Horizontal);
    QSlider *pitch = new QSlider(Qt::Horizontal);
    QSlider *volume = new QSlider(Qt::Horizontal);
    rate->setRange(-100, 100);
    pitch->setRange(-100, 100);
    volume->setRange(0, 100);
    rate->setValue(qRound(speech->rate() * 100.0));
    pitch->setValue(qRound(speech->pitch() * 100.0));
    volume->setValue(qRound(speech->volume() * 100.0));

    QFormLayout *form = new QFormLayout;
    form->addRow(QStringLiteral("Voice"), voices);
    form->addRow(QStringLiteral("Rate"), rate);
    form->addRow(QStringLiteral("Pitch"), pitch);
    form->addRow(QStringLiteral("Volume"), volume);
    layout->addLayout(form);
    layout->addWidget(text, 1);

    QPushButton *speak = new QPushButton(QStringLiteral("Speak"));
    QPushButton *stop = new QPushButton(QStringLiteral("Stop"));
    QLabel *status = new QLabel(stateName(speech->state()));
    QHBoxLayout *buttons = new QHBoxLayout;
    buttons->addWidget(speak);
    buttons->addWidget(stop);
    buttons->addWidget(status, 1);
    layout->addLayout(buttons);

    const auto refreshVoices = [speech, voices, speak, stop] {
        const QSignalBlocker blocker(voices);
        voices->clear();
        const auto available = speech->availableVoices();
        const QString current = speech->voice().name();
        for (const QVoice &voice : available) {
#if QT_VERSION_MAJOR < 6
            const QString label = QStringLiteral("%1 — %2, %3")
                    .arg(voice.name(), QVoice::genderName(voice.gender()), QVoice::ageName(voice.age()));
#else
            const QString label = QStringLiteral("%1 — %2")
                    .arg(voice.name(), voice.locale().nativeLanguageName());
#endif
            voices->addItem(label, QVariant::fromValue(voice));
            if (voice.name() == current)
                voices->setCurrentIndex(voices->count() - 1);
        }
        if (available.isEmpty())
            voices->addItem(QStringLiteral("No voices reported"));
        speak->setEnabled(!available.isEmpty() && !backendFailed(*speech));
        stop->setEnabled(speak->isEnabled());
    };
    refreshVoices();
    QObject::connect(voices, QOverload<int>::of(&QComboBox::currentIndexChanged),
                     page, [speech, voices](int index) {
        const QVariant voice = voices->itemData(index);
        if (voice.canConvert<QVoice>())
            speech->setVoice(voice.value<QVoice>());
    });
    QObject::connect(rate, &QSlider::valueChanged, page,
                     [speech](int value) { speech->setRate(value / 100.0); });
    QObject::connect(pitch, &QSlider::valueChanged, page,
                     [speech](int value) { speech->setPitch(value / 100.0); });
    QObject::connect(volume, &QSlider::valueChanged, page,
                     [speech](int value) { speech->setVolume(value / 100.0); });
    QObject::connect(speak, &QPushButton::clicked, page,
                     [speech, text] { speech->say(text->toPlainText()); });
    QObject::connect(stop, &QPushButton::clicked, page,
                     [speech] { speech->stop(); });
    QObject::connect(speech, &QTextToSpeech::stateChanged, page,
                     [status, speech, refreshVoices](QTextToSpeech::State state) {
        status->setText(stateName(state));
        if (state == QTextToSpeech::Ready || backendFailed(*speech))
            refreshVoices();
    });

    return page;
}

void addSpeechChecks(SmokeReporter &r)
{
    r.check("speech/platform-backend-and-voices", [&r](QString &detail) {
        const QStringList engines = QTextToSpeech::availableEngines();
        QTextToSpeech speech;
        if (!engines.isEmpty() && backendFailed(speech)) {
            // Android binds its speech service asynchronously. Give it a
            // bounded opportunity to report readiness before inspecting voices.
            QEventLoop loop;
            QObject::connect(&speech, &QTextToSpeech::stateChanged, &loop, &QEventLoop::quit);
            QTimer::singleShot(3000, &loop, &QEventLoop::quit);
            loop.exec();
        }
        const auto voices = speech.availableVoices();
        detail = QStringLiteral("engines=%1 voices=%2 state=%3")
                .arg(engines.join(QStringLiteral(",")))
                .arg(voices.size()).arg(stateName(speech.state()));
        if (engines.isEmpty() || backendFailed(speech)) {
            r.skip(detail, QStringLiteral("no usable platform speech backend"));
            return false;
        }
        return !voices.isEmpty();
    });
}

#if defined(Q_OS_ANDROID) && QT_VERSION_MAJOR == 5
#include <QElapsedTimer>
#include <QThread>
#include <QPointer>
#include <atomic>
#include <memory>

namespace {

// Keep these real-service diagnostics separate from the default smoke suite.
// Muted synthesis observes engine callbacks, never audible output. Android's
// Qt5 resume restarts the saved utterance; sample-position resume is not claimed.
class AndroidSpeechAttempt
{
public:
    explicit AndroidSpeechAttempt(SmokeReporter &reporter)
        : speech(QStringLiteral("android")), reporter(reporter)
    {
        connection = QObject::connect(&speech, &QTextToSpeech::stateChanged,
            &speech, [this](QTextToSpeech::State state) {
                if (QThread::currentThread() != speech.thread()) {
                    wrongThread.store(true);
                    return;
                }
                states << state;
                this->reporter.observe(phase, QStringLiteral("state=%1").arg(stateName(state)));
            }, Qt::DirectConnection);
        speech.setVolume(0.0);
    }

    ~AndroidSpeechAttempt() { QObject::disconnect(connection); }

    template <typename Predicate>
    bool wait(Predicate predicate, int milliseconds)
    {
        QElapsedTimer timer;
        timer.start();
        while (!predicate() && !wrongThread.load() && timer.elapsed() < milliseconds) {
            QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
            QThread::msleep(5);
        }
        return !wrongThread.load() && predicate();
    }

    bool ready()
    {
        return wait([this] { return speech.state() == QTextToSpeech::Ready
                                  && !speech.availableVoices().isEmpty(); }, 10000);
    }

    void begin(const QString &name)
    {
        phase = name;
        states.clear();
        reporter.observe(phase, QStringLiteral("initial=%1").arg(stateName(speech.state())));
    }

    bool complete(const QString &text)
    {
        states.clear();
        speech.say(text);
        return wait([this] {
            return backendFailed(speech) || (speech.state() == QTextToSpeech::Ready
                && states.indexOf(QTextToSpeech::Speaking) >= 0
                && states.lastIndexOf(QTextToSpeech::Ready) > states.indexOf(QTextToSpeech::Speaking));
        }, 15000) && !backendFailed(speech);
    }

    bool startLong()
    {
        states.clear();
        speech.say(QStringLiteral("Longreach speech lifecycle observation. ").repeated(12));
        return wait([this] { return speech.state() == QTextToSpeech::Speaking
                                  || backendFailed(speech); }, 10000)
            && speech.state() == QTextToSpeech::Speaking;
    }

    bool stable(QTextToSpeech::State expected, int milliseconds)
    {
        QElapsedTimer timer;
        timer.start();
        bool changed = speech.state() != expected;
        while (!changed && !wrongThread.load() && timer.elapsed() < milliseconds) {
            QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
            changed = speech.state() != expected;
            QThread::msleep(5);
        }
        reporter.observe(phase, QStringLiteral("observation_ms=%1 final=%2 callback_thread_ok=%3")
            .arg(timer.elapsed()).arg(stateName(speech.state())).arg(!wrongThread.load()));
        return !changed && !wrongThread.load();
    }

    QTextToSpeech speech;
    SmokeReporter &reporter;
    QString phase = QStringLiteral("speech/initialize");
    QList<QTextToSpeech::State> states;
    std::atomic<bool> wrongThread{false};
    QMetaObject::Connection connection;
};

} // namespace

int runAndroidSpeechChecks()
{
    SmokeReporter r(QStringLiteral("tts-behavior"));
    r.setTrace(true);
    r.observe(QStringLiteral("speech/scope"), QStringLiteral(
        "real Android engine; muted synthesis; bounded state observations; no audible-output claim"));
    AndroidSpeechAttempt attempt(r);
    const auto check = [&r, &attempt](const char *name, const std::function<bool(QString &)> &fn) {
        attempt.begin(QString::fromLatin1(name));
        r.check(QString::fromLatin1(name), fn);
        return r.failed() == 0;
    };
    if (!check("speech/android-ready-and-voices", [&](QString &d) {
        const bool ok = QTextToSpeech::availableEngines().contains(QStringLiteral("android")) && attempt.ready();
        d = QStringLiteral("engines=%1 voices=%2 state=%3 callback_thread_ok=%4")
            .arg(QTextToSpeech::availableEngines().join(QStringLiteral(",")))
            .arg(attempt.speech.availableVoices().size()).arg(stateName(attempt.speech.state()))
            .arg(!attempt.wrongThread.load());
        r.observe(attempt.phase, d);
        return ok;
    })) return r.summary();
    if (!check("speech/short-completion", [&](QString &) {
        return attempt.complete(QStringLiteral("Hello."));
    })) return r.summary();
    if (!check("speech/repeated-short-completions", [&](QString &d) {
        for (int i = 0; i < 4; ++i) {
            if (!attempt.complete(QStringLiteral("One."))) {
                d = QStringLiteral("completion iteration=%1").arg(i + 1);
                return false;
            }
        }
        r.observe(attempt.phase, QStringLiteral("completed_requests=4"));
        return true;
    })) return r.summary();
    if (!check("speech/stop-active-request", [&](QString &) {
        if (!attempt.startLong()) return false;
        attempt.speech.stop();
        return attempt.stable(QTextToSpeech::Ready, 250);
    })) return r.summary();
    if (!check("speech/pause-stable-before-resume", [&](QString &) {
        if (!attempt.startLong()) return false;
        attempt.speech.pause();
        return attempt.stable(QTextToSpeech::Paused, 250);
    })) return r.summary();
    if (!check("speech/resume-to-completion", [&](QString &) {
        attempt.states.clear();
        // Request the maximum rate to bound the restarted saved phrase.
        // This exercises resume, not sample-position continuation.
        attempt.speech.setRate(1.0);
        attempt.speech.resume();
        const bool completed = attempt.wait([&] {
            return backendFailed(attempt.speech) || (attempt.speech.state() == QTextToSpeech::Ready
                && attempt.states.indexOf(QTextToSpeech::Speaking) >= 0
                && attempt.states.lastIndexOf(QTextToSpeech::Ready) > attempt.states.indexOf(QTextToSpeech::Speaking));
        }, 45000);
        attempt.speech.setRate(0.0);
        return completed && !backendFailed(attempt.speech);
    })) return r.summary();
    if (!check("speech/replace-active-request", [&](QString &) {
        if (!attempt.startLong()) return false;
        return attempt.complete(QStringLiteral("Replacement request."));
    })) return r.summary();
    if (!check("speech/destroy-active-and-recreate", [&](QString &) {
        std::unique_ptr<AndroidSpeechAttempt> active(new AndroidSpeechAttempt(r));
        active->begin(QStringLiteral("speech/destroy-active-and-recreate/old"));
        if (!active->ready() || !active->startLong()) return false;
        QPointer<QTextToSpeech> pointer(&active->speech);
        active.reset();
        if (pointer) return false;
        if (!attempt.stable(QTextToSpeech::Ready, 250)) return false;
        AndroidSpeechAttempt replacement(r);
        replacement.begin(QStringLiteral("speech/destroy-active-and-recreate/new"));
        return replacement.ready() && replacement.complete(QStringLiteral("New engine."));
    })) return r.summary();
    return r.summary();
}
#endif
