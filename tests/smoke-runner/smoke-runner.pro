# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon

TEMPLATE = app
TARGET = smoke-runner
CONFIG += release console
CONFIG -= app_bundle
QT += core
QT -= gui
SOURCES += main.cpp

# The cross qmake runs with -unix on its Linux host, so the win32 scope is
# false. Only the Win95 cross-build passes WIN95_CROSS=1.
contains(WIN95_CROSS, 1):QMAKE_LFLAGS += -static -Wl,-subsystem,console
