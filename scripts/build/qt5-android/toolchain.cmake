# SPDX-License-Identifier: GPL-3.0-or-later

set(CMAKE_SYSTEM_NAME Android)
# CMake reserves 1 for externally managed Android toolchains. The compiler
# wrapper selects API 10; this disables Google's NDK-specific autodetection.
set(CMAKE_SYSTEM_VERSION 1)
set(CMAKE_SYSTEM_PROCESSOR armv7-a)
set(CMAKE_ANDROID_ARCH_ABI armeabi-v7a)
set(CMAKE_ANDROID_API 10)
set(ANDROID_PLATFORM android-10)
set(ANDROID_ABI armeabi-v7a)
set(ANDROID_NDK /opt/longreach-android/ndk)
set(ANDROID_HOST_TAG linux-x86_64)
set(ANDROID_TOOLCHAIN_ROOT "${ANDROID_NDK}/toolchains/llvm/prebuilt/${ANDROID_HOST_TAG}")
if(DEFINED ENV{ANDROID_SDK_ROOT})
    set(ANDROID_SDK "$ENV{ANDROID_SDK_ROOT}" CACHE PATH "Android SDK root")
else()
    set(ANDROID_SDK /work/android-sdk CACHE PATH "Android SDK root")
endif()

set(ANDROID_MIN_SDK_VERSION "10" CACHE STRING "Android minimum SDK version")
set(ANDROID_TARGET_SDK_VERSION "10" CACHE STRING "Android target SDK version")
set(ANDROID_SDK_BUILD_TOOLS_REVISION "36.0.0" CACHE STRING "Android Build Tools version")

set(CMAKE_C_COMPILER /opt/longreach-android/bin/cc)
set(CMAKE_CXX_COMPILER /opt/longreach-android/bin/cxx)
set(CMAKE_AR /usr/bin/llvm-ar-21)
set(CMAKE_RANLIB /usr/bin/llvm-ranlib-21)
set(CMAKE_STRIP /usr/bin/llvm-strip-21)
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
# Bionic provides pthreads in libc. Prefer Clang's supported -pthread flag:
# archive-only feature probes cannot detect a nonexistent libpthreads.
set(THREADS_PREFER_PTHREAD_FLAG TRUE)

set(CMAKE_FIND_ROOT_PATH /opt/longreach-android/sysroot
    /opt/qt5-android-armeabi-v7a-llvm)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
list(APPEND CMAKE_PREFIX_PATH /opt/qt5-android-armeabi-v7a-llvm)
