#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
# Compile all eight API4 JNI diagnostics exclusively against the installed SDK.
set -euo pipefail
quick=/opt/qt4-android-armeabi-llvm
runtime=/opt/longreach-android-api4
tests=/repo/tests/android-donut
cxx="$runtime/bin/cxx"
python3 "$quick/libexec/api4-sdk/api4-sdk.py" verify
test ! -e /work/qt4-donut-quick
mkdir /work/installed-clients
cd /work/installed-clients
compile=(-O2 -fPIC -ffunction-sections -fdata-sections -DQT_NO_SHAREDMEMORY -DQT_NO_SYSTEMSEMAPHORE)
link=(-shared -Wl,--gc-sections,-soname,libdonut_probe.so)

# Bootstrap intentionally requires no C++ runtime or compatibility startup.
"$cxx" "${compile[@]}" -std=c++23 "${link[@]}" -nostdlib "$tests/bootstrap.cpp" -o bootstrap.so
"$cxx" "${compile[@]}" -std=c++23 -I/repo/scripts/tests/qt6-llvm-probes \
    -c "$tests/strict-jni.cpp" -o strict-jni.o
"$cxx" "${link[@]}" strict-jni.o -o strict.so
# Exercise the exported qmake and target mkspec, not only their query output.
mkdir core-client
cat >core-client/core.pro <<'EOF'
TEMPLATE = lib
TARGET = core
CONFIG += dll release
CONFIG -= staticlib app_bundle debug debug_and_release
QT = core
SOURCES = /repo/tests/android-donut/qtcore-jni.cpp
QMAKE_CXXFLAGS += -std=gnu++98 -ffunction-sections -fdata-sections
QMAKE_LFLAGS_SONAME =
QMAKE_LFLAGS += -Wl,--gc-sections,-soname,libdonut_probe.so
EOF
(
    cd core-client
    "$quick/bin/qmake" -spec "$quick/mkspecs/android-longreach-clang" core.pro
    if grep -E '/work/(qt4-donut-quick|qtquick-donut-sdk|donut-bin|runtime-build|sysroot-api4)' Makefile; then
        echo 'Installed qmake client retained a producer build-tree input' >&2
        exit 1
    fi
    make -j2
    cp libcore.so ../core.so
    cp core.pro /out/core-qmake.pro
    cp Makefile /out/core-qmake-Makefile.txt
)

"$quick/bin/rcc" -name qml_qt4 /repo/tests/quick-qml-gallery/qml_qt4.qrc -o qml-resources.cpp
includes=(-I"$quick/include" -I"$quick/include/QtCore" -I"$quick/include/QtGui" -I"$quick/include/QtDeclarative")
widget_gallery=/repo/tests/widgets-gallery
"$quick/bin/moc" -DQT_VERSION_MAJOR=4 -DQT_VERSION_MINOR=8 "${includes[@]}" "$widget_gallery/gallery.cpp" -o gallery.moc
"$cxx" "${compile[@]}" -std=gnu++14 "${includes[@]}" -DQT_VERSION_MAJOR=4 -DQT_VERSION_MINOR=8 \
    -I. -c "$widget_gallery/gallery.cpp" -o widget-gallery.o
"$cxx" "${compile[@]}" -std=gnu++98 "${includes[@]}" -c "$tests/quick-jni.cpp" -o quick-jni.o
"$cxx" "${compile[@]}" -std=gnu++98 "${includes[@]}" -c qml-resources.cpp -o qml-resources.o
"$cxx" "${link[@]}" quick-jni.o qml-resources.o widget-gallery.o -Wl,--start-group \
    "$quick/plugins/platforms/libqminimal.a" \
    "$quick/imports/Qt/labs/folderlistmodel/libqmlfolderlistmodelplugin.a" \
    "$quick/imports/Qt/labs/gestures/libqmlgesturesplugin.a" \
    "$quick/imports/Qt/labs/particles/libqmlparticlesplugin.a" "$quick/plugins/imageformats/libqsvg.a" \
    "$quick/lib"/libQt{Declarative,Svg,Gui,Script,Network,Sql,Xml,Core}.a \
    -Wl,--end-group -o quick.so

suite_includes=("${includes[@]}" -I"$quick/include/QtNetwork" -I"$quick/include/QtSql"
    -I"$quick/include/QtXml" -I"$quick/include/QtSvg" -I"$quick/include/QtScript")
suite_defines=(-DQT_VERSION_MAJOR=4 -DQT_VERSION_MINOR=8 -DLONGREACH_DONUT_JNI -DSMOKE_HAVE_SCRIPT)

build_suite() (
    profile=$1
    suite=$2
    option=$3
    shift 3
    mkdir -p "$profile"
    cd "$profile"
    objects=()
    for source in "$@"; do
        name=$(basename "$source" .cpp)
        if grep -Fq "#include \"$name.moc\"" "$source"; then
            "$quick/bin/moc" "${suite_defines[@]}" "${suite_includes[@]}" "$source" -o "$name.moc"
        fi
        "$cxx" "${compile[@]}" -std=gnu++14 "${suite_defines[@]}" "${suite_includes[@]}" \
            -I. -Dmain=longreachSuiteMain -c "$source" -o "$name.o"
        objects+=("$name.o")
    done
    "$cxx" "${compile[@]}" -std=gnu++14 "${includes[@]}" \
        "-DDONUT_SUITE_NAME=\"$suite\"" "-DDONUT_SUITE_OPTION=\"$option\"" -c "$tests/suite-jni.cpp" -o suite-jni.o
    "$cxx" "${link[@]}" suite-jni.o \
        "${objects[@]}" -Wl,--start-group "$quick/plugins/platforms/libqminimal.a" \
        "$quick/lib"/libQt{Svg,Gui,Script,Network,Sql,Xml,Core}.a \
        -Wl,--end-group -o "../$profile.so"
)

sources=()
for source in /repo/tests/qt-selftest/main.cpp /repo/tests/qt-selftest/checks_*.cpp; do
    case "$source" in
        */checks_qtbase_misc.cpp) ;;
        *) sources+=("$source");;
    esac
done
build_suite selftest qt-selftest --qt-checks-only "${sources[@]}"
build_suite graphics graphics-gallery --selftest /repo/tests/graphics-gallery/{main,canvas,selftest}.cpp
build_suite network network-gui --selftest /repo/tests/network-gui/{main,qt4_ui}.cpp
build_suite painting painting-lab --selftest /repo/tests/painting-lab/main.cpp

for profile in bootstrap strict core quick selftest graphics network painting; do
    llvm-readobj-21 --file-header --arch-specific --dynamic-table "$profile.so" > "/out/$profile-elf.txt"
    cp "$profile.so" /out/
done
cp "$quick/lib/libQtCore.a" /out/
python3 "$quick/libexec/api4-sdk/api4-sdk.py" verify
