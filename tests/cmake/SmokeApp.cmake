# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Settings shared by every app in the suite.
#
# Everything here is deliberately expressed against Qt${QT_VERSION_MAJOR}, so
# the same files build under Qt 5 and Qt 6. The version is resolved once in the
# top-level CMakeLists.txt.
#
# Qt 4 builds the suite with qmake instead (scripts/build/qt4-tests.sh).

# The CMake target for a module name, or "" when this Qt has none.
function(smoke_qt_target out_var module)
    set(${out_var} "Qt${QT_VERSION_MAJOR}::${module}" PARENT_SCOPE)
endfunction()

# Whether the SDK has a module, from the one find_package() at the top level
# (SMOKE_MODULES); a module not listed there counts as absent.
function(smoke_have_qt_module out_var module)
    if(NOT module IN_LIST SMOKE_MODULES)
        message(WARNING "smoke_have_qt_module(${module}): not in SMOKE_MODULES, "
                        "so it can never be found - add it there")
        set(${out_var} FALSE PARENT_SCOPE)
        return()
    endif()
    if(Qt${QT_VERSION_MAJOR}${module}_FOUND)
        set(${out_var} TRUE PARENT_SCOPE)
    else()
        set(${out_var} FALSE PARENT_SCOPE)
    endif()
endfunction()

# TRUE only when every named module is present; the missing ones are named
# in the configure log.
function(smoke_require_modules out_var)
    set(missing "")
    foreach(module IN LISTS ARGN)
        smoke_have_qt_module(have ${module})
        if(NOT have)
            list(APPEND missing ${module})
        endif()
    endforeach()
    if(missing)
        string(REPLACE ";" ", " pretty "${missing}")
        message(STATUS "qt-smoke: skipping an app, SDK has no: ${pretty}")
        set(${out_var} FALSE PARENT_SCOPE)
    else()
        set(${out_var} TRUE PARENT_SCOPE)
    endif()
endfunction()

# Import the QML plugins a static QML application needs (without them:
# "module \"QtQuick\" is not installed" at run time). The command is
# version-stamped, hence the function. Extra arguments are directories the
# scanner should also read, for QML generated into the build tree.
function(smoke_import_qml_plugins target)
    if(QT_VERSION_MAJOR EQUAL 5)
        qt5_import_qml_plugins(${target} PATH_TO_SCAN ${ARGN})
    else()
        qt6_import_qml_plugins(${target} PATH_TO_SCAN ${ARGN})
    endif()
endfunction()

