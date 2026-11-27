// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include "tls-owner-interface.h"
#include "../common/smokecheck.h"
#include <QAndroidJniObject>
#include <QtAndroid>
#include <QFileInfo>
#include <QJsonObject>
#include <QPluginLoader>
#include <QPointer>
#include <atomic>
#include <thread>

namespace SmokePluginTlsOwner {
inline void destroyedTls(void *context)
{
    static_cast<std::atomic<int> *>(context)->fetch_add(1);
}

inline int run()
{
    SmokeReporter r("plugin-tls-owner");
    const auto info = QtAndroid::androidActivity().callObjectMethod(
        "getApplicationInfo", "()Landroid/content/pm/ApplicationInfo;");
    const auto directory = info.getObjectField<jstring>("nativeLibraryDir").toString();
    const auto path = directory + QStringLiteral("/liblongreach_tls_owner_probe.so");
    r.check("plugin-owner/packaged-library", [&](QString &d) {
        d = QFileInfo(path).fileName();
        return !directory.isEmpty() && QFileInfo(path).isFile();
    });
    // Both callback destinations outlive the loader, including early failures.
    std::atomic<int> tlsDestructors{0};
    std::atomic<int> objectDestructors{0};
    QPluginLoader owner(path);
    r.check("plugin-owner/metadata", [&](QString &d) {
        const auto iid = owner.metaData().value(QStringLiteral("IID")).toString();
        d = iid;
        return iid == QString::fromLatin1(SmokeTlsOwnerInterface_iid);
    });
    QObject *object = owner.instance();
    QPointer<QObject> guardedObject(object);
    auto *plugin = qobject_cast<SmokeTlsOwnerInterface *>(object);
    if (object) QObject::connect(object, &QObject::destroyed, [&] {
        objectDestructors.fetch_add(1);
    });
    r.check("plugin-owner/instance-interface", [&](QString &d) {
        d = plugin ? QString::fromLatin1(object->metaObject()->className()) : owner.errorString();
        return plugin && owner.isLoaded();
    });
    int returned = -1;
    bool joined = false;
    if (plugin) {
        // std::thread::join waits through C++ TLS destruction. No unload or
        // owner destruction occurs while this thread or its TLS is alive.
        std::thread worker([&] { returned = plugin->touch(destroyedTls, &tlsDestructors); });
        worker.join();
        joined = true;
    }
    r.check("plugin-owner/worker-joined", [&](QString &d) {
        d = QStringLiteral("joined=%1 return=%2 owner_loaded=%3")
            .arg(joined).arg(returned).arg(owner.isLoaded());
        return joined && returned == 43 && owner.isLoaded();
    });
    r.check("plugin-owner/tls-destructor-before-unload", [&](QString &d) {
        d = QStringLiteral("tls_destructors=%1 object_destructors=%2 owner_loaded=%3")
            .arg(tlsDestructors.load()).arg(objectDestructors.load()).arg(owner.isLoaded());
        return joined && tlsDestructors.load() == 1
            && objectDestructors.load() == 0 && owner.isLoaded();
    });
    std::printf("PLUGIN_TLS_OWNER: protocol=1 joined=%d return=%d tls_before_unload=%d object_before_unload=%d loaded_before_unload=%d\n",
                int(joined), returned, tlsDestructors.load(), objectDestructors.load(), int(owner.isLoaded()));
    std::fflush(stdout);
    // Drop the interface before unloading; it is never used after this point.
    plugin = nullptr;
    object = nullptr;
    const bool unloaded = joined && owner.unload();
    r.check("plugin-owner/unload-after-join", [&](QString &d) {
        d = QStringLiteral("unload=%1 loaded=%2 object_destructors=%3 tls_destructors=%4")
            .arg(unloaded).arg(owner.isLoaded()).arg(objectDestructors.load()).arg(tlsDestructors.load());
        return unloaded && !owner.isLoaded() && guardedObject.isNull()
            && objectDestructors.load() == 1 && tlsDestructors.load() == 1;
    });
    std::printf("PLUGIN_TLS_OWNER: unload_after_join=%d loaded_after_unload=%d object_after_unload=%d tls_after_unload=%d live_TLS_unload_executed=0 callback_after_unmapping_invoked=0\n",
                int(unloaded), int(owner.isLoaded()), objectDestructors.load(), tlsDestructors.load());
    std::fflush(stdout);
    return r.summary();
}
} // namespace SmokePluginTlsOwner
