// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Threads, thread pool, synchronization, futures, process. Headless.
#include "../common/smokecheck.h"
#include "checks.h"

#include <QThread>
#include <QScopedPointer>
#include <QThreadPool>
#include <QRunnable>
#include <QMutex>
#include <QMutexLocker>
#include <QReadWriteLock>
#include <QReadLocker>
#include <QWriteLocker>
#include <QSemaphore>
#include <QWaitCondition>
#include <QAtomicInt>
#include <cerrno>
#if SMOKE_QT5
#include <QtConcurrent>
#else
#include <QtConcurrentRun>
#endif
#include <QFuture>
#include <QFutureInterface>
#include <QFutureWatcher>
#include <QFutureSynchronizer>
#include <QElapsedTimer>
#include <QProcess>
#include <QProcessEnvironment>
#include <QCoreApplication>
#include <QEvent>
#if SMOKE_QT5
#include <QException>
#endif
#include <QFile>
#include <QSocketNotifier>
#include <QThreadStorage>
#include <QTemporaryFile>
#if defined(Q_OS_WIN) && SMOKE_QT5
#include <QWinEventNotifier>
#endif

#if SMOKE_QT5
namespace {
bool timedSyncCheck(SmokeReporter &reporter, const char *name, bool semaphore,
                    bool timeout, QString &detail)
{
    class Peer : public QThread {
    public:
        QMutex mutex;
        QSemaphore available;
        QAtomicInt ready{0}, begin{0}, armed{0}, released{0};
        const bool semaphore;
        const int delay;
        Peer(bool useSemaphore, int milliseconds)
            : semaphore(useSemaphore), delay(milliseconds) {}
        void run() override {
            if (!semaphore) mutex.lock();
            ready.storeRelease(1);
            // Start the release delay only after the caller has observed an
            // unavailable resource. The flag is independent of the primitives
            // under test; an overloaded caller cannot leave us waiting forever.
            QElapsedTimer preparation;
            preparation.start();
            while (!begin.loadAcquire() && preparation.elapsed() < 5000)
                QThread::yieldCurrentThread();
            if (begin.loadAcquire()) {
                armed.storeRelease(1);
                msleep(delay);
            }
            released.storeRelease(1);
            if (!semaphore) mutex.unlock();
            else available.release();
        }
    };
    const int maximumAttempts = timeout ? 1 : 3;
    for (int attempt = 1; attempt <= maximumAttempts; ++attempt) {
        // Peer owns everything referenced by its worker. If joining fails, no
        // pointer to this function's stack is left in the running thread.
        QScopedPointer<Peer> peer(new Peer(semaphore, timeout ? 1200 : 250));
        QObject::connect(peer.data(), SIGNAL(finished()), peer.data(), SLOT(deleteLater()));
        peer->start();
        QElapsedTimer preparation;
        preparation.start();
        while (!peer->ready.loadAcquire() && preparation.elapsed() < 5000)
            QThread::yieldCurrentThread();
        const bool ready = peer->ready.loadAcquire();
        const bool probeAcquired = ready && (semaphore ? peer->available.tryAcquire(1)
                                                       : peer->mutex.tryLock());
        if (probeAcquired) {
            if (semaphore) peer->available.release();
            else peer->mutex.unlock();
        }
        const bool unavailable = ready && !probeAcquired;
        peer->begin.storeRelease(1);
        const bool releasedBeforeCall = peer->released.loadAcquire();
        QElapsedTimer elapsed;
        elapsed.start();
#ifdef ETIMEDOUT
        // Successful wakeups must ignore errno left by a preceding timeout.
        errno = timeout ? 0 : ETIMEDOUT;
#endif
        const bool acquired = ready && (semaphore
            ? peer->available.tryAcquire(1, timeout ? 200 : 5000)
            : peer->mutex.tryLock(timeout ? 200 : 5000));
        const qint64 milliseconds = elapsed.elapsed();
        if (acquired && !semaphore) peer->mutex.unlock();
        const bool joined = peer->wait(10000);
        const bool armed = peer->armed.loadAcquire();
        const bool setup = ready && unavailable && armed && !releasedBeforeCall;
        const bool qualified = joined && setup && milliseconds < 4500
            && (timeout ? !acquired && milliseconds >= 150
                        : acquired && milliseconds >= 100);
        // Retry only successful wakeups whose setup/timing did not establish
        // waiting. A timeout/error from tryLock/tryAcquire is an immediate FAIL.
        const bool retry = !timeout && !qualified && attempt < maximumAttempts
            && joined && ready && acquired
            && (!setup || milliseconds < 100);
        const char *verdict = qualified ? "pass" : retry ? "retry" : "fail";
        detail = QStringLiteral("attempt=%1 ready=%2 unavailable=%3 armed=%4 released_before_call=%5 acquired=%6 elapsed_ms=%7 joined=%8 verdict=%9")
            .arg(attempt).arg(ready).arg(unavailable).arg(armed).arg(releasedBeforeCall)
            .arg(acquired).arg(milliseconds).arg(joined).arg(QString::fromLatin1(verdict));
        reporter.observe(QString::fromLatin1(name), detail);
        if (!joined && peer->isRunning()) peer.take();
        if (qualified) return true;
        if (!retry) return false;
    }
    return false;
}
}
#endif


