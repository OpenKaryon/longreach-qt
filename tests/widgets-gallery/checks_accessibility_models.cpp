// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

#include "../common/smokecheck.h"

#include <QAccessible>
#include <QAccessibleBridge>
#include <QAccessibleObject>
#include <QAccessiblePlugin>
#include <QAccessibleWidget>
#include <QAbstractItemModel>
#include <QAbstractItemModelTester>
#include <QApplication>
#include <QApplicationStateChangeEvent>
#include <QByteArray>
#include <QDebug>
#include <QDynamicPropertyChangeEvent>
#include <QEvent>
#include <QList>
#include <QPoint>
#include <QPushButton>
#include <QRect>
#include <QSize>
#include <QStandardItemModel>
#include <QStringList>
#include <QVariant>
#include <QWhatsThisClickedEvent>

class SmokeAccessibleBridge : public QAccessibleBridge
{
public:
    QAccessibleInterface *root = nullptr;
    QAccessibleEvent *lastEvent = nullptr;

    void setRootObject(QAccessibleInterface *iface) override { root = iface; }
    void notifyAccessibilityUpdate(QAccessibleEvent *event) override { lastEvent = event; }
};

class SmokeAccessibleBridgePlugin : public QAccessibleBridgePlugin
{
public:
    QAccessibleBridge *create(const QString &key) override
    {
        return key == QStringLiteral("smoke") ? new SmokeAccessibleBridge : nullptr;
    }
};

class SmokeAccessiblePlugin : public QAccessiblePlugin
{
public:
    QAccessibleInterface *create(const QString &, QObject *) override { return nullptr; }
};