# Add one smoke-test application.
#
#   smoke_add_app(widgets-gallery
#       SOURCES  main.cpp gallery.cpp
#       MODULES  Core Gui Widgets
#       DEFINES  SMOKE_HAVE_WINEXTRAS)
#
# MODULES (without the Qt5/Qt6 prefix) must all exist; OPTIONAL_MODULES are
# linked when present.
function(smoke_add_app target)
    cmake_parse_arguments(ARG "IMPORT_QML_PLUGINS" ""
                          "SOURCES;MODULES;OPTIONAL_MODULES;DEFINES;LIBRARIES;QML_SCAN_PATHS" ${ARGN})

    add_executable(${target} ${ARG_SOURCES})

    # qmake ran moc, uic and rcc automatically; CMake has to be told to.
    set_target_properties(${target} PROPERTIES
        AUTOMOC ON
        AUTOUIC ON
        AUTORCC ON
        CXX_STANDARD 14
        CXX_STANDARD_REQUIRED ON

        # A plain executable everywhere: no macOS bundle, which extract.sh would not
        # collect.
        MACOSX_BUNDLE FALSE

        # A console subsystem on Windows, so --selftest output reaches the terminal.
        WIN32_EXECUTABLE FALSE
    )

    # Modules were found at the top level, and smoke_require_modules() checked
    # them before an app gets here.
    set(smoke_ordered_modules ${ARG_MODULES})
    foreach(module IN LISTS smoke_ordered_modules)
        # GuiPrivate is not a package of its own: Qt5Gui and Qt6Gui define it.
        if(module STREQUAL "GuiPrivate")
            target_link_libraries(${target} PRIVATE Qt${QT_VERSION_MAJOR}::GuiPrivate)
            continue()
        endif()
        smoke_qt_target(tgt ${module})
        if(NOT tgt OR NOT TARGET ${tgt})
            message(FATAL_ERROR
                "${target} needs the ${module} module, which this Qt "
                "${QT_VERSION_MAJOR} SDK does not have. Guard the app with "
                "smoke_require_modules() in tests/CMakeLists.txt, or add the "
                "module to SMOKE_MODULES there.")
        endif()
        target_link_libraries(${target} PRIVATE ${tgt})
    endforeach()

    foreach(module IN LISTS ARG_OPTIONAL_MODULES)
        smoke_qt_target(tgt ${module})
        if(tgt AND TARGET ${tgt})
            target_link_libraries(${target} PRIVATE ${tgt})
        endif()
    endforeach()

    # The offscreen QPA plugin, so the Linux binaries run without a display: a
    # static build links only the plugins it imports, and qt_import_plugins() is
    # what registers one (linking the archive alone does not). INCLUDE keeps xcb;
    # QT_QPA_PLATFORM chooses at run time.
    set(smoke_plugin_include "")
    set(smoke_plugin_exclude "")
    if(UNIX AND NOT APPLE AND TARGET Qt${QT_VERSION_MAJOR}::QOffscreenIntegrationPlugin)
        list(APPEND smoke_plugin_include Qt${QT_VERSION_MAJOR}::QOffscreenIntegrationPlugin)
    endif()

    # qtwayland's generated import names
    # qt_static_plugin_QWaylandEglStreamBufferIntegrationPlugin(), but the archive
    # defines ...EglStreamClientBufferIntegrationPlugin(): a Qt bug, so the plugin
    # is kept out.
    if(TARGET Qt${QT_VERSION_MAJOR}::QWaylandEglStreamBufferIntegrationPlugin)
        list(APPEND smoke_plugin_exclude
             Qt${QT_VERSION_MAJOR}::QWaylandEglStreamBufferIntegrationPlugin)
    endif()

    # QtSensors' iio-sensor-proxy backend and QtNfc both carry moc output for
    # OrgFreedesktopDBusPropertiesInterface, which two static archives cannot share
    # in one link; the sensor checks do not need the backend.
    if(TARGET Qt${QT_VERSION_MAJOR}::IIOSensorProxySensorPlugin)
        list(APPEND smoke_plugin_exclude
             Qt${QT_VERSION_MAJOR}::IIOSensorProxySensorPlugin)
    endif()

    if(smoke_plugin_include OR smoke_plugin_exclude)
        set(smoke_plugin_args "")
        if(smoke_plugin_include)
            list(APPEND smoke_plugin_args INCLUDE ${smoke_plugin_include})
        endif()
        if(smoke_plugin_exclude)
            list(APPEND smoke_plugin_args EXCLUDE ${smoke_plugin_exclude})
        endif()
        if(QT_VERSION_MAJOR EQUAL 6)
            qt_import_plugins(${target} ${smoke_plugin_args})
        else()
            qt5_import_plugins(${target} ${smoke_plugin_args})
        endif()
    endif()

    if(ARG_LIBRARIES)
        target_link_libraries(${target} PRIVATE ${ARG_LIBRARIES})
    endif()

    if(ARG_DEFINES)
        target_compile_definitions(${target} PRIVATE ${ARG_DEFINES})
    endif()

    target_include_directories(${target} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

    # Before smoke_apply_platform_flags() closes the linker group: a QML plugin
    # imported later cannot resolve back into the Qt libraries.
    if(ARG_IMPORT_QML_PLUGINS)
        smoke_import_qml_plugins(${target} ${ARG_QML_SCAN_PATHS})
    endif()

    smoke_apply_platform_flags(${target})
endfunction()

# Flags for every app.
function(smoke_apply_platform_flags target)
    # Static libstdc++ and libgcc, which otherwise impose their own floor on the
    # target (not possible on macOS). LINK_FLAGS, as the Windows images' CMake
    # predates target_link_options().
    if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
        set_property(TARGET ${target} APPEND_STRING PROPERTY
                     LINK_FLAGS " -static-libstdc++ -static-libgcc")
    endif()

    # Windows: -static, or the binaries import libgcc_s, libstdc++ and
    # libwinpthread and die at load time with 0xC0000139; with it the imports
    # match a qmake build.
    if(WIN32)
        set_property(TARGET ${target} APPEND_STRING PROPERTY LINK_FLAGS " -static")
    endif()

    # QtCore calls pthread_condattr_*, which some C libraries keep outside libc.
    if(Threads_FOUND)
        target_link_libraries(${target} PRIVATE Threads::Threads)
    endif()

    # Qt 5.15 defines QShaderLanguage::staticMetaObject in both libQt5Gui.a and
    # libQt53DRender.a. GNU ld takes the first; lld (Clang everywhere here but
    # Apple) rejects the duplicate, so it is allowed there.
    if(NOT APPLE AND CMAKE_CXX_COMPILER_ID MATCHES "Clang")
        set_property(TARGET ${target} APPEND_STRING PROPERTY
                     LINK_FLAGS " -Wl,--allow-multiple-definition")
    endif()

    # As qmake built them: -Os (Qt is built -optimize-size) and a stripped link;
    # CMake's -O3 unstripped made gl-heavy-gallery 76 MB instead of 33.
    if(CMAKE_BUILD_TYPE STREQUAL "Release" AND NOT MSVC)
        set_property(TARGET ${target} APPEND_STRING PROPERTY LINK_FLAGS " -Wl,-s")
    endif()
endfunction()
