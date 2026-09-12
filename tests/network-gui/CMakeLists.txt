# network-gui: local TCP/UDP/WebSocket/HTTP manual smoke lab.
# WebSockets is optional rather than required: QtWebSockets is Qt 5 and later,
# and the TCP, UDP, HTTP and SSL halves of this app work identically on all
# three versions. Requiring it would have kept the SSL checks - which are what
# verify the Qt 4 OpenSSL port - out of every Qt 4 build (network-gui.pro, with
# qt4_ui.cpp).

smoke_add_app(network-gui
    MODULES Core Gui Widgets Network
    OPTIONAL_MODULES WebSockets HttpServer
    SOURCES main.cpp ../common/smokecheck.h
)

smoke_have_qt_module(SMOKE_HAVE_HTTPSERVER HttpServer)
if(SMOKE_HAVE_HTTPSERVER)
    target_compile_definitions(network-gui PRIVATE SMOKE_HAVE_HTTPSERVER)
endif()

smoke_have_qt_module(SMOKE_HAVE_WEBSOCKETS WebSockets)
if(SMOKE_HAVE_WEBSOCKETS)
    target_compile_definitions(network-gui PRIVATE SMOKE_HAVE_WEBSOCKETS)
endif()
