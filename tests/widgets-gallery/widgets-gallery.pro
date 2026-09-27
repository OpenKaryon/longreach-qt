# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 4 build of widgets-gallery (Qt 5 and 6 use CMake), with the Qt 4-only sweep.
TEMPLATE = app
TARGET = widgets-gallery
CONFIG += release console
CONFIG -= app_bundle
QT = core gui network sql testlib qt3support multimedia
DEFINES += QT_VERSION_MAJOR=4 QT_VERSION_MINOR=8
QMAKE_CXXFLAGS += -std=gnu++14
SOURCES += main.cpp gallery.cpp selftest.cpp checks_qtbase_extra.cpp \
    checks_events_models.cpp checks_graphics_extras.cpp checks_qt3support.cpp \
    checks_qtbase_qt4.cpp checks_platform4.cpp checks_qtbase_tail2_qt4.cpp \
    checks_accessibility_qt4.cpp
HEADERS += gallery.h ../common/smokecheck.h ../common/qtcompat.h
exists($$[QT_INSTALL_LIBS]/libQtUiTools.a) {
    CONFIG += uitools
    DEFINES += SMOKE_HAVE_UITOOLS
}
contains(WIN95_CROSS, 1) {
    QMAKE_LFLAGS += -static -Wl,-subsystem,windows
}
contains(WIN95_ACCESSIBILITY, 1) {
    DEFINES += QT4_WIN95_ACCESSIBILITY_PROBE
    LIBS += $$[QT_INSTALL_PLUGINS]/accessible/libqtaccessiblewidgets.a
}
