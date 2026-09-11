# smoke-runner: drives every app above with --selftest and writes a report.
#
# QT = core only, and no GUI: it just spawns the others as child processes, so
# it is the one app that needs no display and no platform plugin.
smoke_add_app(smoke-runner
    MODULES Core
    SOURCES main.cpp
)
