// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

WorkerScript.onMessage = function(message) {
    WorkerScript.sendMessage({ value: message.value * 2 })
}
