# quick-qml-gallery: QML / Qt Quick.
# The module list is longer than the old QT= line because a statically linked
# QML application has to link every module its QML imports, not just the ones
# its C++ names. qmake picked these up transitively through .prl files; CMake
# does not, and the failure is a wall of undefined references from inside the
# QML plugins rather than anything pointing at the import that caused it.
#
# QmlWorkerScript, QmlModels, QuickTemplates2, QuickParticles and QuickShapes
# are here for exactly that reason - they back `import QtQuick`,
# `Qt.labs.qmlmodels`, `QtQuick.Controls`, `QtQuick.Particles` and
# `QtQuick.Shapes` in tests/quick-qml-gallery/qml/.

# Qt 4's QtDeclarative is QtQuick 1; quick-qml-gallery.pro builds main.cpp's
# QDeclarativeView branch with checks_declarative1_qt4.cpp and qml_qt4/main.qml,
# keeping the same fourteen navigation sections.

# QtGraphicalEffects was removed in Qt 6; the same types live in
# Qt5Compat.GraphicalEffects there, with an unversioned import. QML has no
# conditional import and no #if, so the one line that differs is configured in
# rather than the 200-line file being duplicated.
#
# The generated file gets its own .qrc because rcc resolves paths relative to
# the .qrc, and the other fourteen QML files stay in the source tree. The alias
# puts it back at the resource path main.qml expects.
if(QT_VERSION_MAJOR LESS 6)
    set(SMOKE_GRAPHICALEFFECTS_IMPORT "import QtGraphicalEffects 1.15")
else()
    set(SMOKE_GRAPHICALEFFECTS_IMPORT "import Qt5Compat.GraphicalEffects")
endif()
configure_file(qml/GraphicalEffectsTab.qml.in
               "${CMAKE_CURRENT_BINARY_DIR}/GraphicalEffectsTab.qml" @ONLY)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/effects.qrc"
"<RCC>
    <qresource prefix=\"/\">
        <file alias=\"qml/GraphicalEffectsTab.qml\">GraphicalEffectsTab.qml</file>
    </qresource>
</RCC>
")

set(smoke_quick_qml_extra_args
    IMPORT_QML_PLUGINS
    QML_SCAN_PATHS
    # PATH_TO_SCAN replaces the default scan root rather than adding to
    # it, so the source directory has to be named again alongside the
    # build one - where the configured GraphicalEffectsTab.qml lands and
    # where the scanner would otherwise never see its import.
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_BINARY_DIR}
    MODULES
        Core Gui Widgets Qml Quick QuickWidgets QuickControls2
        QmlWorkerScript QmlModels QuickTemplates2
    OPTIONAL_MODULES
        # Public packages in Qt 5, internal in Qt 6. They are here to satisfy
        # the static link of the QML plugins the scanner pulls in; where Qt
        # does not expose them, it also does not need them named.
        QuickParticles QuickShapes
    SOURCES
        main.cpp
        selftest.cpp
        checks_quickitems.cpp
        checks_scenegraph.cpp
        checks_native_textures.cpp
        qml.qrc
        ${CMAKE_CURRENT_BINARY_DIR}/effects.qrc
        ../common/smokecheck.h
)
if(QT_VERSION_MAJOR EQUAL 5)
    list(APPEND smoke_quick_qml_extra_args checks_scenegraph_qt5.cpp)
endif()
smoke_add_app(quick-qml-gallery ${smoke_quick_qml_extra_args})

# Quick3D needs Qt to have been configured with OpenGL, so it is not present in
# every SDK this kit produces. Key off the module rather than the platform and
# let the self-test report a SKIP when it is missing.
smoke_have_qt_module(SMOKE_HAVE_QUICK3D Quick3D)
if(SMOKE_HAVE_QUICK3D)
    target_sources(quick-qml-gallery PRIVATE checks_quick3d.cpp)
    target_link_libraries(quick-qml-gallery PRIVATE Qt${QT_VERSION_MAJOR}::Quick3D)
    target_compile_definitions(quick-qml-gallery PRIVATE SMOKE_HAVE_QUICK3D)
    # The render-extension check builds its tiny View3D from an in-memory QML
    # string, which qmlimportscanner cannot see. Static builds therefore need
    # the module plugin named explicitly.
    if(TARGET Qt${QT_VERSION_MAJOR}::qquick3dplugin)
        target_link_libraries(quick-qml-gallery PRIVATE
            Qt${QT_VERSION_MAJOR}::qquick3dplugin)
    endif()

    # Qt 6.7+'s render-extension backend is a limited-compatibility public API
    # in Quick3DRuntimeRender. The Private target supplies the <ssg/...>
    # forwarding headers used by Qt's own extension examples and autotests.
    if(QT_VERSION VERSION_GREATER_EQUAL 6.7 AND TARGET Qt6::Quick3DRuntimeRenderPrivate)
        target_link_libraries(quick-qml-gallery PRIVATE
            Qt6::Quick3DRuntimeRenderPrivate Qt6::Quick3DPrivate)
        target_compile_definitions(quick-qml-gallery PRIVATE SMOKE_HAVE_QUICK3D_EXTENSIONS)
    endif()
endif()

# The Quick half of QtWaylandCompositor. The file is always compiled - it
# reports a SKIP when the module is absent - but the module is only linked where
# it exists, which is the Linux targets.
smoke_have_qt_module(SMOKE_HAVE_WAYLANDCOMPOSITOR WaylandCompositor)
if(SMOKE_HAVE_WAYLANDCOMPOSITOR)
    target_link_libraries(quick-qml-gallery PRIVATE Qt${QT_VERSION_MAJOR}::WaylandCompositor)
    target_compile_definitions(quick-qml-gallery PRIVATE SMOKE_HAVE_WAYLANDCOMPOSITOR)
endif()

# Qt 5's scanner finds Qt5Compat.GraphicalEffects' Qt 5 counterpart through the
# extra scan path above; Qt 6's does not link it even when it does, so on Qt 6
# the plugin is named outright. Both halves are needed - the effect types are
# themselves QML files importing Qt5Compat.GraphicalEffects.private, so linking
# only the front one gets the module loaded and then fails a level deeper.
if(NOT QT_VERSION_MAJOR LESS 6)
    foreach(effects_plugin qtgraphicaleffectsplugin qtgraphicaleffectsprivate)
        find_package(Qt6${effects_plugin} QUIET)
        if(TARGET Qt6::${effects_plugin})
            target_link_libraries(quick-qml-gallery PRIVATE Qt6::${effects_plugin})
        else()
            message(WARNING "qt-smoke: ${effects_plugin} is missing; "
                            "quick-qml-gallery's effects tab will fail to load")
        endif()
    endforeach()
endif()
