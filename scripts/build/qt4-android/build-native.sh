#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

scripts=/repo/scripts/build/qt4-android
patches=/repo/patches/android/donut
tests=/repo/tests/android-donut
llvm=/work/llvm-project-21.1.8.src
sysroot=/work/sysroot-api4
runtime=/work/runtime-build
target=armv5te-linux-androideabi4

cd /work
sha256sum -c <<'EOF'
e2882295097e47fe089f8ac741a95fef47e0a73a3f3cdf21b56990638f626ea0  /inputs/qt-everywhere-opensource-src-4.8.7.tar.gz
4633a23617fa31a3ea51242586ea7fb1da7140e426bd62fc164261fe036aa142  /inputs/llvm-project-21.1.8.src.tar.xz
7049f4b170edc3415d48ff4fb36fe9b110ee7122f65051a727edb75600ad0057  /inputs/aosp-ndk-r7-api4-arm.tar.gz
EOF
tar -xf /inputs/llvm-project-21.1.8.src.tar.xz \
    "${llvm##*/}"/{cmake,compiler-rt,libc,libcxx,libcxxabi,libunwind,llvm,runtimes,third-party}
mkdir "$sysroot"
tar -xzf /inputs/aosp-ndk-r7-api4-arm.tar.gz -C "$sysroot"
patch -d "$llvm" -p1 --fuzz=0 < "$patches/llvm.patch"
patch -d "$sysroot" -p1 --fuzz=0 < "$patches/bionic.patch"

flags='-march=armv5te -mfloat-abi=soft -fPIC -femulated-tls -ffunction-sections -fdata-sections -D__STDC_LIMIT_MACROS -D__STDC_CONSTANT_MACROS -DSIZE_MAX=__SIZE_MAX__'
cmake_options=(
    -G Ninja -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=arm -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_C_COMPILER=clang-21 -DCMAKE_CXX_COMPILER=clang++-21 -DCMAKE_ASM_COMPILER=clang-21
    "-DCMAKE_SYSROOT=$sysroot" "-DCMAKE_C_COMPILER_TARGET=$target"
    "-DCMAKE_CXX_COMPILER_TARGET=$target" "-DCMAKE_ASM_COMPILER_TARGET=$target"
    "-DCMAKE_CXX_FLAGS=$flags -D_LIBCPP_PROVIDES_DEFAULT_RUNE_TABLE" "-DCMAKE_ASM_FLAGS=$flags"
    -DCMAKE_AR=/usr/bin/llvm-ar-21 -DCMAKE_RANLIB=/usr/bin/llvm-ranlib-21
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY -DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=lld
    '-DCMAKE_SHARED_LINKER_FLAGS=-fuse-ld=lld -Wl,--hash-style=sysv'
    "-DLLVM_DEFAULT_TARGET_TRIPLE=$target" -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF -DLLVM_INCLUDE_TESTS=OFF
)
cmake -S "$llvm/runtimes" -B "$runtime" "${cmake_options[@]}" "-DCMAKE_C_FLAGS=$flags" \
    '-DLLVM_ENABLE_RUNTIMES=libunwind;libcxxabi;libcxx' \
    -DLIBUNWIND_ENABLE_SHARED=OFF -DLIBUNWIND_ENABLE_STATIC=ON -DLIBUNWIND_INCLUDE_TESTS=OFF \
    -DLIBCXXABI_ENABLE_SHARED=OFF -DLIBCXXABI_ENABLE_STATIC=ON -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
    -DLIBCXXABI_INCLUDE_TESTS=OFF -DLIBCXXABI_HAS_CXA_THREAD_ATEXIT_IMPL=OFF \
    -DLIBCXX_ENABLE_SHARED=OFF -DLIBCXX_ENABLE_STATIC=ON -DLIBCXX_ENABLE_WIDE_CHARACTERS=OFF \
    -DLIBCXX_CXX_ABI=libcxxabi -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON \
    -DLIBCXX_INCLUDE_TESTS=OFF -DLIBCXX_INCLUDE_BENCHMARKS=OFF -DLIBCXX_INSTALL_MODULES=OFF
cmake --build "$runtime" --parallel 2
cmake -S "$llvm/runtimes" -B /work/builtins-build "${cmake_options[@]}" \
    "-DCMAKE_C_FLAGS=$flags -D__ANDROID_API_FUTURE__=10000" \
    -DLLVM_ENABLE_RUNTIMES=compiler-rt -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
    -DCOMPILER_RT_LIBATOMIC_USE_PTHREAD=ON -DCOMPILER_RT_INCLUDE_TESTS=OFF \
    -DCOMPILER_RT_BUILD_SANITIZERS=OFF -DCOMPILER_RT_BUILD_XRAY=OFF \
    -DCOMPILER_RT_BUILD_LIBFUZZER=OFF -DCOMPILER_RT_BUILD_PROFILE=OFF \
    -DCOMPILER_RT_BUILD_CTX_PROFILE=OFF -DCOMPILER_RT_BUILD_ORC=OFF \
    -DCOMPILER_RT_BUILD_MEMPROF=OFF -DCOMPILER_RT_BUILD_GWP_ASAN=OFF -DCOMPILER_RT_BUILD_CRT=OFF
cmake --build /work/builtins-build --parallel 2

