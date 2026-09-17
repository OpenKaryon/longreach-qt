// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Qt 4 API that exists only on one windowing system.
//
// The per-window-system API of the three desktop platforms: the native Windows
// styles and clipboard bridge, the X11 embedding widgets, and Cocoa interop.
//
// What is deliberately NOT here is Qt for Embedded Linux, Symbian, Windows CE
// and QNX. Those stay in the uncovered list on purpose - the coverage figure is
// meant to show that whole platforms are still unreached, not to be flattered
// by excluding them. If one of those ever becomes a target, the number will say
// so before anyone writes a line.
//
// Each is guarded on the window system rather than on the OS macro, because
// that is the question Qt 4 itself asks: Q_WS_WIN, Q_WS_X11 and Q_WS_MAC are
// set by how Qt was configured, and a Qt built for embedded Linux on an X11
// machine is exactly the case where Q_OS_LINUX would give the wrong answer.
//
// The Mac block has no target in this kit today - there is no Qt 4 macOS image
// - so it is written and never compiled. That is deliberate: the rule this
// suite follows is that platform API is checked on its platform, and the day a
// Qt 4 macOS target appears these run without anyone having to remember them.

#include "../common/smokecheck.h"
#include "gallery.h"

#include <QString>
#include <QWidget>

#if defined(Q_WS_WIN)
// QWindowsMime speaks COM: its interface is written in terms of FORMATETC and
// IDataObject, so the platform headers have to come first or the class is
// declared against incomplete types.
#  include <windows.h>
#  include <objidl.h>
#  include <QWindowsMime>
#  include <QWindowsVistaStyle>
#  include <QWindowsXPStyle>
#  include <QVariant>
#  include <QVector>
#endif

#if defined(Q_WS_X11)
#  include <QX11EmbedContainer>
#  include <QX11EmbedWidget>
#endif

#if defined(Q_WS_MAC)
#  include <QMacCocoaViewContainer>
#  include <QMacNativeWidget>
#  include <QMacMime>
#endif

#if defined(Q_WS_WIN)
namespace {

// QWindowsMime is pure virtual on six counts, so the only way to check it is to
// implement one. This converter claims nothing, which is enough to prove the
// vtable and the registration in the constructor.
class NullWindowsMime : public QWindowsMime
{
public:
    bool canConvertFromMime(const FORMATETC &, const QMimeData *) const { return false; }
    bool convertFromMime(const FORMATETC &, const QMimeData *, STGMEDIUM *) const { return false; }
    QVector<FORMATETC> formatsForMime(const QString &, const QMimeData *) const
        { return QVector<FORMATETC>(); }
    bool canConvertToMime(const QString &, IDataObject *) const { return false; }
    QVariant convertToMime(const QString &, IDataObject *, QVariant::Type) const
        { return QVariant(); }
    QString mimeForFormat(const FORMATETC &) const { return QString(); }
};

} // namespace
#endif

void addPlatform4Checks(SmokeReporter &r)
{
    r.check("platform4/mac-native-embedding", [&r](QString &d) {
#if defined(Q_WS_MAC)
        // Cocoa interop, dropped in Qt 5: QMacCocoaViewContainer hosts an NSView in a
        // QWidget, QMacNativeWidget the reverse; QMacMime is the clipboard bridge.
        QMacCocoaViewContainer container(0);
        QMacNativeWidget native;
        d = QString::fromLatin1("%1 / %2")
                .arg(QString::fromLatin1(container.metaObject()->className()))
                .arg(QString::fromLatin1(native.metaObject()->className()));
        return container.cocoaView() == 0
            && QString::fromLatin1(native.metaObject()->className())
                   == QLatin1String("QMacNativeWidget")
            && sizeof(QMacMime) > 0;
#else
        r.skip(d, QLatin1String("QMacCocoaViewContainer/QMacNativeWidget need a Q_WS_MAC build"));
        return true;
#endif
    });

    r.check("platform4/windows-native-styles", [&r](QString &d) {
#if defined(Q_WS_WIN)
        // Both are real QStyle subclasses in a Qt 4 Windows build, and both are
        // gone in Qt 5, where the native look moved into the platform theme.
        QWindowsXPStyle xp;
        QWindowsVistaStyle vista;
        d = QString::fromLatin1("%1 / %2")
                .arg(QString::fromLatin1(xp.metaObject()->className()))
                .arg(QString::fromLatin1(vista.metaObject()->className()));
        return QString::fromLatin1(xp.metaObject()->className()) == QLatin1String("QWindowsXPStyle")
            && QString::fromLatin1(vista.metaObject()->className()) == QLatin1String("QWindowsVistaStyle")
            && xp.standardPalette() == xp.standardPalette();
#else
        r.skip(d, QLatin1String("QWindowsXPStyle/QWindowsVistaStyle need a Q_WS_WIN build"));
        return true;
#endif
    });

    r.check("platform4/windows-mime", [&r](QString &d) {
#if defined(Q_WS_WIN)
        // Constructing one registers it with Qt's clipboard bridge, and
        // destroying it unregisters - so this also checks that half.
        NullWindowsMime mime;
        d = QLatin1String("a QWindowsMime converter registered and answered");
        return !mime.canConvertToMime(QLatin1String("text/plain"), 0)
            && mime.mimeForFormat(FORMATETC()).isEmpty()
            && mime.formatsForMime(QLatin1String("text/plain"), 0).isEmpty();
#else
        r.skip(d, QLatin1String("QWindowsMime needs a Q_WS_WIN build"));
        return true;
#endif
    });

    r.check("platform4/x11-embedding", [&r](QString &d) {
#if defined(Q_WS_X11)
        // XEMBED, which Qt 5 dropped: a container adopts a foreign window and
        // an embed widget plugs into someone else's container.
        QX11EmbedContainer container;
        QX11EmbedWidget embedded;
        d = QString::fromLatin1("container id %1, client id %2")
                .arg(quint64(container.winId())).arg(quint64(embedded.winId()));
        return container.clientWinId() == 0 && embedded.containerWinId() == 0
            && container.winId() != 0 && embedded.winId() != 0;
#else
        r.skip(d, QLatin1String("QX11Embed* need a Q_WS_X11 build"));
        return true;
#endif
    });
}
