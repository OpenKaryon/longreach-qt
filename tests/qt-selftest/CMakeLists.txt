# qt-selftest: the non-visual battery. It needs Xvfb on Linux for its
# QPixmap/font checks. Qt 4 builds it with qt-selftest.pro, which takes every
# checks_*.cpp but checks_qtbase_misc.cpp and so gets checks_qtbase_misc_qt4.cpp.
#
# ScriptTools is deliberately not in the top-level availability check: it ships
# alongside Script in every Qt 5 SDK this kit builds, and neither exists in
# Qt 6, so Script alone decides.
smoke_add_app(qt-selftest
    MODULES
        ${SMOKE_CONSOLE_MODULES}
    SOURCES
        main.cpp
        checks_core.cpp
        checks_time.cpp
        checks_io.cpp
        checks_serial.cpp
        checks_images.cpp
        checks_gui.cpp
        checks_models.cpp
        checks_concurrency.cpp
        checks_net.cpp
        checks_sql.cpp
        checks_extra.cpp
        checks_extra2.cpp
        checks_multimedia.cpp
        checks_sensors.cpp
        checks_connectivity.cpp
        checks_serialbus.cpp
        checks_scxml.cpp
        checks_remoteobjects.cpp
        checks_script2.cpp
        checks_xmlpatterns2.cpp
        checks_misc_hw.cpp
        checks_textdoc.cpp
        checks_qtbase_misc.cpp
        checks_purchasing.cpp
        checks_opcua.cpp
        checks_grpc.cpp
        checks_wayland.cpp
        checks_wayland2.cpp
        checks_wayland_live.cpp
        checks_iot.cpp
        checks_qt6_core.cpp
        checks_dbus.cpp
        checks_platform_extras.cpp
        checks_qt6_modules.cpp
        checks_shadertools.cpp
        checks_qt6_qtbase.cpp
        checks_location2.cpp
        checks_declarative1.cpp
        checks_multimedia2.cpp
        ../common/smokecheck.h
        checks.h
)

# Four modules that are not shared by all three generations. Each is linked
# only when the SDK has it and sets a DEFINE, the same shape widgets-gallery
# uses for WinExtras: the sources stay in every build and guard themselves, so
# unavailable checks report SKIP instead of disappearing from the run.
#
# ScriptTools ships alongside Script in the Qt 4 and Qt 5 SDKs this kit builds,
# so Script alone decides for both.
smoke_have_qt_module(SMOKE_HAVE_SCRIPT Script)
if(SMOKE_HAVE_SCRIPT)
    smoke_qt_target(smoke_script_target Script)
    smoke_qt_target(smoke_scripttools_target ScriptTools)
    target_link_libraries(qt-selftest PRIVATE
        ${smoke_script_target} ${smoke_scripttools_target})
    target_compile_definitions(qt-selftest PRIVATE SMOKE_HAVE_SCRIPT)
endif()

smoke_have_qt_module(SMOKE_HAVE_XMLPATTERNS XmlPatterns)
if(SMOKE_HAVE_XMLPATTERNS)
    smoke_qt_target(smoke_xmlpatterns_target XmlPatterns)
    target_link_libraries(qt-selftest PRIVATE ${smoke_xmlpatterns_target})
    target_compile_definitions(qt-selftest PRIVATE SMOKE_HAVE_XMLPATTERNS)
endif()

smoke_have_qt_module(SMOKE_HAVE_GAMEPAD Gamepad)
if(SMOKE_HAVE_GAMEPAD)
    target_link_libraries(qt-selftest PRIVATE Qt${QT_VERSION_MAJOR}::Gamepad)
    target_compile_definitions(qt-selftest PRIVATE SMOKE_HAVE_GAMEPAD)
endif()

smoke_have_qt_module(SMOKE_HAVE_PURCHASING Purchasing)
if(SMOKE_HAVE_PURCHASING)
    target_link_libraries(qt-selftest PRIVATE Qt${QT_VERSION_MAJOR}::Purchasing)
    target_compile_definitions(qt-selftest PRIVATE SMOKE_HAVE_PURCHASING)
endif()

# NetworkAuth is deliberately absent from the LGPL-friendly SDK profile. Keep
# its named checks in the executable as SKIPs while avoiding both its headers
# and its static library in that profile.
smoke_have_qt_module(SMOKE_HAVE_NETWORKAUTH NetworkAuth)
if(SMOKE_HAVE_NETWORKAUTH)
    target_link_libraries(qt-selftest PRIVATE Qt${QT_VERSION_MAJOR}::NetworkAuth)
    target_compile_definitions(qt-selftest PRIVATE SMOKE_HAVE_NETWORKAUTH)
endif()

