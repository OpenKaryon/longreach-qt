# gl-heavy-gallery: QtCharts, DataVisualization and Qt3D. On Qt 4
# (gl-heavy-gallery.pro) the period equivalent: QtOpenGL, in main_qt4.cpp and
# qt4_opengl.cpp. The target and selftest name are the same on all three.

smoke_add_app(gl-heavy-gallery
    IMPORT_QML_PLUGINS
    MODULES
        Core Gui Widgets Charts DataVisualization
        3DCore 3DRender 3DInput 3DLogic 3DExtras 3DAnimation
        3DQuick 3DQuickScene2D Quick Qml
    OPTIONAL_MODULES
        # QOpenGLWindow lives in QtGui on Qt 5 and in a module of its own on
        # Qt 6.
        OpenGL
    SOURCES
        main.cpp
        glcaps.cpp
        charts_gallery.cpp
        charts_selftest.cpp
        datavis_gallery.cpp
        datavis_selftest.cpp
        ../common/smokecheck.h
        gl-heavy.h
        glcaps.h
)

# qt3d_scene.cpp drives fixed-function desktop GL directly (glBegin/glEnd and
# friends) for its background window. Qt 5's static QtGui carried a link
# dependency on the system GL library, so this came in for free; Qt 6 resolves
# GL through QOpenGLContext instead and links nothing, so the app has to ask
# for it itself.
if(WIN32)
    target_link_libraries(gl-heavy-gallery PRIVATE opengl32)
else()
    find_package(OpenGL)
    if(TARGET OpenGL::GL)
        target_link_libraries(gl-heavy-gallery PRIVATE OpenGL::GL)
    endif()
endif()

# QtGraphs is Qt 6's successor to QtDataVisualization, and QColorAxis is an
# axis type Qt 5's QtCharts did not have. Both are keyed off what the SDK
# contains rather than off the Qt version, so a Qt 5 SDK simply reports them
# absent.
smoke_have_qt_module(SMOKE_HAVE_GRAPHS Graphs)
if(SMOKE_HAVE_GRAPHS AND NOT QT_FEATURE_static)
    target_link_libraries(gl-heavy-gallery PRIVATE Qt${QT_VERSION_MAJOR}::Graphs)
    target_compile_definitions(gl-heavy-gallery PRIVATE SMOKE_HAVE_GRAPHS)
    # The widget wrappers are a module of their own: an SDK can carry QtGraphs
    # without QtGraphsWidgets, so it is asked for separately rather than assumed.
    smoke_have_qt_module(SMOKE_HAVE_GRAPHSWIDGETS GraphsWidgets)
    if(SMOKE_HAVE_GRAPHSWIDGETS)
        target_link_libraries(gl-heavy-gallery PRIVATE Qt${QT_VERSION_MAJOR}::GraphsWidgets)
        target_compile_definitions(gl-heavy-gallery PRIVATE SMOKE_HAVE_GRAPHSWIDGETS)
    endif()
elseif(SMOKE_HAVE_GRAPHS AND QT_FEATURE_static)
    # Qt 6.8's static Charts and Graphs archives both define global classes
    # such as QValueAxis. Separate translation units avoid the header conflict,
    # but cannot avoid duplicate linker symbols. Do not hide that with
    # --allow-multiple-definition: the chosen implementation would be
    # ambiguous. Keep the main Qt3D/Charts/DataVisualization app and report the
    # optional Graphs checks as explicit skips instead.
    target_compile_definitions(gl-heavy-gallery PRIVATE
        SMOKE_GRAPHS_STATIC_SYMBOL_COLLISION)
endif()
