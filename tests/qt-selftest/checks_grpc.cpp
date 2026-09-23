// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// QtGrpc and QtProtobuf - two Qt 6 modules this kit builds into every Qt 6 SDK
// without a check pointed at either.
//
// Neither needs a server here. The serializers are self-contained, the channel
// is lazy - constructing QGrpcHttp2Channel opens nothing until a call is made -
// and the client base only has to be handed a channel to prove the seam works.
// What genuinely cannot be constructed by hand is the operation family
// (QGrpcCallReply and the three stream types): they are returned by generated
// client code and take a QGrpcOperationContext that only the channel makes. Those
// are checked by their type relationships instead, which is the honest limit of
// what a suite without a .proto file and a running server can say about them.
#include "../common/smokecheck.h"

#ifdef SMOKE_HAVE_GRPC
#include <QAbstractGrpcChannel>
#include <QAbstractProtobufSerializer>
#include <QGrpcBidiStream>
#include <QGrpcCallReply>
#include <QGrpcChannelOptions>
#include <QGrpcClientBase>
#include <QGrpcClientStream>
#include <QGrpcHttp2Channel>
#include <QGrpcOperation>
#include <QGrpcOperationContext>
#include <QGrpcServerStream>
#include <QProtobufJsonSerializer>
#include <QProtobufMessage>
#include <QProtobufSerializer>

#include <QByteArray>
#include <QHash>
#include <QObject>
#include <QUrl>

#include <chrono>
#include <memory>
#include <type_traits>

namespace {

// QGrpcClientBase's constructor is protected: it exists to be inherited by the
// client classes the protobuf compiler generates. Inheriting it by hand is the
// same seam without the code generator.
class SmokeGrpcClient : public QGrpcClientBase
{
public:
    SmokeGrpcClient() : QGrpcClientBase(QLatin1StringView("smoke.Service")) {}

    std::unique_ptr<QGrpcClientStream> openClientStream(const QProtobufMessage &message)
    {
        return clientStream(QLatin1StringView("ClientStream"), message, QGrpcCallOptions());
    }

    std::unique_ptr<QGrpcBidiStream> openBidiStream(const QProtobufMessage &message)
    {
        return bidiStream(QLatin1StringView("BidiStream"), message, QGrpcCallOptions());
    }
};

// QQmlAbstractGrpcChannel is the QML side's one pure virtual: hand back a
// channel. Implementing it is the only way to reference the class at all.
} // namespace

#  ifdef SMOKE_HAVE_GRPCQUICK
#    include <QQmlAbstractGrpcChannel>
#    include <QtGrpcQuick/qqmlgrpccalloptions.h>
#    include <QtGrpcQuick/qtqmlgrpcstreamsender.h>
namespace {
class SmokeQmlGrpcChannel : public QQmlAbstractGrpcChannel
{
public:
    std::shared_ptr<QAbstractGrpcChannel> channel() const override { return m_channel; }
    void setChannel(std::shared_ptr<QAbstractGrpcChannel> c) { m_channel = std::move(c); }

private:
    std::shared_ptr<QAbstractGrpcChannel> m_channel;
};

class SmokeQmlClientStreamSender : public QQmlGrpcClientStreamSender
{
public:
    explicit SmokeQmlClientStreamSender(QGrpcClientStream *stream)
        : QQmlGrpcClientStreamSender(stream) {}
};

class SmokeQmlBidiStreamSender : public QQmlGrpcBidiStreamSender
{
public:
    explicit SmokeQmlBidiStreamSender(QGrpcBidiStream *stream)
        : QQmlGrpcBidiStreamSender(stream) {}
};
} // namespace
#  endif
#endif // SMOKE_HAVE_GRPC

