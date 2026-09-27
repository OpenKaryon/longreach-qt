// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Qt 4's gl-heavy counterpart. Qt3D, QtCharts and DataVisualization did not
// exist yet; this application exercises their period-equivalent foundation,
// the QtOpenGL module, under the same executable name used by Qt 5 and Qt 6.
#include "../common/smokecheck.h"
#include "qt4_opengl.h"
#include "../common/crashinfo.h"

#include <QApplication>
#include <QMainWindow>
#include <QStatusBar>
#include <QDir>

static int runSelfTest()
{
    SmokeReporter r("gl-heavy");
    r.setTrace(true);
    if (!r.setLogFile(QDir(QCoreApplication::applicationDirPath()).filePath("gl-selftest.log")))
        return 2;
    checkQt4OpenGL(r);
    checkQt4OpenGLGallery(r);
    return r.summary();
}

int main(int argc, char *argv[])
{
#ifdef Q_OS_WIN
    SmokeCrashInfo::install();
#endif
    QApplication app(argc, argv);

    if (app.arguments().contains(QStringLiteral("--selftest")))
        return runSelfTest();

    QMainWindow window;
    window.setWindowTitle(QStringLiteral("Qt gl-heavy Gallery - ")
                          + QString::fromLatin1(QT_VERSION_STR));
    window.setCentralWidget(buildQt4OpenGLGallery());
    window.statusBar()->showMessage(
        QStringLiteral("gl-heavy gallery - Qt 4 QtOpenGL compatibility path"));
    window.resize(760, 560);
    window.show();
    return app.exec();
}