class SmokeAccessibleObject : public QAccessibleObject,
                              public QAccessibleTextInterface,
                              public QAccessibleEditableTextInterface,
                              public QAccessibleValueInterface,
                              public QAccessibleImageInterface,
                              public QAccessibleTableCellInterface,
                              public QAccessibleTableInterface,
                              public QAccessibleActionInterface
{
public:
    explicit SmokeAccessibleObject(QObject *object)
        : QAccessibleObject(object)
    {
    }

    QAccessibleInterface *parent() const override { return nullptr; }
    QAccessibleInterface *child(int) const override { return nullptr; }
    int childCount() const override { return 0; }
    int indexOfChild(const QAccessibleInterface *) const override { return -1; }
    QString text(QAccessible::Text t) const override
    {
        return texts.value(t);
    }
    void setText(QAccessible::Text t, const QString &value) override
    {
        texts[t] = value;
    }
    QAccessible::Role role() const override { return QAccessible::EditableText; }
    QAccessible::State state() const override
    {
        QAccessible::State s;
        s.focusable = true;
        s.editable = true;
        return s;
    }
    void *interface_cast(QAccessible::InterfaceType type) override
    {
        if (type == QAccessible::TextInterface)
            return static_cast<QAccessibleTextInterface *>(this);
        if (type == QAccessible::EditableTextInterface)
            return static_cast<QAccessibleEditableTextInterface *>(this);
        if (type == QAccessible::ValueInterface)
            return static_cast<QAccessibleValueInterface *>(this);
        if (type == QAccessible::ImageInterface)
            return static_cast<QAccessibleImageInterface *>(this);
        if (type == QAccessible::TableCellInterface)
            return static_cast<QAccessibleTableCellInterface *>(this);
        if (type == QAccessible::TableInterface)
            return static_cast<QAccessibleTableInterface *>(this);
        if (type == QAccessible::ActionInterface)
            return static_cast<QAccessibleActionInterface *>(this);
        return nullptr;
    }

    void selection(int, int *startOffset, int *endOffset) const override
    {
        *startOffset = selectionStart;
        *endOffset = selectionEnd;
    }
    int selectionCount() const override { return hasSelection ? 1 : 0; }
    void addSelection(int startOffset, int endOffset) override
    {
        hasSelection = true;
        selectionStart = startOffset;
        selectionEnd = endOffset;
    }
    void removeSelection(int) override { hasSelection = false; }
    void setSelection(int, int startOffset, int endOffset) override
    {
        addSelection(startOffset, endOffset);
    }
    int cursorPosition() const override { return cursor; }
    void setCursorPosition(int position) override { cursor = position; }
    QString text(int startOffset, int endOffset) const override
    {
        return storage.mid(startOffset, endOffset - startOffset);
    }
    int characterCount() const override { return storage.size(); }
    QRect characterRect(int offset) const override { return QRect(offset, 0, 1, 1); }
    int offsetAtPoint(const QPoint &point) const override { return point.x(); }
    void scrollToSubstring(int startIndex, int endIndex) override
    {
        selectionStart = startIndex;
        selectionEnd = endIndex;
    }
    QString attributes(int offset, int *startOffset, int *endOffset) const override
    {
        *startOffset = offset;
        *endOffset = offset + 1;
        return QStringLiteral("offset:%1").arg(offset);
    }
    void deleteText(int startOffset, int endOffset) override
    {
        storage.remove(startOffset, endOffset - startOffset);
    }
    void insertText(int offset, const QString &text) override
    {
        storage.insert(offset, text);
    }
    void replaceText(int startOffset, int endOffset, const QString &text) override
    {
        storage.replace(startOffset, endOffset - startOffset, text);
    }

    QVariant currentValue() const override { return value; }
    void setCurrentValue(const QVariant &v) override { value = v; }
    QVariant maximumValue() const override { return 100; }
    QVariant minimumValue() const override { return 0; }
    QVariant minimumStepSize() const override { return 1; }

    QString imageDescription() const override { return QStringLiteral("sample"); }
    QSize imageSize() const override { return QSize(16, 16); }
    QPoint imagePosition() const override { return QPoint(2, 3); }

    bool isSelected() const override { return true; }
    QList<QAccessibleInterface *> columnHeaderCells() const override { return {}; }
    QList<QAccessibleInterface *> rowHeaderCells() const override { return {}; }
    int columnIndex() const override { return 0; }
    int rowIndex() const override { return 0; }
    int columnExtent() const override { return 1; }
    int rowExtent() const override { return 1; }
    QAccessibleInterface *table() const override { return const_cast<SmokeAccessibleObject *>(this); }

    QAccessibleInterface *caption() const override { return nullptr; }
    QAccessibleInterface *summary() const override { return nullptr; }
    QAccessibleInterface *cellAt(int row, int column) const override
    {
        return row == 0 && column == 0 ? const_cast<SmokeAccessibleObject *>(this) : nullptr;
    }
    int selectedCellCount() const override { return 1; }
    QList<QAccessibleInterface *> selectedCells() const override
    {
        return {const_cast<SmokeAccessibleObject *>(this)};
    }
    QString columnDescription(int column) const override
    {
        return QStringLiteral("column-%1").arg(column);
    }
    QString rowDescription(int row) const override
    {
        return QStringLiteral("row-%1").arg(row);
    }
    int selectedColumnCount() const override { return 1; }
    int selectedRowCount() const override { return 1; }
    int columnCount() const override { return 1; }
    int rowCount() const override { return 1; }
    QList<int> selectedColumns() const override { return {0}; }
    QList<int> selectedRows() const override { return {0}; }
    bool isColumnSelected(int column) const override { return column == 0; }
    bool isRowSelected(int row) const override { return row == 0; }
    bool selectRow(int row) override { selectedRow = row; return row == 0; }
    bool selectColumn(int column) override { selectedColumn = column; return column == 0; }
    bool unselectRow(int row) override { selectedRow = -1; return row == 0; }
    bool unselectColumn(int column) override { selectedColumn = -1; return column == 0; }
    void modelChange(QAccessibleTableModelChangeEvent *event) override
    {
        lastModelChange = event->modelChangeType();
    }

    QStringList actionNames() const override { return {QAccessibleActionInterface::pressAction()}; }
    void doAction(const QString &actionName) override { lastAction = actionName; }
    QStringList keyBindingsForAction(const QString &actionName) const override
    {
        return actionName == QAccessibleActionInterface::pressAction()
            ? QStringList(QStringLiteral("Space")) : QStringList();
    }

    QString storage = QStringLiteral("abcdef");
    QHash<QAccessible::Text, QString> texts;
    QVariant value = 7;
    int cursor = 0;
    int selectionStart = 0;
    int selectionEnd = 0;
    int selectedRow = -1;
    int selectedColumn = -1;
    QAccessibleTableModelChangeEvent::ModelChangeType lastModelChange =
        QAccessibleTableModelChangeEvent::ModelReset;
    QString lastAction;
    bool hasSelection = false;
};

class PublicAccessibleWidget : public QAccessibleWidget
{
public:
    explicit PublicAccessibleWidget(QWidget *widget)
        : QAccessibleWidget(widget, QAccessible::Button, QStringLiteral("button"))
    {
    }
    ~PublicAccessibleWidget() override = default;
};

