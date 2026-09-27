# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon

TEMPLATE = app
TARGET = graphics-gallery
CONFIG += release console
CONFIG -= app_bundle
QT = core gui svg
DEFINES += QT_VERSION_MAJOR=4 QT_VERSION_MINOR=8
QMAKE_CXXFLAGS += -std=gnu++14
SOURCES += main.cpp canvas.cpp selftest.cpp
HEADERS += graphics.h ../common/smokecheck.h ../common/qtcompat.h
contains(WIN95_CROSS, 1) {
    QMAKE_LFLAGS += -static -Wl,-subsystem,windows
}
