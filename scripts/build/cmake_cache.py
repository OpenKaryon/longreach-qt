# SPDX-License-Identifier: GPL-3.0-or-later
"""Read declared CMake BOOL options without assuming their spelling."""


def cmake_cache_bool(build, name):
    prefix = name + ":BOOL="
    for line in (build / "CMakeCache.txt").read_text().splitlines():
        if line.startswith(prefix):
            value = line[len(prefix):].upper()
            return (value not in {"", "0", "OFF", "NO", "FALSE", "N", "IGNORE", "NOTFOUND"}
                    and not value.endswith("-NOTFOUND"))
    return False
