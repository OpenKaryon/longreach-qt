// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Qt 4 counterpart to checks_accessibility_models.cpp.
//
// Qt 5 redesigned accessibility wholesale, so this is a rewrite rather than a
// guarded copy - not one of that file's forty overrides would override anything
// here. The two differences that shape this file:
//
//   * Qt 4 addresses a widget's children by *index* through one interface
//     (childCount(), text(Name, child), role(child)), where Qt 5 gives each
//     child an interface of its own. So the base API is exercised through a
//     real QAccessibleWidget rather than through a subclass.
//   * the QAccessible2 interfaces - text, editable text, value, table, action,
//     image - are mixins with Qt 4-specific signatures. They are named and
//     type-checked here rather than implemented: a QAccessible2 implementation
//     is only reachable by a bridge asking Qt for it, which needs an
//     accessibility bridge this static build does not load. Naming them is what
//     the QPlatform* shells in checks_qtbase_tail2.cpp do for the same reason.
//
// QAbstractItemModelTester (Qt 5.11) and QApplicationStateChangeEvent (Qt 5.1)
// have no Qt 4 counterpart, so the two check names below drop the words that
// referred to them.
#include "../common/smokecheck.h"
#include "gallery.h"

#include <QAbstractItemModel>
#include <QAccessible>
#include <qaccessible2.h>
#include <QAccessibleApplication>
#include <QAccessibleBridge>
#include <QAccessibleObject>
#include <QAccessibleWidget>
#include <QApplication>
#include <QByteArray>
#include <QDynamicPropertyChangeEvent>
#include <QEvent>
#include <QPushButton>
#include <QLineEdit>
#include <QSlider>
#include <QTableWidget>
#include <QStandardItemModel>
#include <QStringList>
#include <QVariant>
#include <QWhatsThisClickedEvent>

#if defined(Q_WS_WIN) && defined(QT4_WIN95_ACCESSIBILITY_PROBE)
#include <windows.h>
#include <cstring>
#endif

namespace {

// Qt 4's plugin interfaces carry keys() from QFactoryInterface; Qt 5 replaced
// that with JSON metadata. No Q_OBJECT here on purpose - the class has no
// signals or slots of its own, so it needs no moc pass.
#ifndef QT_NO_ACCESSIBILITY
class SmokeAccessibleWidgetQt4 : public QAccessibleWidget
{
public:
    explicit SmokeAccessibleWidgetQt4(QWidget *widget,
                                      QAccessible::Role role = QAccessible::Client)
        : QAccessibleWidget(widget, role) {}
    ~SmokeAccessibleWidgetQt4() override {}
};
#endif

} // namespace

