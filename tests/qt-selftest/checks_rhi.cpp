// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// QRhi - Qt 6's rendering hardware interface, the layer everything graphical
// in Qt 6 sits on. It is the single largest block of Qt 6 API the suite had
// never touched, and it turned out to be reachable from the headless battery:
// QRhi ships a Null backend that implements the whole interface and draws
// nothing, so buffers, textures, render targets and a complete offscreen frame
// with a real render pass all work with no GPU, no window and no display.
// Measured before this file was written, not assumed.
//
// The headers live under QtGui/<version>/QtGui/rhi/, which makes this private
// API. That is deliberate on Qt's part - the ABI is not frozen - and it is why
// the app links Qt::GuiPrivate. The suite already reaches QPA classes the same
// way.
//
// Two things here are named rather than driven, and both say why: a swapchain
// needs a real window to target, and a graphics pipeline needs compiled shader
// stages. The QShader family beside them is covered as value types, which is
// what it is - the compiler that produces one is QShaderBaker, a separate
// toolchain this suite does not run.
#include "../common/smokecheck.h"

#include <QColor>
#include <QSize>

#if QT_VERSION_MAJOR >= 6
#include <rhi/qrhi.h>
#include <rhi/qrhi_platform.h>
#include <rhi/qshader.h>
#include <rhi/qshaderdescription.h>
#define SMOKE_HAVE_QT6_VULKAN_RHI (QT_CONFIG(vulkan) && __has_include(<vulkan/vulkan.h>))
#define SMOKE_HAVE_QT6_METAL_RHI QT_CONFIG(metal)
#else
#define SMOKE_HAVE_QT6_VULKAN_RHI 0
#define SMOKE_HAVE_QT6_METAL_RHI 0
#endif

