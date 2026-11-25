// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
// Explicit Qt5 Android diagnostic. Default smoke totals remain separate.
#pragma once
#include <QtAndroidExtras/QAndroidActivityResultReceiver>
#include <QtAndroidExtras/QAndroidBinder>
#include <QtAndroidExtras/QAndroidIntent>
#include <QtAndroidExtras/QAndroidJniEnvironment>
#include <QtAndroidExtras/QAndroidParcel>
#include <QtAndroidExtras/QAndroidService>
#include <QtAndroidExtras/QAndroidServiceConnection>
#include <QtAndroidExtras/QtAndroid>
#include <QCoreApplication>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QFile>
#include <QSharedPointer>
#include <QSaveFile>
#include <QThread>
#include <QUuid>
#include <QVariantMap>
#include <atomic>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <functional>
#include <mutex>
#include <signal.h>
#include <unistd.h>

namespace SmokeAndroidExtras {
constexpr int EchoCode = 0x5145;
constexpr int CallbackCode = 0x5146;
constexpr int RequestCode = 0x5147;
constexpr int Iterations = 8;

inline bool clearException()
{
    QAndroidJniEnvironment env;
    if (!env->ExceptionCheck()) return true;
    env->ExceptionDescribe();
    env->ExceptionClear();
    return false;
}

inline bool waitFor(const std::function<bool()> &predicate, int milliseconds)
{
    QElapsedTimer timer;
    timer.start();
    do {
        if (predicate()) return true;
        QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
        QThread::msleep(10);
    } while (timer.elapsed() < milliseconds);
    return predicate();
}

inline QByteArray payload(int index)
{
    return QByteArray("Qt\0Binder-", 10) + QByteArray::number(index)
            + QByteArray("-\xc3\xa9_\xe6\x97\xa5");
}

inline bool check(const char *name, bool ok)
{
    std::printf("ANDROID_EXTRAS: %s=%s\n", name, ok ? "PASS" : "FAIL");
    std::fflush(stdout);
    return ok;
}

class EchoBinder final : public QAndroidBinder {
public:
    std::mutex mutex;
    QByteArray nonce;
    std::atomic_int calls { 0 }, callbacks { 0 }, errors { 0 };
    bool onTransact(int code, const QAndroidParcel &data, const QAndroidParcel &reply,
                    CallType flags) override
    {
        if (code != EchoCode || flags != CallType::Normal) return false;
        const QByteArray bytes = data.readData();
        const QVariantMap info = data.readVariant().toMap();
        const QAndroidBinder callback = data.readBinder();
        QByteArray boundNonce;
        { std::lock_guard<std::mutex> lock(mutex); boundNonce = nonce; }
        const int index = calls.fetch_add(1);
        const bool inputOk = !boundNonce.isEmpty() && info.value("nonce").toByteArray() == boundNonce
                && info.value("index").toInt() == index && bytes == payload(index);
        QAndroidParcel callbackData, callbackReply;
        callbackData.writeData(bytes);
        const bool callbackOk = inputOk && callback.transact(CallbackCode, callbackData, &callbackReply)
                && callbackReply.readData() == bytes + QByteArray("-callback");
        if (callbackOk) ++callbacks; else ++errors;
        reply.writeData(bytes);
        reply.writeVariant(QVariantMap {{"nonce", boundNonce}, {"index", index},
            {"pid", qlonglong(getpid())}, {"callback", callbackOk}});
        return clearException() && inputOk && callbackOk;
    }
};

class ServiceApp final : public QAndroidService {
public:
    ServiceApp(int &argc, char **argv) : QAndroidService(argc, argv) {}
    EchoBinder binder;
    std::atomic_int binds { 0 };
    QAndroidBinder *onBind(const QAndroidIntent &intent) override
    {
        QAndroidIntent copy(intent.handle());
        const QByteArray nonce = copy.extraBytes(QStringLiteral("longreach.nonce"));
        if (nonce.size() != 32 || !clearException()) return nullptr;
        { std::lock_guard<std::mutex> lock(binder.mutex); binder.nonce = nonce; }
        ++binds;
        std::printf("ANDROID_EXTRAS_SERVICE: bound pid=%ld nonce=%s\n", long(getpid()), nonce.constData());
        return &binder;
    }
};

inline int runService(int &argc, char **argv)
{
    ServiceApp application(argc, argv);
    const int result = application.exec();
    const bool ok = result == 0 && application.binds == 1
            && application.binder.calls == Iterations && application.binder.callbacks == Iterations
            && application.binder.errors == 0;
    std::printf("ANDROID_EXTRAS_SERVICE: finished=%d binds=%d calls=%d callbacks=%d errors=%d\n",
        ok ? 0 : 1, application.binds.load(), application.binder.calls.load(),
        application.binder.callbacks.load(), application.binder.errors.load());
    return ok ? 0 : 1;
}

class CallbackBinder final : public QAndroidBinder {
public:
    std::atomic_int calls { 0 }, errors { 0 };
    bool onTransact(int code, const QAndroidParcel &data, const QAndroidParcel &reply,
                    CallType flags) override
    {
        const int index = calls.fetch_add(1);
        const QByteArray bytes = data.readData();
        const bool ok = code == CallbackCode && flags == CallType::Normal && bytes == payload(index);
        if (!ok) ++errors;
        reply.writeData(bytes + QByteArray("-callback"));
        return ok && clearException();
    }
};

class Connection final : public QAndroidServiceConnection {
public:
    std::mutex mutex;
    QSharedPointer<QAndroidBinder> binder;
    QString component;
    std::atomic_int connected { 0 }, disconnected { 0 };
    void onServiceConnected(const QString &name, const QAndroidBinder &service) override
    {
        std::lock_guard<std::mutex> lock(mutex);
        component = name;
        binder.reset(new QAndroidBinder(service.handle()));
        ++connected;
    }
    void onServiceDisconnected(const QString &) override { ++disconnected; }
};

class ActivityResult final : public QAndroidActivityResultReceiver {
public:
    std::mutex mutex;
    QByteArray bytes;
    int request = -1, result = 0;
    std::atomic_int calls { 0 };
    void handleActivityResult(int requestCode, int resultCode, const QAndroidJniObject &intent) override
    {
        QAndroidIntent received(intent);
        std::lock_guard<std::mutex> lock(mutex);
        request = requestCode; result = resultCode;
        bytes = received.extraBytes(QStringLiteral("longreach.reply"));
        ++calls;
    }
};

inline QByteArray contents(const QString &path)
{
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray();
}

inline bool hostBarrier(int round, const char *phase, qint64 pid, const QByteArray &nonce)
{
    const char *root = std::getenv("LONGREACH_APP_FILES");
    if (!root || !*root) return false;
    const QString stem = QString::fromLocal8Bit(root)
            + QStringLiteral("/extras-service-%1-%2").arg(round).arg(QString::fromLatin1(phase));
    if (QFile::exists(stem + ".txt") || QFile::exists(stem + "-ack.txt")) return false;
    QSaveFile request(stem + ".txt");
    const QByteArray body = QByteArray::number(pid) + ' ' + nonce + '\n';
    if (!request.open(QIODevice::WriteOnly) || request.write(body) != body.size() || !request.commit()) return false;
    return waitFor([&] { return contents(stem + "-ack.txt").trimmed() == nonce; }, 40000);
}

struct RoundResult {
    bool bound = false, echo = false, callbacks = false, exited = false;
    qint64 pid = -1;
};

inline RoundResult serviceRound(int round)
{
    RoundResult result;
    auto connection = QSharedPointer<Connection>::create();
    CallbackBinder callback;
    const auto context = QtAndroid::androidContext();
    const QByteArray nonce = QUuid::createUuid().toString(QUuid::Id128).toLatin1();
    QAndroidIntent intent(context, "org/qtproject/qt5/android/bindings/LongreachExtrasService");
    intent.putExtra(QStringLiteral("longreach.nonce"), nonce);
    const bool requested = QtAndroid::bindService(intent, *connection, QtAndroid::BindFlag::AutoCreate);
    bool jniOk = clearException();
    if (requested && jniOk && waitFor([&] { return connection->connected.load() > 0; }, 20000)) {
        QSharedPointer<QAndroidBinder> binder;
        { std::lock_guard<std::mutex> lock(connection->mutex);
          binder = connection->binder;
          result.bound = connection->connected == 1 && connection->component.endsWith("LongreachExtrasService"); }
        result.echo = result.bound;
        for (int index = 0; index < Iterations && result.echo; ++index) {
            QAndroidParcel data, reply;
            data.writeData(payload(index));
            data.writeVariant(QVariantMap {{"nonce", nonce}, {"index", index}});
            data.writeBinder(callback);
            const bool transacted = binder->transact(EchoCode, data, &reply);
            if (!transacted || !clearException()) { result.echo = false; break; }
            const QByteArray echoed = reply.readData();
            const QVariantMap info = reply.readVariant().toMap();
            const qint64 pid = info.value("pid").toLongLong();
            result.echo = transacted && clearException() && echoed == payload(index)
                    && info.value("nonce").toByteArray() == nonce && info.value("index").toInt() == index
                    && info.value("callback").toBool() && pid > 0 && pid != getpid()
                    && (result.pid == -1 || result.pid == pid);
            result.pid = pid;
            if (index == 0 && result.echo) result.echo = hostBarrier(round, "live", pid, nonce);
        }
        result.callbacks = callback.calls == Iterations && callback.errors == 0;
    }
    if (requested) {
        struct UnboundState { std::atomic_bool done { false }, ok { false }; };
        auto unbound = QSharedPointer<UnboundState>::create();
        // Serialize unbind after UI-delivered connection callbacks. Capture
        // heap-owned state so a timed-out queued action cannot touch the stack.
        QtAndroid::runOnAndroidThreadSync([context, connection, unbound] {
            context.callMethod<void>("unbindService", "(Landroid/content/ServiceConnection;)V", connection->handle().object());
            unbound->ok = clearException();
            unbound->done = true;
        }, 5000);
        jniOk = unbound->done && unbound->ok && jniOk;
    }
    if (result.pid > 0) {
        const QString files = QString::fromLocal8Bit(std::getenv("LONGREACH_APP_FILES"));
        const QString folder = files + QStringLiteral("/extras-service-%1/").arg(result.pid);
        result.exited = jniOk && waitFor([&] {
            errno = 0;
            const bool gone = ::kill(pid_t(result.pid), 0) == -1 && errno == ESRCH;
            return gone && contents(folder + "selftest-result.txt").trimmed() == "0"
                && contents(folder + "on-destroy.txt").trimmed() == QByteArray::number(result.pid);
        }, 20000);
    }
    if (result.exited) result.exited = hostBarrier(round, "exit", result.pid, nonce);
    std::printf("ANDROID_EXTRAS: service-round=%d pid=%lld nonce=%s calls=%d callbacks=%d native_result=%d exited=%d\n",
        round, static_cast<long long>(result.pid), nonce.constData(),
        result.echo ? Iterations : -1, callback.calls.load(), result.exited ? 0 : -1, result.exited ? 1 : 0);
    return result;
}

inline int runClient()
{
    const auto context = QtAndroid::androidContext();
    struct UiState { std::atomic_bool mainLooper { false }; };
    auto ui = QSharedPointer<UiState>::create();
    QtAndroid::runOnAndroidThreadSync([ui] {
        auto current = QAndroidJniObject::callStaticObjectMethod("android/os/Looper", "myLooper", "()Landroid/os/Looper;");
        auto main = QAndroidJniObject::callStaticObjectMethod("android/os/Looper", "getMainLooper", "()Landroid/os/Looper;");
        QAndroidJniEnvironment env;
        ui->mainLooper = current.isValid() && main.isValid() && env->IsSameObject(current.object(), main.object());
    }, 5000);
    if (!check("context-and-ui-thread", context.isValid() && QtAndroid::androidActivity().isValid()
               && QtAndroid::androidSdkVersion() >= 10 && ui->mainLooper && clearException())) return 1;
    QAndroidIntent values(QStringLiteral("org.longreachqt.EXTRAS"));
    const QByteArray bytes = payload(0);
    values.putExtra(QStringLiteral("bytes"), bytes);
    values.putExtra(QStringLiteral("variant"), QVariant(QString::fromUtf8("Qt-\xc3\xa9_\xe6\x97\xa5")));
    if (!check("intent-values", values.extraBytes(QStringLiteral("bytes")) == bytes
               && values.extraVariant(QStringLiteral("variant")).toString() == QString::fromUtf8("Qt-\xc3\xa9_\xe6\x97\xa5")
               && clearException())) return 1;
    ActivityResult receiver;
    QAndroidIntent activity(context, "org/longreachqt/examples/ExtrasResultActivity");
    activity.putExtra(QStringLiteral("longreach.payload"), bytes);
    QtAndroid::startActivity(activity, RequestCode, &receiver);
    bool received = clearException() && waitFor([&] { return receiver.calls.load() != 0; }, 15000);
    { std::lock_guard<std::mutex> lock(receiver.mutex);
      received = received && receiver.calls == 1 && receiver.request == RequestCode
          && receiver.result == -1 && receiver.bytes == bytes; }
    if (!check("activity-result", received)) return 1;
    const RoundResult first = serviceRound(0);
    bool ok = check("cross-process-service", first.bound && first.pid > 0 && first.pid != getpid());
    ok = check("parcel-binder-echo", first.echo) && ok;
    ok = check("reverse-binder-callbacks", first.callbacks) && ok;
    ok = check("service-unbind-exit", first.exited) && ok;
    if (!ok) return 1;
    const RoundResult second = serviceRound(1);
    ok = check("service-restart-exit", second.bound && second.echo && second.callbacks && second.exited
               && second.pid > 0 && second.pid != first.pid);
    std::printf("ANDROID_EXTRAS: summary=%s checks=8 service_processes=2 transactions=16 callbacks=16\n", ok ? "PASS" : "FAIL");
    return ok ? 0 : 1;
}
} // namespace SmokeAndroidExtras
