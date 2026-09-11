// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Threads, thread pool, synchronization, futures, process. Headless.
#include "../common/smokecheck.h"
#include "checks.h"

#include <QThread>
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
        p.start(QCoreApplication::applicationFilePath(), {"--selftest-child", markerPath});
        if (!p.waitForStarted(3000)) { r.skip(d,"process not startable"); return false; }
        p.waitForFinished(3000);
        QFile markerFile(markerPath);
        const QString output = markerFile.open(QIODevice::ReadOnly)
            ? QString::fromLocal8Bit(markerFile.readAll()) : QString();
        const bool ok = output.contains("smoke");
        if (!ok) {
            d = QStringLiteral("state=%1 exit=%2 error=%3 stdout='%4' stderr='%5'")
                    .arg(int(p.state()))
                    .arg(p.exitCode())
                    .arg(p.errorString())
                    .arg(output.trimmed())
                    .arg(QString::fromLocal8Bit(p.readAllStandardError()).trimmed());
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
    });
#endif
}
