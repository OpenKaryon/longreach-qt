// SPDX-License-Identifier: GPL-3.0-or-later

#include <android/log.h>
#include <jni.h>
#include <QtPlugin>
#include <cstdio>
#include <cstdlib>
#include <unistd.h>

Q_IMPORT_PLUGIN(minimal)

int longreachSuiteMain(int argc, char **argv);

extern "C" JNIEXPORT jint JNICALL
Java_org_longreachqt_donut_ProbeActivity_runProbe(JNIEnv *env, jobject, jstring directory)
{
    const char *files = env->GetStringUTFChars(directory, nullptr);
    if (!files)
        return 2;
    const bool ready = chdir(files) == 0
        && setenv("TMPDIR", files, 1) == 0
        && setenv("QT_QPA_PLATFORM", "minimal", 1) == 0
        && setenv("QT_QPA_FONTDIR", "/system/fonts", 1) == 0;
    env->ReleaseStringUTFChars(directory, files);
    if (!ready || !std::freopen("suite.log", "w", stdout))
        return 2;

    char program[] = DONUT_SUITE_NAME;
    char option[] = DONUT_SUITE_OPTION;
    char *arguments[] = {program, option, nullptr};
    const int result = longreachSuiteMain(2, arguments);
    std::fflush(stdout);
    return result;
}