void checkGrpc(SmokeReporter &r)
{
#ifndef SMOKE_HAVE_GRPC
    r.check("grpc/module-available", [&](QString &d) {
        r.skip(d, QStringLiteral("QtGrpc is Qt 6 and later and not in this SDK"));
        return false;
    });
#else
    r.check("grpc/protobuf-serializers", [](QString &d) {
        QProtobufSerializer binary;
        QProtobufJsonSerializer json;
        // Both are final classes over one abstract base, which is the whole
        // point of the interface: the wire format is chosen by which one you
        // hand to the channel.
        const QAbstractProtobufSerializer *asBase = &binary;
        const QAbstractProtobufSerializer *asJsonBase = &json;
        binary.shouldPreserveUnknownFields(true);

        // On Qt 6.8 QProtobufJsonSerializer starts at Error::None and
        // QProtobufSerializer at Error::UnknownType with an empty lastErrorString().
        // That is Qt's behaviour; the pair is printed so a change shows in the log.
        const int binaryError = int(binary.lastError());
        d = QStringLiteral("binary error %1 (\"%2\"), json error %3")
                .arg(binaryError).arg(binary.lastErrorString())
                .arg(int(json.lastError()));
        return asBase != nullptr && asJsonBase != nullptr
            && json.lastError() == QAbstractProtobufSerializer::Error::None
            && json.lastErrorString().isEmpty()
            && binaryError >= int(QAbstractProtobufSerializer::Error::None)
            && binaryError <= int(QAbstractProtobufSerializer::Error::InvalidFormat);
    });

    r.check("grpc/channel-options", [](QString &d) {
        QGrpcChannelOptions options;
        QHash<QByteArray, QByteArray> metadata;
        metadata.insert(QByteArrayLiteral("x-smoke"), QByteArrayLiteral("1"));
        // The setters return *this by design, so a chain is the intended
        // spelling and worth exercising as one.
        options.setDeadlineTimeout(std::chrono::milliseconds(2500))
               .setMetadata(metadata);
        const auto deadline = options.deadlineTimeout();
        d = QStringLiteral("deadline %1 ms, %2 metadata entr%3")
                .arg(deadline ? qint64(deadline->count()) : -1)
                .arg(options.metadata().size())
                .arg(options.metadata().size() == 1 ? "y" : "ies");
        return deadline.has_value() && deadline->count() == 2500
            && options.metadata().value(QByteArrayLiteral("x-smoke")) == QByteArrayLiteral("1");
    });

    r.check("grpc/http2-channel", [](QString &d) {
        QGrpcChannelOptions options;
        options.setDeadlineTimeout(std::chrono::milliseconds(1000));
        // Nothing is dialled here: the channel resolves and connects on the
        // first call, so constructing one against an address that does not
        // exist is safe and stays offline.
        auto channel = std::make_shared<QGrpcHttp2Channel>(
            QUrl(QStringLiteral("http://127.0.0.1:1")), options);
        const std::shared_ptr<QAbstractGrpcChannel> asBase = channel;
        d = QStringLiteral("QGrpcHttp2Channel constructed and seen as %1")
                .arg(QLatin1String("QAbstractGrpcChannel"));
        return channel != nullptr && asBase != nullptr
            && std::is_base_of<QAbstractGrpcChannel, QGrpcHttp2Channel>::value;
    });

    r.check("grpc/client-base-channel-seam", [](QString &d) {
        SmokeGrpcClient client;
        auto channel = std::make_shared<QGrpcHttp2Channel>(
            QUrl(QStringLiteral("http://127.0.0.1:1")));
        const bool attached = client.attachChannel(channel);
        d = QStringLiteral("attach=%1, channel read back=%2")
                .arg(int(attached)).arg(int(client.channel() == channel));
        return attached && client.channel() == channel
            && client.metaObject()->inherits(&QGrpcClientBase::staticMetaObject);
    });

    r.check("grpc/operation-types", [](QString &d) {
        // Not constructible without a QGrpcOperationContext, which only a
        // channel produces, so what is checked is the shape of the family:
        // one QObject-derived base and four operations over it.
        d = QStringLiteral("QGrpcOperation base with call, server, client and bidi streams");
        return std::is_base_of<QObject, QGrpcOperation>::value
            && std::is_base_of<QGrpcOperation, QGrpcCallReply>::value
            && std::is_base_of<QGrpcOperation, QGrpcServerStream>::value
            && std::is_base_of<QGrpcOperation, QGrpcClientStream>::value
            && std::is_base_of<QGrpcOperation, QGrpcBidiStream>::value
            && std::is_base_of<QObject, QGrpcOperationContext>::value
            && sizeof(QGrpcOperationContext) > 0;
    });

    r.check("grpc/qml-channel-interface", [&r](QString &d) {
#  ifdef SMOKE_HAVE_GRPCQUICK
        SmokeQmlGrpcChannel qmlChannel;
        auto channel = std::make_shared<QGrpcHttp2Channel>(
            QUrl(QStringLiteral("http://127.0.0.1:1")));
        qmlChannel.setChannel(channel);
        d = QStringLiteral("QQmlAbstractGrpcChannel implemented and answered");
        return qmlChannel.channel() == channel
            && std::is_base_of<QObject, QQmlAbstractGrpcChannel>::value;
#  else
        r.skip(d, QStringLiteral("QtGrpcQuick is not in this SDK"));
        return false;
#  endif
    });

    r.check("grpc/qml-call-options-and-stream-senders", [&r](QString &d) {
#  ifdef SMOKE_HAVE_GRPCQUICK
        QtGrpcQuickPrivate::QQmlGrpcCallOptions options;
        options.setDeadlineTimeout(2500);

        SmokeGrpcClient client;
        client.attachChannel(std::make_shared<QGrpcHttp2Channel>(
            QUrl(QStringLiteral("http://127.0.0.1:1"))));
        QProtobufMapEntry<QtProtobuf::int32, QtProtobuf::int32> message;
        message.setKey(7);
        message.setValue(9);
        std::unique_ptr<QGrpcClientStream> clientStream = client.openClientStream(message);
        std::unique_ptr<QGrpcBidiStream> bidiStream = client.openBidiStream(message);
        if (!clientStream || !bidiStream) {
            d = QStringLiteral("the lazy channel did not create both streams");
            return false;
        }
        SmokeQmlClientStreamSender clientSender(clientStream.get());
        SmokeQmlBidiStreamSender bidiSender(bidiStream.get());

        d = QStringLiteral("deadline=%1 client=%2 bidi=%3")
                .arg(options.deadlineTimeout())
                .arg(QString::fromLatin1(clientSender.metaObject()->className()))
                .arg(QString::fromLatin1(bidiSender.metaObject()->className()));
        return options.deadlineTimeout() == 2500
            && options.options().deadlineTimeout().has_value()
            && options.options().deadlineTimeout()->count() == 2500
            && clientSender.parent() == nullptr && bidiSender.parent() == nullptr
            && clientSender.metaObject()->inherits(&QObject::staticMetaObject)
            && bidiSender.metaObject()->inherits(&QObject::staticMetaObject);
#  else
        r.skip(d, QStringLiteral("QtGrpcQuick is not in this SDK"));
        return false;
#  endif
    });
#endif
}
