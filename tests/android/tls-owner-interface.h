// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <QtPlugin>

class SmokeTlsOwnerInterface
{
public:
    using Notify = void (*)(void *);
    virtual ~SmokeTlsOwnerInterface() = default;
    virtual int touch(Notify notify, void *context) = 0;
};

#define SmokeTlsOwnerInterface_iid "org.longreachqt.tests.TlsOwner/1.0"
Q_DECLARE_INTERFACE(SmokeTlsOwnerInterface, SmokeTlsOwnerInterface_iid)
