// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// QtPurchasing: all three classes are constructible without a live purchase
// backend. QInAppStore is a plain QObject. QInAppProduct/QInAppTransaction
// have protected constructors and pure virtuals (purchase()/finalize()) -
// that means only a subclass can create one, not that they're unreachable:
// a minimal subclass calling the protected base constructor is the same
// pattern used for QScxmlCppDataModel/QScxmlTableData elsewhere in this
// suite. Real store backends (android/darwin/winrt, per this module's .pri)
// subclass exactly this way internally.
#include "../common/smokecheck.h"

#ifdef SMOKE_HAVE_PURCHASING
#include <QInAppStore>
#endif
#ifdef SMOKE_HAVE_PURCHASING
#include <QInAppProduct>
#endif
#ifdef SMOKE_HAVE_PURCHASING
#include <QInAppTransaction>
#endif

#if defined(SMOKE_HAVE_PURCHASING)

namespace {

class FixedProduct : public QInAppProduct
{
public:
    FixedProduct(const QString &price, const QString &title, const QString &description,
                ProductType productType, const QString &identifier, QObject *parent)
        : QInAppProduct(price, title, description, productType, identifier, parent) {}
    void purchase() override {}
};

class FixedTransaction : public QInAppTransaction
{
public:
    FixedTransaction(TransactionStatus status, QInAppProduct *product, QObject *parent)
        : QInAppTransaction(status, product, parent) {}
    void finalize() override {}
};

} // namespace

void checkPurchasing(SmokeReporter &r)
{
    r.check("purchasing/store-product-transaction", [&](QString &d) {
        QInAppStore store;
        store.setPlatformProperty(QStringLiteral("qt-smoke"), QStringLiteral("test"));

        auto *product = new FixedProduct(QStringLiteral("0.99"), QStringLiteral("Widget"),
                                         QStringLiteral("A digital widget"),
                                         QInAppProduct::Consumable,
                                         QStringLiteral("widget.001"), &store);
        auto *transaction = new FixedTransaction(QInAppTransaction::PurchaseApproved, product, product);

        return product->identifier() == QStringLiteral("widget.001")
            && product->productType() == QInAppProduct::Consumable
            && product->price() == QStringLiteral("0.99")
            && transaction->status() == QInAppTransaction::PurchaseApproved
            && transaction->product() == product;
    });
}

#else   // the checks above have no counterpart to run against

void checkPurchasing(SmokeReporter &r)
{
    r.check("purchasing/in-app-store", [&](QString &d) {
        r.skip(d, QStringLiteral("QtPurchasing is not in this SDK (Qt 6 dropped it)"));
        return false;
    });
}

#endif
