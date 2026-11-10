# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
cmake_minimum_required(VERSION 3.20)
project(ModernCppProbe LANGUAGES CXX)
find_package(Qt6 REQUIRED COMPONENTS Core)
get_filename_component(REPO_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
add_executable(modern-only
    "${REPO_ROOT}/tests/qt-selftest/checks_modern_cpp.cpp"
    modern-only.cpp
)
target_include_directories(modern-only PRIVATE "${REPO_ROOT}/tests/common")
set_target_properties(modern-only PROPERTIES
    CXX_STANDARD ${CMAKE_CXX_STANDARD}
    CXX_STANDARD_REQUIRED ON
)
target_link_libraries(modern-only PRIVATE Qt6::Core)
include("${REPO_ROOT}/tests/cmake/ModernCpp.cmake")
smoke_configure_modern_cpp(modern-only)
