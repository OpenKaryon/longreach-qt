# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon

TEMPLATE = app
TARGET = quick-qml-gallery
CONFIG += release console
CONFIG -= app_bundle
QT = core gui declarative opengl svg network script xmlpatterns
DEFINES += QT_VERSION_MAJOR=4 QT_VERSION_MINOR=8
QMAKE_CXXFLAGS += -std=gnu++14
SOURCES += main.cpp selftest.cpp checks_declarative1_qt4.cpp
HEADERS += ../common/smokecheck.h ../common/qtcompat.h ../common/crashinfo.h
HEADERS += qt4_static_imports.h
RESOURCES += qml_qt4.qrc
QT4_IMPORT_ROOT = $$[QT_INSTALL_IMPORTS]/Qt/labs
LIBS += $$QT4_IMPORT_ROOT/folderlistmodel/libqmlfolderlistmodelplugin.a
LIBS += $$QT4_IMPORT_ROOT/gestures/libqmlgesturesplugin.a
LIBS += $$QT4_IMPORT_ROOT/particles/libqmlparticlesplugin.a
LIBS += $$QT4_IMPORT_ROOT/shaders/libqmlshadersplugin.a
LIBS += $$[QT_INSTALL_PLUGINS]/imageformats/libqsvg.a
contains(WIN95_CROSS, 1) {
    QMAKE_LFLAGS += -static -Wl,-subsystem,windows
}