mkdir /work/apks
cd /work/apks
arch=(--target="$target" --sysroot="$sysroot" -march=armv5te -mfloat-abi=soft)
compile=(-O2 -fPIC -ffunction-sections -fdata-sections)
link=(-fuse-ld=lld -nostdlib -shared
    -Wl,--hash-style=sysv,--no-undefined,--no-dependent-libraries,--gc-sections,--exclude-libs,ALL,-soname,libdonut_probe.so)
archives=("$runtime/lib/libc++.a" "$runtime/lib/libc++abi.a" "$runtime/lib/libunwind.a"
    /work/builtins-build/compiler-rt/lib/linux/libclang_rt.builtins-arm-android.a)
platform=(-L"$sysroot/usr/lib" -llog -ldl -lm -lc)
for source in crt-donut armv5-compat tmpfile-donut; do
    clang-21 "${arch[@]}" "${compile[@]}" -fvisibility=hidden -c "$scripts/$source.c" -o "$source.o"
done

clang++-21 "${arch[@]}" "${compile[@]}" -std=c++23 "${link[@]}" "$tests/bootstrap.cpp" -o bootstrap.so
clang++-21 "${arch[@]}" "${compile[@]}" -std=c++23 -fexperimental-library -femulated-tls \
    -D__STDC_LIMIT_MACROS -D__STDC_CONSTANT_MACROS -DSIZE_MAX=__SIZE_MAX__ -D_LIBCPP_PROVIDES_DEFAULT_RUNE_TABLE \
    -nostdinc++ -isystem "$runtime/include/c++/v1" -I/repo/scripts/tests/qt6-llvm-probes \
    -c "$tests/strict-jni.cpp" -o strict-jni.o
clang++-21 "${arch[@]}" "${link[@]}" -Wl,--wrap=tmpfile \
    crt-donut.o armv5-compat.o tmpfile-donut.o strict-jni.o -Wl,--start-group \
    "$runtime/lib/libc++experimental.a" "${archives[@]}" -Wl,--end-group "${platform[@]}" -o strict.so

bash "$scripts/build-qtcore.sh" core
core=/work/qt4-donut
cxx=/work/donut-bin/donut-cxx
"$cxx" "${compile[@]}" -std=gnu++98 -I"$core/include" -I"$core/include/QtCore" \
    -c "$tests/qtcore-jni.cpp" -o qtcore-jni.o
"$cxx" "${link[@]}" crt-donut.o armv5-compat.o qtcore-jni.o -Wl,--start-group \
    "$core/lib/libQtCore.a" "${archives[@]}" -Wl,--end-group "${platform[@]}" -o core.so

bash "$scripts/build-qtcore.sh" quick
quick=/work/qt4-donut-quick
for module in folderlistmodel gestures particles; do
    make -C "$quick/src/imports/$module" -j2
done
make -C "$quick/src/plugins/imageformats/svg" -j2
"$quick/bin/rcc" -name qml_qt4 /repo/tests/quick-qml-gallery/qml_qt4.qrc -o qml-resources.cpp
includes=(-I"$quick/include" -I"$quick/include/QtCore" -I"$quick/include/QtGui" -I"$quick/include/QtDeclarative")
widget_gallery=/repo/tests/widgets-gallery
"$quick/bin/moc" -DQT_VERSION_MAJOR=4 -DQT_VERSION_MINOR=8 "${includes[@]}" "$widget_gallery/gallery.cpp" -o gallery.moc
"$cxx" "${compile[@]}" -std=gnu++14 "${includes[@]}" -DQT_VERSION_MAJOR=4 -DQT_VERSION_MINOR=8 \
    -I. -c "$widget_gallery/gallery.cpp" -o widget-gallery.o
"$cxx" "${compile[@]}" -std=gnu++98 "${includes[@]}" -c "$tests/quick-jni.cpp" -o quick-jni.o
"$cxx" "${compile[@]}" -std=gnu++98 "${includes[@]}" -c qml-resources.cpp -o qml-resources.o
"$cxx" "${link[@]}" crt-donut.o armv5-compat.o quick-jni.o qml-resources.o widget-gallery.o -Wl,--start-group \
    "$quick/plugins/platforms/libqminimal.a" \
    "$quick/imports/Qt/labs/folderlistmodel/libqmlfolderlistmodelplugin.a" \
    "$quick/imports/Qt/labs/gestures/libqmlgesturesplugin.a" \
    "$quick/imports/Qt/labs/particles/libqmlparticlesplugin.a" "$quick/plugins/imageformats/libqsvg.a" \
    "$quick/lib"/libQt{Declarative,Svg,Gui,Script,Network,Sql,Xml,Core}.a "${archives[@]}" \
    -Wl,--end-group "${platform[@]}" -o quick.so

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
    "$cxx" "${link[@]}" -Wl,--wrap=tmpfile ../crt-donut.o ../armv5-compat.o ../tmpfile-donut.o suite-jni.o \
        "${objects[@]}" -Wl,--start-group "$quick/plugins/platforms/libqminimal.a" \
        "$quick/lib"/libQt{Svg,Gui,Script,Network,Sql,Xml,Core}.a "${archives[@]}" \
        -Wl,--end-group "${platform[@]}" -o "../$profile.so"
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
cp "$core/lib/libQtCore.a" /out/
