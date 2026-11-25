// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
// Real QtCore delivery and QPointer lifetime; Android/JNI calls are substitutes.
#include <QtCore/QCoreApplication>
#include <QtCore/QEvent>
#include <QtCore/QMap>
#include <QtCore/QMutex>
#include <QtCore/QPointer>
#include <QtCore/QString>
#include <QtCore/QVariant>
#include <functional>
#include <stdexcept>
#include <thread>
#include <vector>
#include <iostream>
#include "qandroidttsutterance_p.h"

using jlong = long long;
using jint = int;
using jboolean = unsigned char;
using jobject = void *;
using jclass = void *;
using JNIEnv = void;
#define JNI_FALSE 0
static int sdk = 10;
static int result = 0, stops = 0;
static std::vector<QString> texts;
static std::vector<jlong> tokens;
static std::function<void(jlong, jlong)> onDispatch;
namespace QtAndroidPrivate {
static void *context() { return nullptr; }
static int androidSdkVersion() { return sdk; }
}
struct QJNIObjectPrivate {
    jlong id = 0;
    QString text;
    static QJNIObjectPrivate callStaticObjectMethod(jclass, const char *, const char *, void *, jlong id) {
        QJNIObjectPrivate speech; speech.id = id; return speech;
    }
    static QJNIObjectPrivate fromString(const QString &text) {
        QJNIObjectPrivate value; value.text = text; return value;
    }
    void *object() const { return const_cast<QJNIObjectPrivate *>(this); }
    template<typename T> T callMethod(const char *name, const char * = nullptr) const {
        if (QString::fromLatin1(name) == "stop") ++stops;
    }
    template<typename T> T callMethod(const char *, const char *, void *value, jlong generation) const {
        texts.push_back(static_cast<QJNIObjectPrivate *>(value)->text);
        tokens.push_back(generation);
        if (onDispatch) onDispatch(id, generation);
        return result;
    }
};
struct QTextToSpeech { enum State { Ready, Speaking, Paused, BackendError }; };
using QTextToSpeechEngine = QObject;
class QTextToSpeechEngineAndroid : public QTextToSpeechEngine {
    Q_OBJECT
public:
    QTextToSpeechEngineAndroid(const QVariantMap &, QObject *);
    ~QTextToSpeechEngineAndroid();
    void say(const QString &);
    QTextToSpeech::State state() const;
    void setState(QTextToSpeech::State);
    void stop(); void pause(); void resume();
    qlonglong m_id;
    QAndroidTtsUtterance m_utterance;
    QJNIObjectPrivate m_speech;
    QTextToSpeech::State m_state;
    QString m_text;
public slots:
    void processNotifyReady();
    void processNotifyError();
    void processNotifyUtterance(qlonglong, bool);
signals:
    void stateChanged(QTextToSpeech::State);
};

// ENGINE_IMPLEMENTATION

