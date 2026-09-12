# graphics-gallery: QPainter, image display, shaped window, animations.
smoke_add_app(graphics-gallery
    MODULES Core Gui Widgets Svg
    OPTIONAL_MODULES
        # QSvgWidget lives in QtSvg on Qt 5 and in QtSvgWidgets on Qt 6;
        # QStateMachine is in QtCore on Qt 5 and QtStateMachine on Qt 6.
        SvgWidgets StateMachine
    SOURCES
        main.cpp
        canvas.cpp
        selftest.cpp
        ../common/smokecheck.h
        graphics.h
)
