// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

#ifndef SMOKE_SPEECH_TAB_H
#define SMOKE_SPEECH_TAB_H

#include <QWidget>

class SmokeReporter;

QWidget *makeSpeechTab();
void addSpeechChecks(SmokeReporter &reporter);

#endif
