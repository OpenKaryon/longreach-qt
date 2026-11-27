// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
// Production method bodies, real Qt6 Core queue; JNI/audio/speech base substitutes.
#include <QtCore/QCoreApplication>
#include <QtCore/QEvent>
#include <QtCore/QMap>
#include <QtCore/QMutex>
#include <QtCore/QPointer>
#include <QtCore/QThread>
#include <QtCore/QVariant>
#include <functional>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <thread>
#include <type_traits>
#include <cstring>

using jlong = qlonglong;
using jint = int;
using jbyte = signed char;
using jobject = void *;
using jclass = void *;
using jstring = void *;
using jbyteArray = QByteArray *;
struct JNIEnv {
    int GetArrayLength(jbyteArray a) { return a->size(); }
    void GetByteArrayRegion(jbyteArray a, int first, int size, jbyte *out) {
        std::memcpy(out, a->constData() + first, size);
    }
};
#define Q_DECLARE_JNI_CLASS(...)
#define Q_DECLARE_JNI_NATIVE_METHOD(...)
namespace QtJniTypes { struct QtTextToSpeech {}; }
namespace QNativeInterface { struct QAndroidApplication { static void *context() { return nullptr; } }; }
struct QAudioFormat {
    enum SampleFormat { Unknown, UInt8, Int16, Int32, Float };
    int rate = 0, channels = 0;
    SampleFormat format = Unknown;
    void setSampleRate(int n) { rate = n; }
    void setChannelCount(int n) { channels = n; }
    void setSampleFormat(SampleFormat f) { format = f; }
    bool isValid() const { return rate > 0 && channels > 0 && format != Unknown; }
};
static void notifyReady(JNIEnv *, jobject, jlong, jlong);
static void notifySpeaking(JNIEnv *, jobject, jlong, jlong);
static void notifyError(JNIEnv *, jobject, jlong, jlong, jlong);
static bool inlineInit = true;
static int result = 0, stops = 0, shutdowns = 0;
static jlong lastToken = -1;
static QString lastText;
struct QJniObject {
    jlong id = 0;
    QString text;
    static QJniObject fromString(const QString &s) { QJniObject o; o.text = s; return o; }
    template<class T> T object() const { return reinterpret_cast<T>(const_cast<QJniObject *>(this)); }
    template<class T> static QJniObject construct(void *, jlong id, jstring) {
        QJniObject o; o.id = id;
        if (inlineInit) notifyReady(nullptr, nullptr, id, 0);
        return o;
    }
    void invoke(const char *name) const {
        if (QString::fromLatin1(name) == "stop") {
            ++stops;
            if (lastToken > 0) notifyError(nullptr, nullptr, id, lastToken, 4);
        } else if (QString::fromLatin1(name) == "shutdown") {
            ++shutdowns;
            notifyReady(nullptr, nullptr, id, lastToken);
        }
    }
    void invoke(const char *name, jstring value, jlong token) const {
        lastToken = token; lastText = static_cast<QJniObject *>(value)->text;
        if (result) notifyError(nullptr, nullptr, id, token, 3);
        else if (QString::fromLatin1(name) == "say") notifySpeaking(nullptr, nullptr, id, token);
    }
    template<class T, class... Args> T callMethod(const char *name, Args... args) const {
        invoke(name, args...);
        if constexpr (!std::is_void_v<T>) return result;
    }
};
struct QTextToSpeech {
    enum State { Ready, Speaking, Paused, Error, Synthesizing };
    enum class ErrorReason { NoError, Initialization, Configuration, Input, Playback };
    enum class BoundaryHint { Default };
};
using QTextToSpeechEngine = QObject;
class QTextToSpeechEngineAndroid : public QTextToSpeechEngine {
public:
    QTextToSpeechEngineAndroid(const QVariantMap &, QObject *);
    ~QTextToSpeechEngineAndroid();
    bool acceptRequestGeneration(jlong, bool);
    jlong nextRequestGeneration();
    void say(const QString &); void synthesize(const QString &);
    void stop(QTextToSpeech::BoundaryHint); void pause(QTextToSpeech::BoundaryHint); void resume();
    void setState(QTextToSpeech::State); void setError(QTextToSpeech::ErrorReason, const QString &);
    QTextToSpeech::State state() const;
    QTextToSpeech::ErrorReason errorReason() const; QString errorString() const;
    void processNotifyReady(); void processNotifySpeaking(); void processNotifyError(int);
    void processNotifyRangeStart(int, int, int);
    void processNotifyBeginSynthesis(const QAudioFormat &); void processNotifyAudioAvailable(const QByteArray &);
    void record() { threadOK &= QThread::currentThread() == thread(); }
    void stateChanged(QTextToSpeech::State s) { record(); states.append(s); }
    void errorOccurred(QTextToSpeech::ErrorReason, const QString &) { record(); ++errors; }
    void sayingWord(const QString &s, int, int) { record(); words.append(s); }
    void synthesized(const QAudioFormat &, const QByteArray &b) { record(); audio.append(b); }
    bool threadOK = true;
    int errors = 0;
    QList<QTextToSpeech::State> states;
    QStringList words;
    QByteArray audio;
    jlong m_id = 0, m_requestGeneration = 0;
    QJniObject m_speech;
    QTextToSpeech::State m_state = QTextToSpeech::Error;
    QTextToSpeech::ErrorReason m_errorReason = QTextToSpeech::ErrorReason::Initialization;
    QString m_errorString, m_text;
    QAudioFormat m_format;
};

