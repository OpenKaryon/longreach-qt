// SPDX-License-Identifier: GPL-3.0-or-later

#include <jni.h>
#include <android/log.h>
#include <cstdio>
#include <cstdlib>
#include <locale>
#include <sstream>
#include <unistd.h>

#define main longreachProbeMain
#include "main.cpp"
#undef main

static bool checkClassicLocale()
{
    const std::locale classic("C");
    const auto &punctuation = std::use_facet<std::numpunct<char>>(classic);
    std::istringstream input("12.5");
    input.imbue(classic);
    double value = 0.0;
    input >> value;
    return punctuation.decimal_point() == '.' && punctuation.grouping().empty() &&
           !input.fail() && value == 12.5;
}

extern "C" JNIEXPORT jint JNICALL
Java_org_longreachqt_donut_ProbeActivity_runProbe(JNIEnv *env, jobject, jstring directory)
{
    const char *files = env->GetStringUTFChars(directory, nullptr);
    if (!files)
        return 2;
    const bool canWrite = chdir(files) == 0 && setenv("TMPDIR", files, 1) == 0;
    env->ReleaseStringUTFChars(directory, files);
    if (!canWrite || !std::freopen("strict-cxx23.log", "w", stdout))
        return 2;

    if (!checkClassicLocale()) {
        __android_log_write(ANDROID_LOG_ERROR, "LongreachDonut", "Classic locale check failed");
        return 2;
    }
    __android_log_write(ANDROID_LOG_INFO, "LongreachDonut", "Classic locale check passed");

    const int result = longreachProbeMain();
    std::fflush(stdout);
    std::FILE *log = std::fopen("strict-cxx23.log", "r");
    if (!log)
        return 2;
    char line[512];
    while (std::fgets(line, sizeof(line), log))
        __android_log_write(ANDROID_LOG_INFO, "LongreachDonut", line);
    std::fclose(log);
    return result;
}
