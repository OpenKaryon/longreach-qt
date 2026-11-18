// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
#ifndef SMOKE_OPENGLCOMPAT_H
#define SMOKE_OPENGLCOMPAT_H

// Include after the Qt OpenGL headers: Qt 5 publishes the legacy ES macro
// there, while Qt 6 exposes the SDK capability through qtgui-config.h.
#include <QtGlobal>
#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
#include <QtGui/qtguiglobal.h>
#if QT_CONFIG(opengles2)
#define SMOKE_OPENGL_ES 1
#else
#define SMOKE_OPENGL_ES 0
#endif
#elif defined(QT_OPENGL_ES_2)
#define SMOKE_OPENGL_ES 1
#else
#define SMOKE_OPENGL_ES 0
#endif

#endif // SMOKE_OPENGLCOMPAT_H
