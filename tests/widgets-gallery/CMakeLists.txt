# widgets-gallery: QtWidgets, item views, dialogs, tray, clipboard, styles.
#
# Three check files are Qt 5 and later only, and are left out of the Qt 4 build
# rather than guarded line by line. Each for a reason worth stating, because "it
# did not compile" would hide which of them is a real gap and which is not.
#
# The extended visual gallery is NOT among them: gallery.cpp builds on all three versions.
# What kept it out at first was idiom rather than API - twenty-two
# pointer-to-member connect() calls and lambdas passed as slots, neither of
# which Qt 4 has. Of the 97 Qt classes it includes, Qt 4 is missing exactly
# three (QGuiApplication, QKeySequenceEdit, QOperatingSystemVersion), so all
# fifteen tabs are there on Qt 4 too, when the extended SDK modules are present.
#
#   checks_multimediawidgets.cpp  every class in it is QtMultimediaWidgets,
#                                 which Qt 4 folded into QtMultimedia and which
#                                 has no counterpart there. A genuine gap.
#   checks_qtbase_tail2.cpp       958 lines around eighteen "Qt 5 or Qt 6?"
#                                 branches. Qt 4 is a third answer to a question
#                                 written as a binary one, so it was rewritten
#                                 rather than guarded: checks_qtbase_tail2_qt4.cpp
#                                 below carries the same check names over the 44
#                                 of its classes that 4.8.7 has. No longer a gap.
#   checks_accessibility_models.cpp
#                                 implements QAccessibleTextInterface and its
#                                 siblings. Qt 5 redesigned QAccessibleInterface
#                                 wholesale, so on Qt 4 not one of the forty
#                                 overrides overrides anything. Another rewrite,
#                                 not a guard. A gap.
# The three real gaps report a SKIP from main.cpp instead of vanishing, so a
# Qt 4 run says what it did not cover. Qt 4 builds the gallery with
# widgets-gallery.pro, which adds the Qt 4-only sweep (checks_qt3support.cpp,
# checks_qtbase_qt4.cpp, checks_platform4.cpp, checks_qtbase_tail2_qt4.cpp,
# checks_accessibility_qt4.cpp).
set(smoke_widgets_sources
    main.cpp
    ../common/smokecheck.h
    gallery.h
)
set(smoke_widgets_modules Core Gui GuiPrivate Widgets PrintSupport Multimedia Test)
list(APPEND smoke_widgets_sources gallery.cpp
    checks_multimediawidgets.cpp checks_qtbase_tail2.cpp
    checks_accessibility_models.cpp)
list(APPEND smoke_widgets_modules MultimediaWidgets)

smoke_add_app(widgets-gallery
    MODULES
        ${smoke_widgets_modules}
    OPTIONAL_MODULES
        # Both are part of another module on Qt 5 and modules of their own on
        # Qt 6: QStateMachine and its event transitions were in QtCore,
        # QOpenGLWidget was in QtWidgets.
        StateMachine OpenGLWidgets
    SOURCES
        ${smoke_widgets_sources}
)

# Optional modules, keyed off what the SDK actually contains rather than off the
# target platform. Each sets a DEFINE so the matching self-test reports a SKIP
# instead of silently vanishing - the suite guards with a fallback rather than
# cutting code out, the same principle the XP patches follow.
#
# WinExtras is a Windows-only module, so this doubles as the Windows check. Qt
# has no configuration macro for it, hence the DEFINE.
smoke_have_qt_module(SMOKE_HAVE_WINEXTRAS WinExtras)
if(SMOKE_HAVE_WINEXTRAS)
    target_sources(widgets-gallery PRIVATE checks_winextras.cpp)
    target_link_libraries(widgets-gallery PRIVATE Qt${QT_VERSION_MAJOR}::WinExtras)
    target_compile_definitions(widgets-gallery PRIVATE SMOKE_HAVE_WINEXTRAS)
endif()

# Only linked when present; the code guards itself with Qt's own
# QT_CONFIG(opengl), so no DEFINE is needed here.
#
smoke_have_qt_module(SMOKE_HAVE_OPENGL OpenGL)
if(SMOKE_HAVE_OPENGL)
    smoke_qt_target(smoke_opengl_target OpenGL)
    target_link_libraries(widgets-gallery PRIVATE ${smoke_opengl_target})
endif()

# QtMacExtras exists only in the macOS SDKs, and only in Qt 5. Keyed off the
# module rather than off Q_OS_MACOS, for the same reason WinExtras above is:
# the platform being right does not mean the module is there.
smoke_have_qt_module(SMOKE_HAVE_MACEXTRAS MacExtras)
if(SMOKE_HAVE_MACEXTRAS)
    target_link_libraries(widgets-gallery PRIVATE Qt${QT_VERSION_MAJOR}::MacExtras)
    target_compile_definitions(widgets-gallery PRIVATE SMOKE_HAVE_MACEXTRAS)
endif()
