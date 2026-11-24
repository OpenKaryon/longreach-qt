// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

#ifdef main
#undef main
#endif

#include <android/log.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <unistd.h>

int longreachExampleMain(int argc, char **argv);

__attribute__((visibility("default"))) int main(int argc, char **argv)
{
    const char *directory = std::getenv("LONGREACH_APP_FILES");
    if (!directory || chdir(directory) != 0
            || !std::freopen("selftest.stdout", "w", stdout)
            || !std::freopen("selftest.stderr", "w", stderr)) {
        __android_log_write(ANDROID_LOG_ERROR, "LongreachExamples", "Could not open app-private reports");
        return 97;
    }

    // Preserve completed checks if a legacy backend aborts before main returns.
    std::setvbuf(stdout, nullptr, _IOLBF, 0);

    // Keep startup loader evidence even if Qt initialization aborts on an old
    // Android linker with a fixed shared-library pool.
    std::FILE *maps = std::fopen("/proc/self/maps", "r");
    std::FILE *snapshot = std::fopen("native-maps.txt", "w");
    if (maps && snapshot) {
        char line[1024];
        while (std::fgets(line, sizeof(line), maps))
            std::fputs(line, snapshot);
    }
    if (maps)
        std::fclose(maps);
    if (snapshot)
        std::fclose(snapshot);

    // Standalone teardown diagnosis only: allow debuggerd to finish before
    // Qt's Android entry point exits the process. Normal runs never wait here.
    bool crashHold = false;
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--android-crash-hold") == 0) {
            crashHold = true;
            for (int j = i; j < argc; ++j)
                argv[j] = argv[j + 1];
            --argc;
            --i;
        }
    }
    const int result = longreachExampleMain(argc, argv);
    if (crashHold) {
        __android_log_write(ANDROID_LOG_INFO, "LongreachExamples", "Diagnostic post-main hold");
        sleep(5);
    }
    std::fflush(nullptr);
    std::FILE *report = std::fopen("selftest-result.txt", "w");
    if (!report) {
        __android_log_write(ANDROID_LOG_ERROR, "LongreachExamples", "Could not save example result");
        return 98;
    }
    const bool saved = std::fprintf(report, "%d\n", result) > 0;
    const bool closed = std::fclose(report) == 0;
    if (!saved || !closed)
        return 98;

    __android_log_print(ANDROID_LOG_INFO, "LongreachExamples", "Example returned %d", result);
    return result;
}