void checkRhi(SmokeReporter &r)
{
    r.check("rhi/null-backend-resources", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        QRhiNullInitParams params;
        QRhiInitParams *paramsBase = &params;
        QScopedPointer<QRhi> rhi(QRhi::create(QRhi::Null, paramsBase));
        if (rhi.isNull()) {
            r.skip(d, QStringLiteral("QRhi::create(Null) failed"));
            return false;
        }

        const QRhiDriverInfo info = rhi->driverInfo();
        const QRhiStats stats = rhi->statistics();

        QScopedPointer<QRhiBuffer> buffer(
            rhi->newBuffer(QRhiBuffer::Immutable, QRhiBuffer::VertexBuffer, 256));
        QScopedPointer<QRhiTexture> texture(
            rhi->newTexture(QRhiTexture::RGBA8, QSize(64, 64)));
        QScopedPointer<QRhiRenderBuffer> renderBuffer(
            rhi->newRenderBuffer(QRhiRenderBuffer::DepthStencil, QSize(64, 64)));
        QScopedPointer<QRhiSampler> sampler(
            rhi->newSampler(QRhiSampler::Linear, QRhiSampler::Linear, QRhiSampler::None,
                            QRhiSampler::ClampToEdge, QRhiSampler::ClampToEdge));

        const bool built = buffer->create() && texture->create()
            && renderBuffer->create() && sampler->create();

        // Every one of them is a QRhiResource, which is what owns the
        // lifetime and the debug name.
        QRhiResource *resourceBase = buffer.data();
        resourceBase->setName(QByteArrayLiteral("qt-smoke-vertices"));

        QStringList misses;
        if (rhi->backendName() != QByteArrayLiteral("Null")) misses << QStringLiteral("backend");
        if (info.deviceName.isEmpty()) misses << QStringLiteral("driverinfo");
        if (stats.totalPipelineCreationTime < 0) misses << QStringLiteral("stats");
        if (!built) misses << QStringLiteral("create");
        if (buffer->size() != 256) misses << QStringLiteral("buffersize");
        if (texture->pixelSize() != QSize(64, 64)) misses << QStringLiteral("texturesize");
        if (resourceBase->name() != QByteArrayLiteral("qt-smoke-vertices"))
            misses << QStringLiteral("resource");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QRhi is Qt 6 only"));
        return false;
#endif
    });

    r.check("rhi/pipeline-and-render-target", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        QRhiNullInitParams params;
        QScopedPointer<QRhi> rhi(QRhi::create(QRhi::Null, &params));
        if (rhi.isNull()) {
            r.skip(d, QStringLiteral("QRhi::create(Null) failed"));
            return false;
        }

        QScopedPointer<QRhiTexture> colour(
            rhi->newTexture(QRhiTexture::RGBA8, QSize(64, 64), 1,
                            QRhiTexture::RenderTarget | QRhiTexture::UsedAsTransferSource));
        colour->create();

        QRhiColorAttachment attachment(colour.data());
        QRhiTextureRenderTargetDescription description(attachment);
        QScopedPointer<QRhiTextureRenderTarget> renderTarget(
            rhi->newTextureRenderTarget(description));
        QScopedPointer<QRhiRenderPassDescriptor> renderPass(
            renderTarget->newCompatibleRenderPassDescriptor());
        renderTarget->setRenderPassDescriptor(renderPass.data());
        const bool targetBuilt = renderTarget->create();
        QRhiRenderTarget *renderTargetBase = renderTarget.data();

        QScopedPointer<QRhiShaderResourceBindings> bindings(rhi->newShaderResourceBindings());
        const QRhiShaderResourceBinding binding =
            QRhiShaderResourceBinding::sampledTexture(0, QRhiShaderResourceBinding::FragmentStage,
                                                      colour.data(), nullptr);
        bindings->setBindings({ binding });
        const bool bindingsBuilt = bindings->create();

        QRhiVertexInputLayout layout;
        layout.setBindings({ QRhiVertexInputBinding(sizeof(float) * 4) });
        layout.setAttributes({ QRhiVertexInputAttribute(0, 0, QRhiVertexInputAttribute::Float4, 0) });

        QScopedPointer<QRhiGraphicsPipeline> pipeline(rhi->newGraphicsPipeline());
        pipeline->setVertexInputLayout(layout);
        pipeline->setShaderResourceBindings(bindings.data());
        pipeline->setRenderPassDescriptor(renderPass.data());
        pipeline->setTopology(QRhiGraphicsPipeline::Triangles);
        // create() is deliberately not called: a pipeline needs compiled
        // shader stages, and compiling one needs the shader toolchain this
        // suite does not run.
        QScopedPointer<QRhiComputePipeline> computePipeline(rhi->newComputePipeline());

        // A swapchain has to target a real window; naming it is as far as it
        // goes from a headless battery.
        QScopedPointer<QRhiSwapChain> swapChain(rhi->newSwapChain());
        QRhiSwapChainRenderTarget *swapChainTarget = nullptr;

        QStringList misses;
        if (!targetBuilt) misses << QStringLiteral("rendertarget");
        if (renderTargetBase->pixelSize() != QSize(64, 64)) misses << QStringLiteral("targetsize");
        if (!bindingsBuilt || bindings->cbeginBindings() == bindings->cendBindings())
            misses << QStringLiteral("bindings");
        if (pipeline->topology() != QRhiGraphicsPipeline::Triangles)
            misses << QStringLiteral("pipeline");
        if (computePipeline.isNull()) misses << QStringLiteral("computepipeline");
        if (swapChain.isNull() || swapChainTarget != nullptr) misses << QStringLiteral("swapchain");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QRhi is Qt 6 only"));
        return false;
#endif
    });

    r.check("rhi/offscreen-frame-and-updates", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        QRhiNullInitParams params;
        QScopedPointer<QRhi> rhi(QRhi::create(QRhi::Null, &params));
        if (rhi.isNull()) {
            r.skip(d, QStringLiteral("QRhi::create(Null) failed"));
            return false;
        }

        QScopedPointer<QRhiBuffer> buffer(
            rhi->newBuffer(QRhiBuffer::Immutable, QRhiBuffer::VertexBuffer, 256));
        buffer->create();
        QScopedPointer<QRhiTexture> colour(
            rhi->newTexture(QRhiTexture::RGBA8, QSize(32, 32), 1,
                            QRhiTexture::RenderTarget | QRhiTexture::UsedAsTransferSource));
        colour->create();
        QScopedPointer<QRhiTexture> copy(
            rhi->newTexture(QRhiTexture::RGBA8, QSize(32, 32)));
        copy->create();

        QRhiColorAttachment attachment(colour.data());
        QScopedPointer<QRhiTextureRenderTarget> renderTarget(
            rhi->newTextureRenderTarget(QRhiTextureRenderTargetDescription(attachment)));
        QScopedPointer<QRhiRenderPassDescriptor> renderPass(
            renderTarget->newCompatibleRenderPassDescriptor());
        renderTarget->setRenderPassDescriptor(renderPass.data());
        renderTarget->create();

        // An offscreen frame is a complete frame with no swapchain behind it:
        // begin, record into a command buffer, end.
        QRhiCommandBuffer *commandBuffer = nullptr;
        if (rhi->beginOffscreenFrame(&commandBuffer) != QRhi::FrameOpSuccess || !commandBuffer) {
            d = QStringLiteral("beginOffscreenFrame failed");
            return false;
        }

        QRhiResourceUpdateBatch *updates = rhi->nextResourceUpdateBatch();
        const QByteArray vertices(256, 'x');
        updates->uploadStaticBuffer(buffer.data(), vertices.constData());

        QImage pixels(32, 32, QImage::Format_RGBA8888);
        pixels.fill(Qt::green);
        QRhiTextureSubresourceUploadDescription subresource(pixels);
        QRhiTextureUploadEntry entry(0, 0, subresource);
        updates->uploadTexture(copy.data(), QRhiTextureUploadDescription(entry));

        QRhiTextureCopyDescription copyDescription;
        copyDescription.setPixelSize(QSize(16, 16));
        updates->copyTexture(copy.data(), colour.data(), copyDescription);

        QRhiReadbackResult readback;
        QRhiReadbackDescription readbackDescription(colour.data());
        updates->readBackTexture(readbackDescription, &readback);

        commandBuffer->debugMarkBegin(QByteArrayLiteral("qt-smoke-pass"));
        commandBuffer->beginPass(renderTarget.data(), QColor(Qt::black),
                                 QRhiDepthStencilClearValue(1.0f, 0), updates);
        commandBuffer->setViewport(QRhiViewport(0, 0, 32, 32));
        commandBuffer->setScissor(QRhiScissor(0, 0, 32, 32));
        commandBuffer->endPass();
        commandBuffer->debugMarkEnd();

        rhi->endOffscreenFrame();
        const QRhi::FrameOpResult finished = rhi->finish();

        QStringList misses;
        if (finished != QRhi::FrameOpSuccess) misses << QStringLiteral("finish");
        if (commandBuffer == nullptr) misses << QStringLiteral("commandbuffer");
        // The Null backend performs no real transfers, so the readback comes
        // back empty - the point here is that the whole path ran.
        if (readback.pixelSize.width() < 0) misses << QStringLiteral("readback");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QRhi is Qt 6 only"));
        return false;
#endif
    });

    r.check("rhi/backend-init-params-and-native-handles", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        // The per-backend structs an application fills in to hand QRhi an
        // existing device, or reads back to reach one. Which ones exist is
        // decided at Qt configure time, so each is behind the same test Qt
        // uses itself.
        QRhiNullInitParams nullParams;
        QRhiNullNativeHandles nullHandles;
        QRhiNativeHandles *handlesBase = &nullHandles;

        QStringList present;
        present << QStringLiteral("null");
#if QT_CONFIG(opengl)
        QRhiGles2InitParams gles2Params;
        QRhiGles2NativeHandles gles2Handles;
        gles2Params.fallbackSurface = nullptr;
        Q_UNUSED(gles2Handles);
        present << QStringLiteral("gles2");
#endif
#ifdef Q_OS_WIN
        QRhiD3D11InitParams d3d11Params;
        QRhiD3D11NativeHandles d3d11Handles;
        QRhiD3D12InitParams d3d12Params;
        QRhiD3D12NativeHandles d3d12Handles;
        QRhiD3D12CommandBufferNativeHandles d3d12CommandBuffer;
        d3d11Params.enableDebugLayer = false;
        d3d12Params.enableDebugLayer = false;
        Q_UNUSED(d3d11Handles); Q_UNUSED(d3d12Handles); Q_UNUSED(d3d12CommandBuffer);
        present << QStringLiteral("d3d11") << QStringLiteral("d3d12");
#endif
#if QT_CONFIG(vulkan) && __has_include(<vulkan/vulkan.h>)
        QRhiVulkanInitParams vulkanParams;
        QRhiVulkanNativeHandles vulkanHandles;
        QRhiVulkanCommandBufferNativeHandles vulkanCommandBuffer;
        QRhiVulkanRenderPassNativeHandles vulkanRenderPass;
        Q_UNUSED(vulkanParams); Q_UNUSED(vulkanHandles);
        Q_UNUSED(vulkanCommandBuffer); Q_UNUSED(vulkanRenderPass);
        present << QStringLiteral("vulkan");
#endif
#if QT_CONFIG(metal)
        QRhiMetalInitParams metalParams;
        QRhiMetalNativeHandles metalHandles;
        QRhiMetalCommandBufferNativeHandles metalCommandBuffer;
        Q_UNUSED(metalParams); Q_UNUSED(metalHandles); Q_UNUSED(metalCommandBuffer);
        present << QStringLiteral("metal");
#endif

        Q_UNUSED(nullParams);
        bool ok = handlesBase != nullptr && !present.isEmpty();
        if (!ok)
            d = QStringLiteral("no backend parameter structs compiled in");
        return ok;
#else
        r.skip(d, QStringLiteral("QRhi is Qt 6 only"));
        return false;
#endif
    });

    r.check("rhi/vulkan-native-frame", [&](QString &d) {
#if SMOKE_HAVE_QT6_VULKAN_RHI
        QVulkanInstance instance;
        if (!instance.create()) {
            r.skip(d, QStringLiteral("QVulkanInstance::create failed: %1")
                          .arg(instance.errorCode()));
            return false;
        }

        QRhiVulkanInitParams params;
        params.inst = &instance;
        QScopedPointer<QRhi> rhi(QRhi::create(QRhi::Vulkan, &params));
        if (rhi.isNull()) {
            r.skip(d, QStringLiteral("QRhi Vulkan backend unavailable"));
            return false;
        }

        const QRhiVulkanNativeHandles *deviceHandles =
            static_cast<const QRhiVulkanNativeHandles *>(rhi->nativeHandles());

        QScopedPointer<QRhiTexture> colour(
            rhi->newTexture(QRhiTexture::RGBA8, QSize(16, 16), 1,
                            QRhiTexture::RenderTarget));
        if (!colour->create()) {
            d = QStringLiteral("Vulkan render texture creation failed");
            return false;
        }
        QRhiColorAttachment attachment(colour.data());
        QScopedPointer<QRhiTextureRenderTarget> target(
            rhi->newTextureRenderTarget(QRhiTextureRenderTargetDescription(attachment)));
        QScopedPointer<QRhiRenderPassDescriptor> pass(
            target->newCompatibleRenderPassDescriptor());
        target->setRenderPassDescriptor(pass.data());
        if (!target->create()) {
            d = QStringLiteral("Vulkan render target creation failed");
            return false;
        }

        QRhiCommandBuffer *commandBuffer = nullptr;
        if (rhi->beginOffscreenFrame(&commandBuffer) != QRhi::FrameOpSuccess
            || !commandBuffer) {
            d = QStringLiteral("Vulkan beginOffscreenFrame failed");
            return false;
        }
        commandBuffer->beginPass(target.data(), Qt::black, { 1.0f, 0 });
        commandBuffer->endPass();
        const QRhiVulkanCommandBufferNativeHandles *commandHandles =
            static_cast<const QRhiVulkanCommandBufferNativeHandles *>(
                commandBuffer->nativeHandles());
        const QRhiVulkanRenderPassNativeHandles *passHandles =
            static_cast<const QRhiVulkanRenderPassNativeHandles *>(pass->nativeHandles());
        rhi->endOffscreenFrame();

        const bool ok = deviceHandles && deviceHandles->physDev != VK_NULL_HANDLE
            && deviceHandles->dev != VK_NULL_HANDLE
            && commandHandles && commandHandles->commandBuffer != VK_NULL_HANDLE
            && passHandles && passHandles->renderPass != VK_NULL_HANDLE;
        d = QStringLiteral("device=%1 command-buffer=%2 render-pass=%3")
                .arg(deviceHandles && deviceHandles->dev != VK_NULL_HANDLE)
                .arg(commandHandles && commandHandles->commandBuffer != VK_NULL_HANDLE)
                .arg(passHandles && passHandles->renderPass != VK_NULL_HANDLE);
        return ok;
#else
        r.skip(d, QStringLiteral("Qt was built without Vulkan headers/backend"));
        return false;
#endif
    });

    r.check("rhi/metal-native-frame", [&](QString &d) {
#if SMOKE_HAVE_QT6_METAL_RHI
        QRhiMetalInitParams params;
        QScopedPointer<QRhi> rhi(QRhi::create(QRhi::Metal, &params));
        if (rhi.isNull()) {
            r.skip(d, QStringLiteral("QRhi Metal backend unavailable"));
            return false;
        }
        const QRhiMetalNativeHandles *deviceHandles =
            static_cast<const QRhiMetalNativeHandles *>(rhi->nativeHandles());
        QRhiCommandBuffer *commandBuffer = nullptr;
        if (rhi->beginOffscreenFrame(&commandBuffer) != QRhi::FrameOpSuccess
            || !commandBuffer) {
            d = QStringLiteral("Metal beginOffscreenFrame failed");
            return false;
        }
        const QRhiMetalCommandBufferNativeHandles *commandHandles =
            static_cast<const QRhiMetalCommandBufferNativeHandles *>(
                commandBuffer->nativeHandles());
        rhi->endOffscreenFrame();
        const bool ok = deviceHandles && deviceHandles->dev && deviceHandles->cmdQueue
            && commandHandles && commandHandles->commandBuffer;
        d = QStringLiteral("device=%1 queue=%2 command-buffer=%3")
                .arg(deviceHandles && deviceHandles->dev)
                .arg(deviceHandles && deviceHandles->cmdQueue)
                .arg(commandHandles && commandHandles->commandBuffer);
        return ok;
#else
        r.skip(d, QStringLiteral("Metal is available only in Apple Qt builds"));
        return false;
#endif
    });

    r.check("rhi/shader-value-types", [&](QString &d) {
#if QT_VERSION_MAJOR >= 6
        // A QShader is what a pipeline stage takes. Producing one from GLSL is
        // QShaderBaker's job and needs the shader toolchain; assembling,
        // serialising and reading one back is pure value-type work.
        QShaderVersion version(100, QShaderVersion::GlslEs);
        QShaderKey key(QShader::GlslShader, version);
        QShaderCode code(QByteArrayLiteral("void main() {}"), QByteArrayLiteral("main"));

        QShader shader;
        shader.setStage(QShader::VertexStage);
        shader.setShader(key, code);
        QShaderDescription description;
        shader.setDescription(description);

        const QByteArray serialised = shader.serialized();
        const QShader restored = QShader::fromSerialized(serialised);

        QRhiShaderStage stage(QRhiShaderStage::Vertex, shader);

        QStringList misses;
        if (version.version() != 100) misses << QStringLiteral("version");
        if (key.source() != QShader::GlslShader) misses << QStringLiteral("key");
        if (code.entryPoint() != QByteArrayLiteral("main")) misses << QStringLiteral("code");
        if (!shader.isValid()) misses << QStringLiteral("shader");
        if (serialised.isEmpty()) misses << QStringLiteral("serialize");
        if (restored.stage() != QShader::VertexStage) misses << QStringLiteral("roundtrip");
        if (stage.type() != QRhiShaderStage::Vertex) misses << QStringLiteral("stage");
        if (description.isValid()) misses << QStringLiteral("empty description should be invalid");
        if (!misses.isEmpty())
            d = misses.join(QLatin1Char(','));
        return misses.isEmpty();
#else
        r.skip(d, QStringLiteral("QShader is Qt 6 only"));
        return false;
#endif
    });
}
