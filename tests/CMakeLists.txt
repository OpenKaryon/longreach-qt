# The smoke-test suite: eight applications that exercise the public Qt API
# once each, every one with --selftest (console PASS/FAIL), so results compare
# across targets. Qt 5 and Qt 6 build it with CMake; Qt 4 with each
# application's .pro (scripts/build/qt4-tests.sh).
#
#   qt-selftest        core, io, serialization, network, sql, threads, ...
#   widgets-gallery    widgets, item views, dialogs, tray, clipboard, styles
#   graphics-gallery   QPainter, images, shaped windows, animation
#   quick-qml-gallery  QML, Qt Quick, Quick 3D
#   gl-heavy-gallery   OpenGL, Qt3D, Charts, DataVisualization
#   painting-lab       raster, text, alpha, printing
#   multimedia-lab     media, camera, audio
#   network-gui        TCP, UDP, WebSocket, HTTP
#   smoke-runner       runs every application with --selftest and writes a report
cmake_minimum_required(VERSION 3.10)

# C too: Qt 6's FindWMF.cmake searches CMAKE_C_IMPLICIT_LINK_DIRECTORIES,
# which is empty with CXX alone.
project(qt-smoke-tests LANGUAGES C CXX)

# The Qt major version, once; Qt 6 is preferred when both are visible.
find_package(QT NAMES Qt6 Qt5 QUIET COMPONENTS Core)
if(NOT QT_FOUND)
    message(FATAL_ERROR
        "no Qt 5 or Qt 6 found; point CMAKE_PREFIX_PATH at an SDK. "
        "Qt 4 builds this suite with qmake (scripts/build/qt4-tests.sh).")
endif()

message(STATUS "qt-smoke: building against Qt ${QT_VERSION_MAJOR} "
               "(${QT_VERSION}) for ${CMAKE_SYSTEM_NAME}")

set(SMOKE_LICENSE_PROFILE "gpl-enabled" CACHE STRING
    "License ceiling: lgpl-friendly, gpl-enabled, or commercial-qt")
set_property(CACHE SMOKE_LICENSE_PROFILE PROPERTY STRINGS
    lgpl-friendly gpl-enabled commercial-qt)
if(NOT SMOKE_LICENSE_PROFILE MATCHES "^(lgpl-friendly|gpl-enabled|commercial-qt)$")
    message(FATAL_ERROR "invalid SMOKE_LICENSE_PROFILE=${SMOKE_LICENSE_PROFILE}")
endif()
message(STATUS "qt-smoke: license profile ${SMOKE_LICENSE_PROFILE}")

set(SMOKE_GPL_ONLY_MODULES
    Charts DataVisualization Graphs GraphsWidgets Quick3D Quick3DRuntimeRender
    NetworkAuth VirtualKeyboard Mqtt Coap HttpServer)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(SmokeApp)

# Every module an application might link, found in one umbrella call: Qt 6's
# per-module packages need it first, and repeating it per application
# redefines imported targets. QUIET, as several modules exist in only one
# version. GuiPrivate is defined by Qt5Gui/Qt6Gui and linked directly.
set(SMOKE_MODULES
    # core, present in both
    Core Gui Widgets Network Sql Concurrent Xml Svg SvgWidgets PrintSupport Test
    Qml Quick QuickWidgets QuickControls2 QmlWorkerScript QmlModels
    QuickTemplates2
    Multimedia MultimediaWidgets
    WebSockets WebChannel WebChannelQuick NetworkAuth SerialPort Sensors Bluetooth Nfc
    SerialBus Scxml RemoteObjects TextToSpeech Location
    OpcUa Mqtt Coap HttpServer Core5Compat DBus X11Extras MacExtras SpatialAudio VirtualKeyboard OpenGL Graphs ShaderTools
    Grpc Protobuf GrpcQuick GraphsWidgets WaylandCompositor WaylandClient
    Charts DataVisualization
    3DCore 3DRender 3DInput 3DLogic 3DExtras 3DAnimation 3DQuick 3DQuickScene2D

    # Qt 5 only
    Script ScriptTools XmlPatterns Gamepad Purchasing WinExtras

    QuickParticles QuickShapes

    # optional everywhere: configured in or out, or a module of its own in one
    # version (QStateMachine is in QtCore on Qt 5).
    OpenGL Quick3D Quick3DRuntimeRender StateMachine OpenGLWidgets
)
# One call per component: a single call stops at the first missing one and
# leaves the rest unset (on Qt 6 without 3DCore, StateMachine and
# OpenGLWidgets went missing that way).
foreach(smoke_module IN LISTS SMOKE_MODULES)
    if(SMOKE_LICENSE_PROFILE STREQUAL "lgpl-friendly"
            AND smoke_module IN_LIST SMOKE_GPL_ONLY_MODULES)
        continue()
    endif()
    find_package(Qt${QT_VERSION_MAJOR} QUIET COMPONENTS ${smoke_module})
endforeach()

# The QML plugin scanner, likewise found once.
find_package(Qt${QT_VERSION_MAJOR}QmlImportScanner QUIET)

find_package(Threads)

# -Os, as Qt (-optimize-size) and qmake's applications; replacing the
# variable keeps -O3 out of the flags.
if(NOT MSVC)
    set(CMAKE_CXX_FLAGS_RELEASE "-Os -DNDEBUG")
    set(CMAKE_C_FLAGS_RELEASE "-Os -DNDEBUG")
