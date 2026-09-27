# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt 4 build of qt-selftest (Qt 5 and 6 use CMake); needs a C++14 compiler.
TEMPLATE = app
TARGET = qt-selftest
CONFIG += release console
CONFIG -= app_bundle
QT = core gui network sql xml svg
DEFINES += QT_VERSION_MAJOR=4 QT_VERSION_MINOR=8
QMAKE_CXXFLAGS += -std=gnu++14
SOURCES += main.cpp $$files(checks_*.cpp)
SOURCES -= checks_qtbase_misc.cpp
HEADERS += checks.h ../common/smokecheck.h ../common/qtcompat.h
exists($$[QT_INSTALL_LIBS]/libQtScript.a):exists($$[QT_INSTALL_LIBS]/libQtScriptTools.a) {
    QT += script scripttools
    DEFINES += SMOKE_HAVE_SCRIPT
}
exists($$[QT_INSTALL_LIBS]/libQtXmlPatterns.a) {
    QT += xmlpatterns
    DEFINES += SMOKE_HAVE_XMLPATTERNS
}
contains(WIN95_CROSS, 1) {
    DEFINES += SMOKE_STATIC_QSQLITE
    LIBS += -L$$[QT_INSTALL_PLUGINS]/sqldrivers -lqsqlite
    QMAKE_LFLAGS += -static -Wl,-subsystem,console
}
