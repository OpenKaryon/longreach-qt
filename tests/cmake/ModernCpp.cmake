# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
option(SMOKE_REQUIRE_CXX23 "Fail when any required C++23 behavior is unavailable" OFF)

function(smoke_configure_modern_cpp target)
    if(SMOKE_REQUIRE_CXX23)
        get_target_property(standard ${target} CXX_STANDARD)
        if(NOT standard OR standard LESS 23)
            message(FATAL_ERROR "SMOKE_REQUIRE_CXX23 requires CMAKE_CXX_STANDARD=23 or newer")
        endif()
        target_compile_definitions(${target} PRIVATE SMOKE_REQUIRE_CXX23=1)
    endif()
    if(NOT WIN32)
        find_package(Threads REQUIRED)
        target_link_libraries(${target} PRIVATE Threads::Threads)
    endif()
endfunction()
