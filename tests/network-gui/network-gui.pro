# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 4 build of network-gui: the shared main.cpp, with the tabs spelled as
# QObject slots in qt4_ui.cpp. Qt 5 and 6 build it with CMake.
TEMPLATE = app
TARGET = network-gui
CONFIG += release console
CONFIG -= app_bundle
QT = core gui network
DEFINES += QT_VERSION_MAJOR=4 QT_VERSION_MINOR=8
QMAKE_CXXFLAGS += -std=gnu++14
SOURCES += main.cpp qt4_ui.cpp
HEADERS += qt4_ui.h ../common/smokecheck.h ../common/qtcompat.h
contains(WIN95_CROSS, 1) {
    QMAKE_LFLAGS += -static -Wl,-subsystem,windows
}
