# SPDX-License-Identifier: GPL-3.0-or-later
include(/opt/longreach-android-api21/toolchain.cmake)
set(CMAKE_CXX_FLAGS_INIT "${CMAKE_CXX_FLAGS_INIT} -DQT_NO_SHAREDMEMORY -DQT_NO_SYSTEMSEMAPHORE")
get_filename_component(LONGREACH_QT_PREFIX "${CMAKE_CURRENT_LIST_FILE}" DIRECTORY)
set(CMAKE_FIND_ROOT_PATH /opt/longreach-android-api21/sysroot "${LONGREACH_QT_PREFIX}")
list(PREPEND CMAKE_PREFIX_PATH "${LONGREACH_QT_PREFIX}")
set(QT_QMAKE_EXECUTABLE "${LONGREACH_QT_PREFIX}/bin/qmake" CACHE FILEPATH "Qt4 host qmake")