# QQmlWebChannel is part of QtWebChannel on Qt 5 and of a WebChannelQuick
# module of its own on Qt 6. Either way the C++ class needs no QML engine to
# construct, which is why a headless app can cover it.
smoke_have_qt_module(SMOKE_HAVE_WEBCHANNELQUICK WebChannelQuick)
if(SMOKE_HAVE_WEBCHANNELQUICK)
    target_link_libraries(qt-selftest PRIVATE Qt${QT_VERSION_MAJOR}::WebChannelQuick)
endif()
if(SMOKE_HAVE_WEBCHANNELQUICK OR QT_VERSION_MAJOR LESS 6)
    target_compile_definitions(qt-selftest PRIVATE SMOKE_HAVE_QMLWEBCHANNEL)
endif()

# QStateMachine, QEventTransition, QHistoryState and the rest of the state
# machine framework are part of QtCore on Qt 5 and a module of their own on
# Qt 6, so this is a link-only difference - the sources need no guards.
smoke_have_qt_module(SMOKE_HAVE_STATEMACHINE StateMachine)
if(SMOKE_HAVE_STATEMACHINE)
    target_link_libraries(qt-selftest PRIVATE Qt${QT_VERSION_MAJOR}::StateMachine)
endif()

# QtOpcUa exists only in Qt 6. Everything the check touches is a value type
# that needs no server, so the only thing gating it is whether the SDK has the
# module at all.
smoke_have_qt_module(SMOKE_HAVE_OPCUA OpcUa)
if(SMOKE_HAVE_OPCUA)
    target_link_libraries(qt-selftest PRIVATE Qt${QT_VERSION_MAJOR}::OpcUa)
    target_compile_definitions(qt-selftest PRIVATE SMOKE_HAVE_OPCUA)
endif()

# QtWaylandCompositor - Linux only, and only where the SDK was built with it.
# The module is a library for writing a compositor, so every class in the check
# is assembled and inspected without ever calling QWaylandCompositor::create():
# nothing binds a socket and no Wayland session is needed.
smoke_have_qt_module(SMOKE_HAVE_WAYLANDCOMPOSITOR WaylandCompositor)
if(SMOKE_HAVE_WAYLANDCOMPOSITOR)
    target_link_libraries(qt-selftest PRIVATE Qt${QT_VERSION_MAJOR}::WaylandCompositor)
    target_compile_definitions(qt-selftest PRIVATE SMOKE_HAVE_WAYLANDCOMPOSITOR)
endif()

# The live Wayland check starts a compositor and a QPA client as two child
# processes. Both halves are optional together: a compositor-only SDK keeps the
# existing value/object checks above and reports the live protocol check as a
# named SKIP.
smoke_have_qt_module(SMOKE_HAVE_WAYLANDCLIENT WaylandClient)
if(SMOKE_HAVE_WAYLANDCLIENT)
    target_link_libraries(qt-selftest PRIVATE Qt${QT_VERSION_MAJOR}::WaylandClient)
    target_compile_definitions(qt-selftest PRIVATE SMOKE_HAVE_WAYLANDCLIENT)
    # Static Qt does not discover QPA plugins from a directory at runtime.
    # Import the Wayland platform plugin into the executable that launches the
    # real client half of the compositor test.
    find_package(Qt${QT_VERSION_MAJOR} QUIET COMPONENTS QWaylandIntegrationPlugin)
    if(TARGET Qt${QT_VERSION_MAJOR}::QWaylandIntegrationPlugin)
        target_link_libraries(qt-selftest PRIVATE
            Qt${QT_VERSION_MAJOR}::QWaylandIntegrationPlugin)
    endif()
endif()

# QtGrpc and QtProtobuf, Qt 6 only. The channel is lazy and the serializers are
# self-contained, so nothing here needs a server - availability of the module is
# the only gate. GrpcQuick is asked for separately: it is the QML half and an
# SDK can carry the C++ module without it.
smoke_have_qt_module(SMOKE_HAVE_GRPC Grpc)
if(SMOKE_HAVE_GRPC)
    target_link_libraries(qt-selftest PRIVATE Qt${QT_VERSION_MAJOR}::Grpc Qt${QT_VERSION_MAJOR}::Protobuf)
    target_compile_definitions(qt-selftest PRIVATE SMOKE_HAVE_GRPC)
    smoke_have_qt_module(SMOKE_HAVE_GRPCQUICK GrpcQuick)
    if(SMOKE_HAVE_GRPCQUICK)
        target_link_libraries(qt-selftest PRIVATE Qt${QT_VERSION_MAJOR}::GrpcQuick)
        target_compile_definitions(qt-selftest PRIVATE SMOKE_HAVE_GRPCQUICK)
    endif()
endif()

# Three more Qt 6-only modules. Same shape as OpcUa above: value types and
# unconnected clients, so availability of the module is the only gate.
foreach(iot_module Mqtt Coap HttpServer)
    string(TOUPPER "${iot_module}" iot_upper)
    smoke_have_qt_module(SMOKE_HAVE_${iot_upper} ${iot_module})
    if(SMOKE_HAVE_${iot_upper})
        target_link_libraries(qt-selftest PRIVATE Qt${QT_VERSION_MAJOR}::${iot_module})
        target_compile_definitions(qt-selftest PRIVATE SMOKE_HAVE_${iot_upper})
    endif()
