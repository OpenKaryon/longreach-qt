# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
cmake_minimum_required(VERSION 3.20)
project(LongreachCpp23Probe LANGUAGES CXX)
add_executable(cxx23-probe main.cpp)
set_target_properties(cxx23-probe PROPERTIES
    CXX_STANDARD 23
    CXX_STANDARD_REQUIRED ON
    CXX_EXTENSIONS OFF
    MACOSX_BUNDLE OFF
)
target_compile_options(cxx23-probe PRIVATE -Wall -Wextra -Werror)
# The Windows runtime uses Win32 threads, without a POSIX threads library.
if(NOT WIN32)
    find_package(Threads REQUIRED)
    target_link_libraries(cxx23-probe PRIVATE Threads::Threads)
endif()