static void require(bool condition, const char *message) {
    if (!condition) throw std::runtime_error(message);
}
static void drain() {
    for (int i = 0; i != 4; ++i)
        QCoreApplication::sendPostedEvents(nullptr, QEvent::MetaCall);
}
static void event(jlong id, jlong token, bool speaking, bool binder = true) {
    auto send = [=] { notifyUtterance(nullptr, nullptr, id, token, speaking); };
    if (binder) { std::thread worker(send); worker.join(); } else send();
}
static QTextToSpeechEngineAndroid *engine() {
    result = 0; onDispatch = {}; texts.clear(); tokens.clear(); stops = 0;
    auto *e = new QTextToSpeechEngineAndroid({}, nullptr);
    notifyReady(nullptr, nullptr, e->m_id); drain();
    require(e->state() == QTextToSpeech::Ready, "initial Ready");
    return e;
}
static void pass(const char *name) { std::cout << "PASS " << name << std::endl; }
int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    g_qtSpeechClass = reinterpret_cast<jclass>(1);
    try {
        sdk = 10;
        auto *e = engine();
        e->say(""); require(texts.empty(), "empty dispatch");
        e->say("A"); require(e->state() == QTextToSpeech::Speaking, "legacy successful Speaking");
        event(e->m_id, tokens.back(), false); drain();
        require(e->state() == QTextToSpeech::Ready, "legacy completion");
        delete e; pass("legacy-success-empty");

        e = engine();
        onDispatch = [](jlong id, jlong token) { event(id, token, false); };
        e->say("fast"); require(e->state() == QTextToSpeech::Speaking, "fast must dispatch Speaking first");
        drain(); require(e->state() == QTextToSpeech::Ready, "fast final Ready");
        onDispatch = {}; delete e; pass("fast-completion-queued");

        for (int api : {10, 21}) for (bool queued : {true, false}) {
            sdk = api;
            e = engine(); e->say("A"); const auto a = tokens.back();
            if (sdk >= 15) { event(e->m_id, a, true); drain(); }
            if (queued) event(e->m_id, a, false);
            e->say("B"); const auto b = tokens.back();
            require(a != b, "generation must change");
            if (sdk >= 15) { event(e->m_id, b, true); drain(); }
            if (!queued) event(e->m_id, a, false);
            drain(); require(e->state() == QTextToSpeech::Speaking, "stale completion stopped B");
            event(e->m_id, b, false); event(e->m_id, b, true); drain();
            require(e->state() == QTextToSpeech::Ready, "late Start resurrected completed utterance");
            delete e;
        }
        pass("queued-and-late-stale-completion");

        sdk = 10;
        e = engine(); result = -1; e->say("error");
        require(e->state() == QTextToSpeech::BackendError, "dispatch failure");
        event(e->m_id, tokens.back(), true); drain();
        require(e->state() == QTextToSpeech::BackendError, "failed dispatch token accepted");
        delete e; pass("dispatch-failure-invalidates-token");

        sdk = 21; e = engine(); e->say("pending"); const auto pending = tokens.back();
        require(e->state() == QTextToSpeech::Ready, "modern waits for onStart");
        e->stop(); require(stops == 1, "stop must cancel dispatched phrase before onStart");
        event(e->m_id, pending, true); drain();
        require(e->state() == QTextToSpeech::Ready, "stopped pending onStart");
        e->say("modern"); event(e->m_id, tokens.back(), true); drain();
        require(e->state() == QTextToSpeech::Speaking, "modern onStart");
        event(e->m_id, tokens.back(), false); drain();
        require(e->state() == QTextToSpeech::Ready, "modern completion");
        delete e; pass("modern-start-done-stop-before-start");

        e = engine(); e->say("initializing");
        notifyReady(nullptr, nullptr, e->m_id); drain();
        require(e->m_utterance.isActive(), "queued initialization Ready cancelled active phrase");
        notifyError(nullptr, nullptr, e->m_id); drain();
        require(e->state() == QTextToSpeech::BackendError && !e->m_utterance.isActive(), "initialization error must cancel phrase");
        delete e; pass("initialization-ready-and-error");

        for (int api : {10, 21}) {
            sdk = api; e = engine(); e->say("resume"); const auto old = tokens.back();
            e->pause(); event(e->m_id, old, false); event(e->m_id, old, true); drain();
            require(e->state() == QTextToSpeech::Paused, "pause ignored stale completion");
            e->resume(); require(tokens.back() != old && texts.back() == "resume", "resume new generation/text");
            event(e->m_id, old, false); drain();
            require(e->m_utterance.isActive(), "old completion cancelled resume");
            e->stop(); event(e->m_id, tokens.back(), true); drain();
            require(e->state() == QTextToSpeech::Ready, "stop stale start");
            delete e;
        }
        pass("pause-resume-stop-both-api-paths");

        sdk = 10; e = engine(); e->say("A"); bool replaced = false;
        QObject::connect(e, &QTextToSpeechEngineAndroid::stateChanged, e, [&](QTextToSpeech::State state) {
            if (!replaced && state == QTextToSpeech::Ready) { replaced = true; e->say("C"); }
        });
        e->say("B"); require(texts.size() == 2 && texts.back() == "C", "reentrant C overwritten by B");
        delete e; pass("reentrant-replacement");

        e = engine(); e->say("A"); bool stopped = false;
        QObject::connect(e, &QTextToSpeechEngineAndroid::stateChanged, e, [&](QTextToSpeech::State state) {
            if (!stopped && state == QTextToSpeech::Ready) { stopped = true; e->stop(); }
        });
        e->say("B"); require(texts.size() == 1 && e->state() == QTextToSpeech::Ready, "reentrant stop failed to cancel pending B");
        delete e; pass("reentrant-stop");

        e = engine(); e->say("A"); const auto deadId = e->m_id, deadToken = tokens.back();
        QPointer<QTextToSpeechEngineAndroid> guarded(e);
        QObject::connect(e, &QTextToSpeechEngineAndroid::stateChanged, e, [=](QTextToSpeech::State state) {
            if (state == QTextToSpeech::Ready) delete e;
        });
        e->say("delete"); require(!guarded && texts.size() == 1, "dispatch after reentrant deletion");
        e = engine(); require(e->m_id != deadId, "deleted engine identity reused");
        event(deadId, deadToken, false); drain();
        require(e->state() == QTextToSpeech::Ready, "callback targeted replacement engine");
        e->say("queued-delete"); event(e->m_id, tokens.back(), false); delete e; drain();
        pass("destruction-and-late-engine-callbacks");
        return 0;
    } catch (const std::exception &error) { std::cerr << error.what() << std::endl; return 1; }
}
#include "native.moc"