void addAccessibilityQt4Checks(SmokeReporter &r)
{
#ifndef QT_NO_ACCESSIBILITY
    r.check("accessibility/interfaces-events-actions", [&](QString &d) {
        QPushButton button(QStringLiteral("Press"));
        button.setAccessibleName(QStringLiteral("smoke-button"));
        button.setAccessibleDescription(QStringLiteral("a button"));

        // QAccessibleWidget is concrete in Qt 4 and wraps any QWidget, so this
        // needs no accessibility plugin to be loaded - which matters in a static
        // build where none is.
        SmokeAccessibleWidgetQt4 widgetInterface(&button, QAccessible::PushButton);
        QAccessibleInterface *iface = &widgetInterface;

        QAccessibleApplication applicationInterface;
        QAccessibleInterface *applicationIface = &applicationInterface;

        QAccessibleEvent accessibleEvent(QEvent::AccessibilityDescription, 0);
        accessibleEvent.setValue(QStringLiteral("described"));

        // Named and type-checked, not implemented - see the file comment.
        QAccessibleTextInterface *textInterface = 0;
        QAccessibleEditableTextInterface *editableTextInterface = 0;
        QAccessibleValueInterface *valueInterface = 0;
        QAccessibleTableInterface *tableInterface = 0;
        QAccessibleActionInterface *actionInterface = 0;
        QAccessibleImageInterface *imageInterface = 0;

        QStringList misses;
        if (iface->object() != &button) misses << QStringLiteral("object");
        if (iface->role(0) != QAccessible::PushButton) misses << QStringLiteral("role");
        if (iface->text(QAccessible::Name, 0) != QStringLiteral("smoke-button"))
            misses << QStringLiteral("name");
        if (iface->text(QAccessible::Description, 0) != QStringLiteral("a button"))
            misses << QStringLiteral("description");
        if (iface->childCount() != 0) misses << QStringLiteral("childcount");
        if (!iface->isValid()) misses << QStringLiteral("valid");
        if (applicationIface->role(0) != QAccessible::Application)
            misses << QStringLiteral("application-role");
        if (accessibleEvent.value() != QStringLiteral("described"))
            misses << QStringLiteral("event-value");
        if (accessibleEvent.child() != 0) misses << QStringLiteral("event-child");
        if (textInterface || editableTextInterface || valueInterface
            || tableInterface || actionInterface || imageInterface)
            misses << QStringLiteral("qaccessible2-shells");
        if (!misses.isEmpty())
            d = misses.join(QLatin1String(","));
        return misses.isEmpty();
    });

    r.check("accessibility/widget-and-plugin-factories", [&](QString &d) {
        QWidget host;
        SmokeAccessibleWidgetQt4 hostInterface(&host);
        // Qt 4's navigation is index-based and returns the number of the target
        // through an out-parameter; asking a childless widget for a child is the
        // documented way to get 0 back rather than an error.
        QAccessibleInterface *child = 0;
        const int navigated = hostInterface.navigate(QAccessible::Child, 1, &child);
        delete child;

        d = QStringLiteral("bridge-plugin type=%1 bytes").arg(sizeof(QAccessibleBridgePlugin));
        return sizeof(QAccessibleBridgePlugin) > 0
            && hostInterface.object() == &host
            && navigated <= 0;
    });

#if defined(Q_WS_WIN) && defined(QT4_WIN95_ACCESSIBILITY_PROBE)
    r.check("accessibility/native-widget-factory", [&](QString &d) {
        QPushButton button(QLatin1String("button"));
        QLineEdit edit(QLatin1String("value"));
        QSlider slider;
        QTableWidget table(2, 2);
        QWidget *widgets[] = {&button, &edit, &slider, &table};
        const QAccessible::Role roles[] = {QAccessible::PushButton,
            QAccessible::EditableText, QAccessible::Slider, QAccessible::Client};
        QStringList misses;
        for (unsigned i = 0; i < sizeof(widgets) / sizeof(widgets[0]); ++i) {
            QAccessibleInterface *iface = QAccessible::queryAccessibleInterface(widgets[i]);
            if (!iface || !iface->isValid() || iface->object() != widgets[i]
                || iface->role(0) != roles[i]
                // Qt4's Windows item-view bridge exposes the table as the
                // viewport child of a Client container, unlike its X11 bridge.
                || (i == 3 && iface->role(1) != QAccessible::Table))
                misses << QString::fromLatin1(widgets[i]->metaObject()->className());
            delete iface;
        }
        d = misses.join(QLatin1String(","));
        return misses.isEmpty();
    });

    r.check("accessibility/native-name-buffer", [&](QString &d) {
        QWidget host;
        QPushButton button(QLatin1String("visible label"), &host);
        const QString name = QString::fromUtf8("\xd0\x9a\xd0\xbd\xd0\xbe\xd0\xbf\xd0\xba\xd0\xb0")
            + QLatin1String("-95");
        button.setAccessibleName(name);
        const HWND window = button.winId();
        const bool ansi = QSysInfo::windowsVersion() & QSysInfo::WV_DOS_based;
        const int capacities[] = {0, 1, 4, 32};
        QStringList misses;
        for (unsigned i = 0; i < sizeof(capacities) / sizeof(capacities[0]); ++i) {
            const int capacity = capacities[i];
            if (ansi) {
                char buffer[40];
                std::memset(buffer, 0x5a, sizeof(buffer));
                const QByteArray bytes = name.toLocal8Bit();
                const int expected = capacity ? qMin(capacity - 1, bytes.size()) : 0;
                const LRESULT copied = SendMessageA(window, WM_GETTEXT, capacity,
                                                    reinterpret_cast<LPARAM>(buffer + 1));
                if (copied != expected || buffer[0] != 0x5a
                    || (capacity && (std::memcmp(buffer + 1, bytes.constData(), expected)
                                     || buffer[expected + 1] != 0)))
                    misses << QString::fromLatin1("ANSI-content-%1").arg(capacity);
                for (int j = capacity + 1; j < int(sizeof(buffer)); ++j)
                    if (buffer[j] != 0x5a) {
                        misses << QString::fromLatin1("ANSI-overwrite-%1").arg(capacity);
                        break;
                    }
            } else {
                ushort buffer[40];
                for (int j = 0; j < 40; ++j) buffer[j] = 0x5a5a;
                const int expected = capacity ? qMin(capacity - 1, name.size()) : 0;
                const LRESULT copied = SendMessageW(window, WM_GETTEXT, capacity,
                                                    reinterpret_cast<LPARAM>(buffer + 1));
                if (copied != expected || buffer[0] != 0x5a5a
                    || (capacity && (std::memcmp(buffer + 1, name.utf16(), expected * sizeof(ushort))
                                     || buffer[expected + 1] != 0)))
                    misses << QString::fromLatin1("Unicode-content-%1").arg(capacity);
                for (int j = capacity + 1; j < 40; ++j)
                    if (buffer[j] != 0x5a5a) {
                        misses << QString::fromLatin1("Unicode-overwrite-%1").arg(capacity);
                        break;
                    }
            }
        }
        d = misses.isEmpty() ? (ansi ? QLatin1String("ANSI Cyrillic, capacities 0/1/4/32")
                                    : QLatin1String("Unicode Cyrillic, capacities 0/1/4/32"))
                             : misses.join(QLatin1String(","));
        return misses.isEmpty();
    });
#endif
#else
    r.check("accessibility/not-built", [&](QString &d) {
        r.skip(d, QStringLiteral("Qt was configured without accessibility"));
        return false;
    });
#endif

    r.check("models/abstract-base", [&](QString &d) {
        QStandardItemModel model(2, 2);
        model.setData(model.index(0, 0), QStringLiteral("cell"));
        QAbstractItemModel *abstractModel = &model;
        return abstractModel->rowCount() == 2
            && abstractModel->columnCount() == 2
            && abstractModel->data(abstractModel->index(0, 0)).toString()
                   == QStringLiteral("cell");
    });

    r.check("events/dynamic-whats-this", [&](QString &d) {
        QObject target;
        target.setProperty("smokeProperty", 1);
        QDynamicPropertyChangeEvent propertyEvent("smokeProperty");
        QWhatsThisClickedEvent whatsThisEvent(QStringLiteral("https://example.invalid/help"));
        return propertyEvent.propertyName() == QByteArray("smokeProperty")
            && target.property("smokeProperty").toInt() == 1
            && whatsThisEvent.href().contains(QStringLiteral("example.invalid"));
    });
}
