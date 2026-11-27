// SPDX-License-Identifier: GPL-3.0-or-later
#include "tls-owner-interface.h"
#include <QObject>

namespace {
struct Payload {
    SmokeTlsOwnerInterface::Notify notify = nullptr;
    void *context = nullptr;
    ~Payload() { if (notify) notify(context); }
};
}

class SmokeTlsOwnerPlugin final : public QObject, public SmokeTlsOwnerInterface
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID SmokeTlsOwnerInterface_iid)
    Q_INTERFACES(SmokeTlsOwnerInterface)
public:
    int touch(Notify notify, void *context) override
    {
        thread_local Payload payload;
        payload.notify = notify;
        payload.context = context;
        return 43;
    }
};

#include "tls-owner-plugin.moc"
