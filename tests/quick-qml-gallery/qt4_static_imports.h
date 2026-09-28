// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

#ifndef SMOKE_QT4_STATIC_IMPORTS_H
#define SMOKE_QT4_STATIC_IMPORTS_H

#include <QDeclarativeEngine>
#include <QDir>
#include <QLibraryInfo>
#include <QDeclarativeContext>
#include <QDeclarativeView>
#include <QGLWidget>
#include <QGLShaderProgram>
#include <QGLFramebufferObject>

// Qt4's disk qmldir loader cannot resolve linked-in static plugin instances.
// The app registers every Qt.labs module itself. Avoid rediscovering the SDK's
// physical qmldir files, which otherwise demand a DLL/shared plugin even when
// all the URI's types have already been registered. Keep app/user import paths.
inline void configureStaticQt4Imports(QDeclarativeEngine *engine)
{
    QStringList paths = engine->importPathList();
    const QString sdkImports = QDir::cleanPath(QLibraryInfo::location(QLibraryInfo::ImportsPath));
    for (int i = paths.size() - 1; i >= 0; --i) {
#ifdef Q_OS_WIN
        const Qt::CaseSensitivity sensitivity = Qt::CaseInsensitive;
#else
        const Qt::CaseSensitivity sensitivity = Qt::CaseSensitive;
#endif
        if (QDir::cleanPath(paths.at(i)).compare(sdkImports, sensitivity) == 0)
            paths.removeAt(i);
    }
    engine->setImportPathList(paths);
    engine->rootContext()->setContextProperty("appShaderEffectsAvailable", QVariant(false));
}

inline bool configureQt4QmlView(QDeclarativeView &view)
{
    configureStaticQt4Imports(view.engine());
    // ShaderEffectSource needs FBOs and GLSL. GL1.1 systems retain the full
    // raster gallery and explicitly report this unavailable driver feature.
    QGLWidget *candidate = new QGLWidget(&view);
    bool shaderEffects = false;
    if (candidate->isValid()) {
        candidate->makeCurrent();
        shaderEffects = QGLShaderProgram::hasOpenGLShaderPrograms(candidate->context())
            && QGLFramebufferObject::hasOpenGLFramebufferObjects();
    }
    if (shaderEffects) {
        view.setViewport(candidate);
        view.setViewportUpdateMode(QGraphicsView::FullViewportUpdate);
    } else {
        delete candidate;
    }
    view.engine()->rootContext()->setContextProperty("appShaderEffectsAvailable", shaderEffects);
    view.setResizeMode(QDeclarativeView::SizeRootObjectToView);
    return shaderEffects;
}

class SmokeQt4QmlEngine : public QDeclarativeEngine
{
public:
    explicit SmokeQt4QmlEngine(QObject *parent = 0) : QDeclarativeEngine(parent)
    {
        configureStaticQt4Imports(this);
    }
};

#endif
