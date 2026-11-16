// SPDX-License-Identifier: GPL-3.0-or-later

#include <android/log.h>
#include <jni.h>
#include <QtCore/QByteArray>
#include <QtCore/QCoreApplication>
#include <QtCore/QFile>
#include <QtCore/QString>
#include <QtCore/QTimer>

extern "C" JNIEXPORT jint JNICALL
Java_org_longreachqt_donut_ProbeActivity_runProbe(JNIEnv *env, jobject, jstring directory)
{
    const char *directoryBytes = env->GetStringUTFChars(directory, 0);
    if (!directoryBytes)
        return 2;
    const QString path = QString::fromUtf8(directoryBytes)
                       + QString::fromUtf8("/qtcore-\xc3\xa9_\xe6\x97\xa5.txt");
    env->ReleaseStringUTFChars(directory, directoryBytes);

    int argc = 1;
    char appName[] = "qtcore-donut";
    char *argv[] = {appName, 0};
    QCoreApplication application(argc, argv);
    const QString text = QString::fromUtf8("Longreach \xc3\xa9_\xe6\x97\xa5");
    const QByteArray bytes = text.toUtf8();
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate) || file.write(bytes) != bytes.size())
        return 3;
    file.close();
    if (!file.open(QIODevice::ReadOnly) || file.readAll() != bytes)
        return 4;
    file.close();
    file.remove();

    QTimer::singleShot(30, &application, SLOT(quit()));
    if (application.exec() != 0 || qstrcmp(qVersion(), "4.8.7") != 0)
        return 5;
    __android_log_write(ANDROID_LOG_INFO, "LongreachDonut", "QtCore 4.8.7 PASS: QString, QFile, QCoreApplication and QTimer");
    return 0;
}
