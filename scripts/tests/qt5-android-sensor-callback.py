#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Host behavioral regression for the actual QtSensors looper callback.

Compile the callback extracted from a prepared sensoreventqueue.h with narrow
event-source/posting substitutes. Check empty/error reads and a continuously
ready producer. This does not qualify the Android ABI or queue teardown.
"""
import argparse
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('source', type=Path)
parser.add_argument('output', type=Path)
parser.add_argument('--manager', type=Path)
args = parser.parse_args()
source = args.source.read_text()
begin = source.index('    static int looperCallback(')
end = source.index('\nprotected:', begin)
function = source[begin:end]
args.output.mkdir(parents=True, exist_ok=True)
prefix = r'''
#include <functional>
#include <cstdio>
#include <stdexcept>
#include <atomic>
#include <memory>
#include <vector>
struct ASensorEvent { int value = 0; };
struct ASensorEventQueue { int remaining, terminal, calls = 0; bool continuous; };
static int ASensorEventQueue_getEvents(ASensorEventQueue *q, ASensorEvent *event, int) {
    if (++q->calls > 128)
        throw std::runtime_error("callback did not return control to the looper");
    if (q->continuous || q->remaining > 0) {
        --q->remaining;
        event->value = 42;
        return 1;
    }
    return q->terminal;
}
struct FunctionEvent {
    std::function<void()> function;
    explicit FunctionEvent(const std::function<void()> &f): function(f) {}
};
class SensorEventQueue;
struct ReceiverState { SensorEventQueue *backend; };
struct BackendGuard {
    std::shared_ptr<ReceiverState> state;
    explicit operator bool() const { return state && state->backend; }
    SensorEventQueue *operator->() const { return state->backend; }
};
struct SensorEventReceiver {
    std::vector<std::unique_ptr<FunctionEvent>> pending;
};
struct QCoreApplication {
    static void postEvent(SensorEventReceiver *receiver, FunctionEvent *event) {
        receiver->pending.emplace_back(event);
    }
    static void postEvent(SensorEventQueue *, FunctionEvent *event);
};
class SensorEventQueue {
public:
    struct DeliveryState {
        std::atomic<bool> retired{false};
        BackendGuard backend;
    };
    struct QueueContext {
        std::atomic<ASensorEventQueue *> queue{nullptr};
        std::shared_ptr<DeliveryState> delivery = std::make_shared<DeliveryState>();
        SensorEventReceiver *receiver;
    };
    ASensorEventQueue *m_sensorEventQueue;
    int delivered = 0;
    void dataReceived(const ASensorEvent &event) {
        if (event.value != 42) throw std::runtime_error("posted an invalid reading");
        ++delivered;
    }
'''
suffix = r'''
};
static SensorEventReceiver oldReceiver;
void QCoreApplication::postEvent(SensorEventQueue *, FunctionEvent *event) {
    oldReceiver.pending.emplace_back(event);
}
int main() {
    int failures = 0;
    for (int profile = 0; profile < (QUEUE_CONTEXT_PROFILE ? 8 : 4); ++profile) {
        ASensorEventQueue native{profile == 2 || profile == 5 || profile == 7 ? 3 : 0,
                                profile == 1 ? 0 : -11, 0, profile == 3};
        SensorEventQueue backend{&native};
        auto owner = std::make_shared<ReceiverState>(ReceiverState{&backend});
        SensorEventReceiver receiver;
        SensorEventQueue::QueueContext context;
        context.queue.store(profile == 6 ? nullptr : &native);
        context.delivery->retired.store(profile == 4);
        context.receiver = &receiver;
        context.delivery->backend = BackendGuard{owner};
        const char *name[] = {"empty-negative", "empty-zero", "finite-burst", "continuous-producer",
                              "retired-queue", "destroyed-backend", "unpublished-queue", "retire-after-post"};
        bool ok = false;
        try {
            void *data = QUEUE_CONTEXT_PROFILE ? static_cast<void *>(&context) : &backend;
            const int keep = SensorEventQueue::looperCallback(0, 0, data);
            if (profile == 5) owner->backend = nullptr;
            if (profile == 7) context.delivery->retired = true;
            auto &pending = QUEUE_CONTEXT_PROFILE ? receiver.pending : oldReceiver.pending;
            for (auto &event : pending) event->function();
            pending.clear();
            if (profile < 2) ok = keep == 1 && native.calls == 1 && backend.delivered == 0;
            if (profile == 2) ok = keep == 1 && native.calls == 4 && backend.delivered == 3;
            if (profile == 3) ok = keep == 1 && native.calls > 0 && native.calls <= 64
                                      && backend.delivered == native.calls;
            if (profile == 4) ok = keep == 0 && native.calls == 0 && backend.delivered == 0;
            if (profile == 5) ok = keep == 1 && native.calls == 4 && backend.delivered == 0;
            if (profile == 6) ok = keep == 1 && native.calls == 0 && backend.delivered == 0;
            if (profile == 7) ok = keep == 1 && native.calls == 4 && backend.delivered == 0;
        } catch (const std::exception &error) {
            std::printf("%s: %s\n", name[profile], error.what());
        }
        std::printf("%s: reads=%d delivered=%d %s\n", name[profile], native.calls,
                    backend.delivered, ok ? "PASS" : "FAIL");
        failures += !ok;
        oldReceiver.pending.clear();
    }
    return failures ? 1 : 0;
}
'''
program = args.output / 'sensor-callback.cpp'
program.write_text(f'#define QUEUE_CONTEXT_PROFILE {int("QueueContext" in function)}\n' + prefix + function + suffix)
binary = args.output / 'sensor-callback'
subprocess.run(['clang++-21', '-std=c++17', '-O2', str(program), '-o', str(binary)], check=True)
result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=5)
print(result.stdout, end='', flush=True)
if result.returncode:
    raise SystemExit(result.returncode)

if args.manager:
    manager = args.manager.read_text()
    start = manager.index('void SensorManager::retireQueue(')
    finish = manager.index('\nstatic inline ASensorManager', start)
    declarations = r'''
#include <atomic>
#include <functional>
#include <thread>
#include <vector>
#include <cstdio>
class SensorManager {
public:
    struct RetiredQueue { std::function<void()> cleanup; RetiredQueue *next; };
    std::atomic<RetiredQueue *> m_retiredQueues{nullptr};
    std::atomic<bool> m_dispatchStopped{false};
    void retireQueue(const std::function<void()> &cleanup);
    void drainRetiredQueues();
};
'''
    retirement = r'''
int main() {
    SensorManager manager;
    std::atomic<bool> active{false}, release{false}, ready{false};
    std::atomic<int> calls{0}, early{0};
    std::thread dispatch([&] {
        active = true; ready = true;
        while (!release.load()) std::this_thread::yield();
        active = false;
        manager.drainRetiredQueues();
    });
    while (!ready.load()) std::this_thread::yield();
    manager.retireQueue([&] { early += active.load() ? 1 : 0; ++calls; });
    bool ok = calls.load() == 0;
    release = true;
    dispatch.join();
    ok = ok && calls == 1 && early == 0;
    std::printf("deferred-dispatch-cleanup: calls=%d early=%d %s\n",
                calls.load(), early.load(), ok ? "PASS" : "FAIL");
    std::atomic<int> done{0}, executed{0};
    std::thread consumer([&] {
        while (done < 4) {
            manager.drainRetiredQueues();
            std::this_thread::yield();
        }
        manager.drainRetiredQueues();
    });
    std::vector<std::thread> producers;
    for (int p = 0; p < 4; ++p) producers.emplace_back([&] {
        for (int n = 0; n < 512; ++n) manager.retireQueue([&] { ++executed; });
        ++done;
    });
    for (auto &producer : producers) producer.join();
    consumer.join();
    bool concurrent = executed == 2048;
    std::printf("concurrent-retirement-cleanup: executed=%d %s\n",
                executed.load(), concurrent ? "PASS" : "FAIL");
    manager.m_dispatchStopped.store(true, std::memory_order_release);
    int lateCalls = 0;
    manager.retireQueue([&] { ++lateCalls; });
    bool late = lateCalls == 1 && manager.m_retiredQueues.load() == nullptr;
    std::printf("retirement-after-dispatch-stopped: calls=%d %s\n", lateCalls, late ? "PASS" : "FAIL");
    return ok && concurrent && late ? 0 : 1;
}
'''
    program = args.output / 'sensor-retirement.cpp'
    program.write_text(declarations + manager[start:finish] + retirement)
    binary = args.output / 'sensor-retirement'
    subprocess.run(['clang++-21', '-std=c++17', '-pthread', '-O2', str(program), '-o', str(binary)], check=True)
    result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=5)
    print(result.stdout, end='', flush=True)
    raise SystemExit(result.returncode)
