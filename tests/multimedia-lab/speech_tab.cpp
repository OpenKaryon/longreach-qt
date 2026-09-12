// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

#include "speech_tab.h"

#include "../common/smokecheck.h"

#include <QComboBox>
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
    const auto availableVoices = speech->availableVoices();
    for (const QVoice &voice : availableVoices) {
#if QT_VERSION_MAJOR < 6
        const QString label = QStringLiteral("%1 — %2, %3")
                .arg(voice.name(), QVoice::genderName(voice.gender()),
                     QVoice::ageName(voice.age()));
#else
        const QString label = QStringLiteral("%1 — %2")
                .arg(voice.name(), voice.locale().nativeLanguageName());
#endif
        voices->addItem(label);
    }
    if (availableVoices.isEmpty())
        voices->addItem(QStringLiteral("No voices reported"));

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

    speak->setEnabled(!availableVoices.isEmpty() && !backendFailed(*speech));
    stop->setEnabled(speak->isEnabled());

    QObject::connect(voices, QOverload<int>::of(&QComboBox::currentIndexChanged),
                     page, [speech, availableVoices](int index) {
        if (index >= 0 && index < availableVoices.size())
            speech->setVoice(availableVoices.at(index));
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
                     [status](QTextToSpeech::State state) { status->setText(stateName(state)); });

    return page;
}

void addSpeechChecks(SmokeReporter &r)
{
    r.check("speech/platform-backend-and-voices", [&r](QString &detail) {
        const QStringList engines = QTextToSpeech::availableEngines();
        QTextToSpeech speech;
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