endforeach()

# QtCore5Compat holds the Qt 5 classes Qt 6 kept rather than dropped - the SAX
# readers, QRegExp, QTextCodec, QLinkedList. This kit builds it into every
# Qt 6 SDK, so it belongs under test; on Qt 5 those classes are in QtCore and
# the module does not exist, which is what the guard reads.
smoke_have_qt_module(SMOKE_HAVE_CORE5COMPAT Core5Compat)
if(SMOKE_HAVE_CORE5COMPAT)
    target_link_libraries(qt-selftest PRIVATE Qt${QT_VERSION_MAJOR}::Core5Compat)
    target_compile_definitions(qt-selftest PRIVATE SMOKE_HAVE_CORE5COMPAT)
endif()

# QShaderBaker is a Qt 6 tool module and is optional in a custom SDK. Keep the
# source in every build so an SDK without it reports a named SKIP.
smoke_have_qt_module(SMOKE_HAVE_SHADERTOOLS ShaderTools)
if(SMOKE_HAVE_SHADERTOOLS)
    target_link_libraries(qt-selftest PRIVATE Qt${QT_VERSION_MAJOR}::ShaderTools)
    if(TARGET Qt6::ShaderToolsPrivate)
        target_link_libraries(qt-selftest PRIVATE Qt6::ShaderToolsPrivate)
    endif()
    target_compile_definitions(qt-selftest PRIVATE SMOKE_HAVE_SHADERTOOLS)
endif()

# QtDBus is built into the Linux and macOS SDKs and not into the Windows ones -
# there is no D-Bus on Windows to talk to. Keying off the module rather than off
# the platform means this also covers a Qt 6 SDK once one is built with it.
smoke_have_qt_module(SMOKE_HAVE_DBUS DBus)
if(SMOKE_HAVE_DBUS)
    smoke_qt_target(smoke_dbus_target DBus)
    target_link_libraries(qt-selftest PRIVATE ${smoke_dbus_target})
    target_compile_definitions(qt-selftest PRIVATE SMOKE_HAVE_DBUS)
endif()

# QtX11Extras exists only in the Linux SDKs, and only in Qt 5 - Qt 6 folded
# what survived of it into QGuiApplication's native interfaces.
smoke_have_qt_module(SMOKE_HAVE_X11EXTRAS X11Extras)
if(SMOKE_HAVE_X11EXTRAS)
    target_link_libraries(qt-selftest PRIVATE Qt${QT_VERSION_MAJOR}::X11Extras)
    target_compile_definitions(qt-selftest PRIVATE SMOKE_HAVE_X11EXTRAS)
endif()

# QtSpatialAudio is a Qt 6 module of its own, built alongside QtMultimedia. The
# engine is constructed but never started, so no output device is opened.
smoke_have_qt_module(SMOKE_HAVE_SPATIALAUDIO SpatialAudio)
if(SMOKE_HAVE_SPATIALAUDIO)
    target_link_libraries(qt-selftest PRIVATE Qt${QT_VERSION_MAJOR}::SpatialAudio)
    target_compile_definitions(qt-selftest PRIVATE SMOKE_HAVE_SPATIALAUDIO)
endif()

# QtVirtualKeyboard, and QtOpenGL for the version-functions factory. Both are
# Qt 6-side additions to what this app can reach.
#
# The keyboard is the one place where the module is not enough to decide, and
# asking it alone was a build break on Qt 5: Qt 5 ships a QtVirtualKeyboard too,
# but its classes are spelled differently - QVirtualKeyboardInputContext and its
# relatives are the Qt 6 names - so a Qt 5 SDK that has the module still cannot
# compile the includes. The version is what decides here, and is asked outright.
if(NOT QT_VERSION_MAJOR LESS 6)
    smoke_have_qt_module(SMOKE_HAVE_VIRTUALKEYBOARD VirtualKeyboard)
    if(SMOKE_HAVE_VIRTUALKEYBOARD)
        target_link_libraries(qt-selftest PRIVATE Qt${QT_VERSION_MAJOR}::VirtualKeyboard)
        target_compile_definitions(qt-selftest PRIVATE SMOKE_HAVE_VIRTUALKEYBOARD)
    endif()
endif()

smoke_have_qt_module(SMOKE_CONSOLE_HAVE_OPENGL OpenGL)
if(SMOKE_CONSOLE_HAVE_OPENGL)
    smoke_qt_target(smoke_opengl_target OpenGL)
    target_link_libraries(qt-selftest PRIVATE ${smoke_opengl_target})
    target_compile_definitions(qt-selftest PRIVATE SMOKE_CONSOLE_HAVE_OPENGL)
endif()