void checkAccessibilityAndModelHelpers(SmokeReporter &r)
{
#ifndef QT_NO_ACCESSIBILITY
    r.check("accessibility/interfaces-events-actions", [&](QString &d) {
        QObject object;
        SmokeAccessibleObject iface(&object);
        QAccessibleInterface *base = &iface;
        base->setText(QAccessible::Name, QStringLiteral("name"));
        auto *textIface = base->textInterface();
        auto *editIface = base->editableTextInterface();
        auto *valueIface = base->valueInterface();
        auto *imageIface = base->imageInterface();
        auto *tableIface = base->tableInterface();
        auto *cellIface = base->tableCellInterface();
        auto *actionIface = base->actionInterface();

        textIface->setCursorPosition(2);
        editIface->replaceText(1, 3, QStringLiteral("ZZ"));
        valueIface->setCurrentValue(11);
        tableIface->selectRow(0);
        tableIface->selectColumn(0);
        actionIface->doAction(QAccessibleActionInterface::pressAction());

        QAccessibleEvent shown(&object, QAccessible::ObjectShow);
        QAccessible::State changed;
        changed.focused = true;
        QAccessibleStateChangeEvent stateChanged(&object, changed);
        QAccessibleTextCursorEvent cursorMoved(&object, 3);
        QAccessibleTextSelectionEvent selectionChanged(&object, 1, 4);
        QAccessibleTextInsertEvent inserted(&object, 2, QStringLiteral("xy"));
        QAccessibleTextRemoveEvent removed(&object, 2, QStringLiteral("z"));
        QAccessibleTextUpdateEvent updated(&object, 2, QStringLiteral("old"), QStringLiteral("new"));
        QAccessibleValueChangeEvent valueChanged(&object, 12);
        QAccessibleTableModelChangeEvent modelChanged(
            &object, QAccessibleTableModelChangeEvent::RowsInserted);
        modelChanged.setFirstRow(1);
        tableIface->modelChange(&modelChanged);

        QAccessibleApplication applicationIface;
        const char *roleName = qAccessibleRoleString(base->role());
        const char *eventName = qAccessibleEventString(shown.type());
        return base->text(QAccessible::Name) == QStringLiteral("name")
            && textIface->cursorPosition() == 2
            && iface.storage == QStringLiteral("aZZdef")
            && valueIface->currentValue().toInt() == 11
            && imageIface->imageSize() == QSize(16, 16)
            && cellIface->table() == base
            && tableIface->cellAt(0, 0) == base
            && iface.lastAction == QAccessibleActionInterface::pressAction()
            && stateChanged.changedStates().focused
            && cursorMoved.cursorPosition() == 3
            && selectionChanged.selectionStart() == 1
            && inserted.textInserted() == QStringLiteral("xy")
            && removed.textRemoved() == QStringLiteral("z")
            && updated.textInserted() == QStringLiteral("new")
            && valueChanged.value().toInt() == 12
            && iface.lastModelChange == QAccessibleTableModelChangeEvent::RowsInserted
            && applicationIface.role() == QAccessible::Application
            && roleName != nullptr && eventName != nullptr;
    });

    r.check("accessibility/widget-and-plugin-factories", [&](QString &d) {
        QPushButton button(QStringLiteral("Press"));
        PublicAccessibleWidget widgetIface(&button);
        SmokeAccessiblePlugin objectPlugin;
        SmokeAccessibleBridgePlugin bridgePlugin;
        QScopedPointer<QAccessibleBridge> bridge(bridgePlugin.create(QStringLiteral("smoke")));
        QAccessibleEvent focusEvent(&button, QAccessible::Focus);
        bridge->setRootObject(&widgetIface);
        bridge->notifyAccessibilityUpdate(&focusEvent);
        auto *typedBridge = static_cast<SmokeAccessibleBridge *>(bridge.data());
        const bool ok = widgetIface.isValid()
            && widgetIface.role() == QAccessible::Button
            && widgetIface.actionNames().contains(QAccessibleActionInterface::setFocusAction())
            && objectPlugin.create(QString(), &button) == nullptr
            && typedBridge->root == &widgetIface
            && typedBridge->lastEvent == &focusEvent;
        if (!ok) {
            d = QStringLiteral("valid=%1 role=%2 actions=%3 pluginNull=%4 root=%5 event=%6")
                    .arg(widgetIface.isValid())
                    .arg(int(widgetIface.role()))
                    .arg(widgetIface.actionNames().join('|'))
                    .arg(objectPlugin.create(QString(), &button) == nullptr)
                    .arg(typedBridge->root == &widgetIface)
                    .arg(typedBridge->lastEvent == &focusEvent);
        }
        return ok;
    });
#else
    r.check("accessibility/not-built", [&](QString &d) {
        d = QStringLiteral("Qt was configured without accessibility");
        return true;
    });
#endif

    r.check("models/tester-and-abstract-base", [&](QString &d) {
        QStandardItemModel model(2, 2);
        model.setData(model.index(0, 0), QStringLiteral("cell"));
        QAbstractItemModel *abstractModel = &model;
        QAbstractItemModelTester tester(&model, QAbstractItemModelTester::FailureReportingMode::Warning);
        return abstractModel->rowCount() == 2
            && abstractModel->data(abstractModel->index(0, 0)).toString() == QStringLiteral("cell")
            && tester.model() == &model
            && tester.failureReportingMode() == QAbstractItemModelTester::FailureReportingMode::Warning;
    });

    r.check("events/application-dynamic-whats-this", [&](QString &d) {
        QApplicationStateChangeEvent appEvent(Qt::ApplicationActive);
        QDynamicPropertyChangeEvent propertyEvent("smokeProperty");
        QWhatsThisClickedEvent whatsThisEvent(QStringLiteral("https://example.invalid/help"));
        return appEvent.applicationState() == Qt::ApplicationActive
            && propertyEvent.propertyName() == QByteArray("smokeProperty")
            && whatsThisEvent.href().contains(QStringLiteral("example.invalid"));
    });
}