endif()

# Let the linker revisit archives: a static Qt's plugins reference libraries
# already passed (the Controls 2 styles need libQt5QuickControls2.a), and
# quick-qml-gallery does not link without it. Only the opening flag is set:
# CMake has no way to place the closing one after every library, and GNU ld
# runs an open group to the end of the line. ld64 needs neither.
if(WIN32)
    set(CMAKE_CXX_STANDARD_LIBRARIES "${CMAKE_CXX_STANDARD_LIBRARIES} -Wl,-Bstatic")
endif()

if(NOT APPLE)
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,--start-group")
endif()

# Drop unreferenced sections: a static Qt is already compiled with
# -ffunction-sections -fdata-sections (gc_binaries), but nothing collected
# them. ld64 spells it -dead_strip. Plugins are reached through registration
# objects no call site names, which is why the suite is run, not only built,
# after this: a plugin collected by mistake fails loudly.
if(APPLE)
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,-dead_strip")
else()
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,--gc-sections")
endif()

# One directory per application, named after it: tests/expected-apps.txt.
# graphics-gallery and smoke-runner need nothing either Qt version lacks.
add_subdirectory(graphics-gallery)
add_subdirectory(smoke-runner)

# Each other app is added when the SDK has every module it needs; an app left
# out for a reason not recorded in SMOKE_OMITTED_APPS fails the configure step.
set(SMOKE_OMITTED_APPS "")

smoke_require_modules(SMOKE_HAVE_WIDGETS Widgets Test)
if(SMOKE_HAVE_WIDGETS)
    add_subdirectory(widgets-gallery)
endif()

# Script, XmlPatterns, Gamepad and Purchasing exist in one generation only;
# qt-selftest/CMakeLists.txt picks them up one by one, and their checks SKIP
# where they are missing.
set(SMOKE_CONSOLE_MODULES
    Core Gui GuiPrivate Network Sql Concurrent Xml Svg
    Location WebSockets WebChannel SerialPort Multimedia Sensors
    Bluetooth Nfc SerialBus Scxml RemoteObjects TextToSpeech Qml)
set(SMOKE_CONSOLE_REQUIRED_MODULES
    Core Gui Network Sql Concurrent Xml Svg
    Location WebSockets WebChannel SerialPort Multimedia Sensors
    Bluetooth Nfc SerialBus Scxml RemoteObjects TextToSpeech Qml)
if(NOT SMOKE_LICENSE_PROFILE STREQUAL "lgpl-friendly")
    list(APPEND SMOKE_CONSOLE_MODULES NetworkAuth)
    list(APPEND SMOKE_CONSOLE_REQUIRED_MODULES NetworkAuth)
endif()
smoke_require_modules(SMOKE_HAVE_CONSOLE ${SMOKE_CONSOLE_REQUIRED_MODULES})
if(SMOKE_HAVE_CONSOLE)
    add_subdirectory(qt-selftest)
endif()

# Qml alone; the app's own CMakeLists asks for Quick, QuickWidgets and
# QuickControls2 separately.
smoke_require_modules(SMOKE_HAVE_QUICK_QML Qml)
if(SMOKE_HAVE_QUICK_QML)
    add_subdirectory(quick-qml-gallery)
endif()

smoke_require_modules(SMOKE_HAVE_PAINTING_LAB PrintSupport Svg)
if(SMOKE_HAVE_PAINTING_LAB)
    add_subdirectory(painting-lab)
endif()

# Multimedia alone; tests/multimedia-lab/CMakeLists.txt asks for
# MultimediaWidgets separately.
smoke_require_modules(SMOKE_HAVE_MULTIMEDIA_LAB Multimedia)
if(SMOKE_HAVE_MULTIMEDIA_LAB)
    add_subdirectory(multimedia-lab)
endif()

smoke_require_modules(SMOKE_HAVE_NETWORK_GUI Network)
if(SMOKE_HAVE_NETWORK_GUI)
    add_subdirectory(network-gui)
endif()

# Qt3D, Charts and DataVisualization; the last two are GPL-only, so the
# lgpl-friendly profile leaves the app out.
if(SMOKE_LICENSE_PROFILE STREQUAL "lgpl-friendly")
    set(SMOKE_HAVE_GL_HEAVY FALSE)
    list(APPEND SMOKE_OMITTED_APPS gl-heavy-gallery)
    message(STATUS "qt-smoke: gl-heavy-gallery omitted: GPL-only Charts/DataVisualization")
else()
    smoke_require_modules(SMOKE_HAVE_GL_HEAVY 3DCore 3DQuick Charts DataVisualization)
endif()
if(SMOKE_HAVE_GL_HEAVY)
    add_subdirectory(gl-heavy-gallery)
endif()

# Every application in tests/expected-apps.txt is built, or the omission is
# one recorded above.
file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/expected-apps.txt" smoke_expected REGEX "^[a-z]")
foreach(smoke_app IN LISTS smoke_expected)
    if(NOT TARGET ${smoke_app} AND NOT smoke_app IN_LIST SMOKE_OMITTED_APPS)
        message(FATAL_ERROR "qt-smoke: ${smoke_app} is in expected-apps.txt but was not added; "
                            "the SDK lacks a module it requires")
    endif()
endforeach()