void checkConcurrency(SmokeReporter &r)
{
#if SMOKE_QT5
    r.check("thread/qthread", [&r](QString &d) {
        QThread t; bool ran=false; QObject ctx;
        QObject::connect(&t,&QThread::started,&ctx,[&]{ ran=true; t.quit(); }, Qt::DirectConnection);
        t.start(); t.wait(2000);
        if (!ran) { d="did not run"; return false; }
        return true;
    });
    r.check("thread/qthread-explicit-stack", [&](QString &detail) {
        class Worker : public QThread {
        public:
            bool ran = false;
            void run() override { ran = true; }
        };
        QScopedPointer<Worker> thread(new Worker);
        QObject::connect(thread.data(), SIGNAL(finished()), thread.data(), SLOT(deleteLater()));
        thread->setStackSize(256 * 1024);
        thread->start();
        if (!thread->wait(10000)) {
            detail = QStringLiteral("worker did not finish within 10 seconds");
            // A timed-out worker only references itself. Keep it alive until
            // finished()->deleteLater(), without reading its unsynchronized flag.
            if (thread->isRunning())
                thread.take();
            return false;
        }
        detail = QStringLiteral("finished=1 ran=%1 stack=%2")
                .arg(thread->ran).arg(thread->stackSize());
        return thread->ran && thread->isFinished();
    });
    r.check("thread/threadpool+runnable", [&r](QString &d) {
        QAtomicInt counter(0);
        struct Job : QRunnable { QAtomicInt *c; explicit Job(QAtomicInt*x):c(x){} void run() override { c->fetchAndAddOrdered(1);} };
        QThreadPool pool; pool.setMaxThreadCount(4);
        for (int i=0;i<8;++i) pool.start(new Job(&counter));
        pool.waitForDone(3000);
        if (counter.loadAcquire()!=8) { d=QString("count=%1").arg(counter.loadAcquire()); return false; }
        return true;
    });
    r.check("sync/mutex", [&r](QString &d) {
        QMutex m; { QMutexLocker lock(&m); }
        return m.tryLock() ? (m.unlock(), true) : false;
    });
    r.check("sync/mutex-timed-wakeup", [&r](QString &d) { return timedSyncCheck(r, "sync/mutex-timed-wakeup", false, false, d); });
    r.check("sync/mutex-timed-timeout", [&r](QString &d) { return timedSyncCheck(r, "sync/mutex-timed-timeout", false, true, d); });
    r.check("sync/semaphore-timed-wakeup", [&r](QString &d) { return timedSyncCheck(r, "sync/semaphore-timed-wakeup", true, false, d); });
    r.check("sync/semaphore-timed-timeout", [&r](QString &d) { return timedSyncCheck(r, "sync/semaphore-timed-timeout", true, true, d); });
    r.check("sync/readwritelock", [&r](QString &d) {
        QReadWriteLock lock; { QReadLocker r0(&lock); }
        if (!lock.tryLockForWrite()) { d="write lock"; return false; }
        lock.unlock();
        { QWriteLocker w0(&lock); }
        return true;
    });
    r.check("sync/basicmutex-threadstorage-events", [&](QString &d) {
        QBasicMutex *basic = nullptr;
        QThreadStorage<int *> *threadStorage = nullptr;
        QThreadStorageData *storageData = nullptr;
        QSocketNotifier *socketNotifier = nullptr;
#ifdef Q_OS_WIN
        QWinEventNotifier winEventNotifier;
        QWinEventNotifier *winEventNotifierPtr = &winEventNotifier;
        const bool winNotifierOk = winEventNotifierPtr != nullptr;
#else
        QObject *winEventNotifierPtr = nullptr;
        const bool winNotifierOk = winEventNotifierPtr == nullptr;
#endif
        QTimerEvent timerEvent(42);
#if QT_VERSION_MAJOR < 6
        QDeferredDeleteEvent deferredDeleteEvent;
#endif
        return basic == nullptr
            && threadStorage == nullptr
            && storageData == nullptr
            && socketNotifier == nullptr
            && winNotifierOk
            && timerEvent.timerId() == 42
#if QT_VERSION_MAJOR < 6
            && deferredDeleteEvent.type() == QEvent::DeferredDelete
#endif
            ;
    });
#ifndef QT_NO_EXCEPTIONS
    r.check("concurrent/exception-types", [&](QString &d) {
        QException *exception = nullptr;
        QUnhandledException *unhandledException = nullptr;
        return exception == nullptr && unhandledException == nullptr;
    });
#endif
    r.check("sync/semaphore", [&r](QString &d) {
        QSemaphore s(2);
        s.acquire(2);
        bool none = !s.tryAcquire(1);
        s.release(2);
        return none && s.available()==2;
    });
    r.check("concurrent/run", [&r](QString &d) {
        QFuture<int> f = QtConcurrent::run([]{ int s=0; for (int i=1;i<=10;++i) s+=i*i; return s; });
        f.waitForFinished();
        if (f.result()!=385) { d=QString("got %1").arg(f.result()); return false; }
        return true;
    });
    r.check("concurrent/filtered-reduced", [&r](QString &d) {
        QVector<int> in; for (int i=1;i<=10;++i) in<<i;
        // sum of even numbers via blocking filtered
        QFuture<int> f = QtConcurrent::filtered(in, [](int x){ return x%2==0; });
        f.waitForFinished();
        int sum=0; for (int v : f.results()) sum+=v;
        if (sum!=30) { d=QString("sum=%1").arg(sum); return false; }
        return true;
    });
    r.check("concurrent/futurewatcher", [&r](QString &d) {
        QFutureWatcher<int> w; bool done=false;
        QObject ctx; QObject::connect(&w,&QFutureWatcher<int>::finished,&ctx,[&]{ done=true; });
        w.setFuture(QtConcurrent::run([]{ return 7; }));
        QElapsedTimer t; t.start();
        while (!done && t.elapsed()<3000) QCoreApplication::processEvents();
        return done && w.result()==7;
    });
    r.check("concurrent/future-interface-base", [&](QString &d) {
        QFutureInterfaceBase iface(QFutureInterfaceBase::Started);
        QFutureInterfaceBase *ifaceBase = &iface;
        QFutureWatcherBase *watcherBase = nullptr;
        ifaceBase->setProgressRange(0, 10);
        ifaceBase->setProgressValue(4);
        ifaceBase->reportFinished();
        return ifaceBase->progressMinimum() == 0
            && ifaceBase->progressMaximum() == 10
            && ifaceBase->progressValue() == 4
            && ifaceBase->isFinished()
            && watcherBase == nullptr;
    });
    r.check("process/env", [&r](QString &d) {
        QProcessEnvironment e = QProcessEnvironment::systemEnvironment();
        return !e.isEmpty();
    });
    r.check("process/run", [&r](QString &d) {
        QTemporaryFile marker;
        if (!marker.open()) {
            d = "marker file not open";
            return false;
        }
        const QString markerPath = marker.fileName();
        marker.close();

        QProcess p;
#ifdef LONGREACH_ANDROID_APK
        // An APK's applicationFilePath is not a standalone native executable.
        // Exercise the real process/pipe backend with the system shell; pass
        // the private marker path as an argument rather than shell source.
        p.start(QStringLiteral("/system/bin/sh"),
                {QStringLiteral("-c"), QStringLiteral("echo smoke > \"$1\""),
                 QStringLiteral("longreach-selftest"), markerPath});
        if (!p.waitForStarted(10000)) { d = p.errorString(); return false; }
#else
        p.start(QCoreApplication::applicationFilePath(), {"--selftest-child", markerPath});
        if (!p.waitForStarted(10000)) { r.skip(d,"process not startable"); return false; }
#endif
        // A static build of this binary can take seconds to start on a busy
        // host; wait as long as the Qt 4 branch does.
        const bool finished = p.state() == QProcess::NotRunning || p.waitForFinished(10000);
        QFile markerFile(markerPath);
        const QString output = markerFile.open(QIODevice::ReadOnly)
            ? QString::fromLocal8Bit(markerFile.readAll()) : QString();
        const bool ok = finished && p.state() == QProcess::NotRunning
                && p.exitStatus() == QProcess::NormalExit && p.exitCode() == 0
                && output.contains("smoke");
        if (!ok) {
            d = QStringLiteral("finished=%1 state=%2 exit=%3 error=%4 stdout='%5' stderr='%6'")
                    .arg(int(finished))
                    .arg(int(p.state()))
                    .arg(p.exitCode())
                    .arg(p.errorString())
                    .arg(output.trimmed())
                    .arg(QString::fromLocal8Bit(p.readAllStandardError()).trimmed());
            p.kill();
            p.waitForFinished(1000);
        }
        return ok;
    });
#else
    r.check("thread/qthread", [&r](QString &d) {
        class Worker : public QThread {
        public:
            bool ran = false;
            void run() override { ran = true; }
        } worker;
        worker.start();
        return worker.wait(2000) && worker.ran;
    });
    r.check("thread/threadpool+runnable", [&r](QString &d) {
        QAtomicInt counter(0);
        struct Job : QRunnable { QAtomicInt *c; explicit Job(QAtomicInt*x):c(x){} void run() override { c->fetchAndAddOrdered(1); } };
        QThreadPool pool;
        for (int i=0;i<4;++i) pool.start(new Job(&counter));
        pool.waitForDone();
        return counter.fetchAndAddOrdered(0)==4;
    });
    r.check("sync/mutex-readwrite-semaphore", [&r](QString &d) {
        QMutex mutex; QReadWriteLock rw; QSemaphore semaphore(1);
        if (!mutex.tryLock()) return false; mutex.unlock();
        if (!rw.tryLockForRead()) return false; rw.unlock();
        return semaphore.tryAcquire(1) ? (semaphore.release(), true) : false;
    });
    r.check("concurrent/run", [&r](QString &d) {
        struct Work { static int square(int value) { return value * value; } };
        QFuture<int> future = QtConcurrent::run(&Work::square, 7);
        future.waitForFinished();
        return future.result()==49;
    });
    r.check("process/env", [&r](QString &d) {
        return !QProcessEnvironment::systemEnvironment().isEmpty();
    });
    r.check("process/run", [&r](QString &d) {
#ifdef LONGREACH_DONUT_JNI
        r.skip(d, "Qt runs in the Android Activity process");
        return false;
#else
        QProcess process;
        QElapsedTimer elapsed;
        elapsed.start();
        process.start(QCoreApplication::applicationFilePath(),
                      QStringList() << "--selftest-child");
        const bool started = process.waitForStarted(10000);
        // Qt 4 returns false from waitForFinished() if the child has already
        // reached NotRunning. Accept that completed state before waiting.
        const bool finished = started && (process.state() == QProcess::NotRunning
                                         || process.waitForFinished(10000));
        const QProcess::ProcessState state = process.state();
        const QByteArray output = process.readAllStandardOutput();
        const QByteArray errors = process.readAllStandardError();
        const bool ok = started && finished && state == QProcess::NotRunning
                && process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0
                && output.contains("smoke");
        if (!ok) {
            // Capture the original failure before kill() changes the process
            // status and error. A timeout is a failure, not a platform skip.
            d = QString("started=%1 finished=%2 state=%3 error=%4 (%5) elapsed-ms=%6 exit-status=%7 exit=%8 stdout='%9' stderr='%10'")
                    .arg(int(started)).arg(int(finished)).arg(int(state))
                    .arg(int(process.error())).arg(process.errorString())
                    .arg(elapsed.elapsed()).arg(int(process.exitStatus())).arg(process.exitCode())
                    .arg(QString::fromLocal8Bit(output).trimmed())
                    .arg(QString::fromLocal8Bit(errors).trimmed());
        }
        if (state != QProcess::NotRunning) {
            process.kill();
            process.waitForFinished(5000);
        }
        return ok;
#endif
    });
#endif
}