// ENGINE_IMPLEMENTATION

static void require(bool condition, const char *s) { if (!condition) throw std::runtime_error(s); }
static void drain() { for (int i = 0; i < 4; ++i) QCoreApplication::sendPostedEvents(nullptr, QEvent::MetaCall); }
static constexpr auto boundary = QTextToSpeech::BoundaryHint::Default;
static QTextToSpeechEngineAndroid *engine() {
    result = 0; lastToken = -1; stops = 0; shutdowns = 0; inlineInit = true;
    auto *e = new QTextToSpeechEngineAndroid({}, nullptr);
    require(e->state() == QTextToSpeech::Error && e->states.isEmpty(), "initial callback ran inside constructor");
    drain(); require(e->state() == QTextToSpeech::Ready, "inline onInit was lost");
    return e;
}
static void pass(const char *s) { std::cout << "PASS " << s << std::endl; }
int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    g_qtSpeechClass = reinterpret_cast<jclass>(1);
    try {
        auto *e = engine(); const auto id = e->m_id;
        require(e->states.size() == 1 && e->threadOK, "init owner delivery");
        e->say(""); require(lastToken == -1, "empty dispatch");
        delete e; pass("inline-init-queued-after-construction");

        e = engine(); result = -1; e->say("input rejected"); const auto failed = lastToken;
        require(e->errors == 0, "error dispatched inline");
        drain(); require(e->state() == QTextToSpeech::Error && e->errors == 1, "missing error state/signal");
        require(e->errorReason() == QTextToSpeech::ErrorReason::Input && !e->errorString().isEmpty(), "input reason/text");
        notifyError(nullptr, nullptr, e->m_id, failed, 4); drain();
        require(e->errors == 1 && e->errorReason() == QTextToSpeech::ErrorReason::Input, "duplicate terminal error");
        e->stop(boundary); drain();
        require(e->state() == QTextToSpeech::Ready && e->errorReason() == QTextToSpeech::ErrorReason::NoError && e->errorString().isEmpty(), "error recovery");
        result = 0; e->say("recovered"); drain(); require(e->state() == QTextToSpeech::Speaking, "say after recovery");
        delete e; pass("input-error-once-and-recovery");

        e = engine(); e->say("pending"); const auto pending = lastToken;
        require(e->state() == QTextToSpeech::Ready, "onStart should be queued");
        e->stop(boundary); require(stops == 1, "Ready state skipped Java stop for pending request");
        notifyReady(nullptr, nullptr, e->m_id, pending); drain();
        require(e->state() == QTextToSpeech::Ready && e->errors == 0, "pending callback survived cancellation");
        delete e; pass("stop-before-queued-onStart");

        for (bool beforeReplacement : {true, false}) {
            e = engine(); e->say("old"); drain(); const auto old = lastToken;
            if (beforeReplacement) notifyReady(nullptr, nullptr, e->m_id, old);
            e->say("new"); const auto current = lastToken;
            if (!beforeReplacement) notifyReady(nullptr, nullptr, e->m_id, old);
            require(old != current, "reused request generation");
            drain(); require(e->state() == QTextToSpeech::Speaking && e->errors == 0, "old callback changed replacement state");
            notifyReady(nullptr, nullptr, e->m_id, current);
            notifySpeaking(nullptr, nullptr, e->m_id, current);
            notifyError(nullptr, nullptr, e->m_id, current, 4); drain();
            require(e->state() == QTextToSpeech::Ready && e->errors == 0, "completed request accepted duplicate callback");
            delete e;
        }
        pass("replacement-queued-and-late-terminal-events");

        e = engine(); e->say("pause text"); drain(); const auto paused = lastToken;
        e->pause(boundary); notifyReady(nullptr, nullptr, e->m_id, paused); drain();
        require(e->state() == QTextToSpeech::Paused && e->errors == 0, "pause accepted canceled event");
        e->resume(); require(lastToken != paused && lastText == "pause text", "resume dispatch");
        drain(); require(e->state() == QTextToSpeech::Speaking, "resume Speaking");
        e->stop(boundary); drain(); require(e->state() == QTextToSpeech::Ready && e->errors == 0, "active stop");
        delete e; pass("pause-resume-active-stop");

        e = engine(); e->say("worker"); drain(); const auto token = lastToken;
        std::thread worker([=] { notifyRangeStart(nullptr, nullptr, e->m_id, token, 0, 3, 0); notifyReady(nullptr, nullptr, e->m_id, token); });
        worker.join(); require(e->state() == QTextToSpeech::Speaking && e->words.isEmpty(), "worker changed owner state inline");
        drain(); require(e->threadOK && e->words == QStringList{"wor"} && e->state() == QTextToSpeech::Ready, "worker events not delivered in order on owner");
        delete e; pass("worker-events-delivered-on-owner-thread");

        e = engine(); e->synthesize("pcm"); const auto synthesized = lastToken;
        notifyBeginSynthesis(nullptr, nullptr, e->m_id, synthesized, 16000, 2, 1);
        QByteArray pcm("abc", 3); JNIEnv env;
        notifyAudioAvailable(&env, nullptr, e->m_id, synthesized, &pcm);
        notifyEndSynthesis(nullptr, nullptr, e->m_id, synthesized);
        pcm[0] = 'z'; drain();
        require(e->audio == QByteArray("abc", 3) && e->state() == QTextToSpeech::Ready && !e->m_format.isValid(), "synthesis queue/audio copy/end ordering");
        delete e; pass("synthesis-begin-copy-audio-end-order");

        e = engine(); const auto deletedId = e->m_id;
        e->say("delete queued"); QPointer<QTextToSpeechEngineAndroid> p(e);
        delete e; require(p.isNull() && !textToSpeechRegistry->objects.contains(deletedId), "receiver remained registered");
        notifyReady(nullptr, nullptr, deletedId, lastToken); drain();
        e = engine(); require(e->m_id > deletedId && e->m_id > id, "engine identifier reused");
        notifyError(nullptr, nullptr, deletedId, lastToken, 4); drain();
        require(e->errors == 0 && e->state() == QTextToSpeech::Ready, "old engine callback reached replacement");
        delete e; pass("receiver-destruction-and-unique-engine-id");
    } catch (const std::exception &e) { std::cerr << "FAIL " << e.what() << std::endl; return 1; }
    return 0;
}
