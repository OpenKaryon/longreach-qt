// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// QtShaderTools is optional, but where the SDK ships it this is a real shader
// compiler check rather than a construction probe: one valid GLSL shader must
// become SPIR-V and one invalid shader must produce a diagnostic.
#include "../common/smokecheck.h"

#ifdef SMOKE_HAVE_SHADERTOOLS
#include <rhi/qshaderbaker.h>
#include <rhi/qshader.h>
#endif

void checkShaderTools(SmokeReporter &r)
{
    r.check("shadertools/bake-valid-and-invalid", [&](QString &d) {
#ifdef SMOKE_HAVE_SHADERTOOLS
        static const char validVertexShader[] =
            "#version 440\n"
            "layout(location = 0) in vec4 position;\n"
            "void main() { gl_Position = position; }\n";

        QShaderBaker baker;
        baker.setSourceString(QByteArray(validVertexShader), QShader::VertexStage);
        baker.setGeneratedShaderVariants({ QShader::StandardShader });
        baker.setGeneratedShaders({
            { QShader::SpirvShader, QShaderVersion(100) }
        });
        const QShader shader = baker.bake();
        if (!shader.isValid()) {
            d = QStringLiteral("valid shader failed: %1").arg(baker.errorMessage());
            return false;
        }

        const QShaderKey key(QShader::SpirvShader, QShaderVersion(100));
        if (shader.shader(key).shader().isEmpty()) {
            d = QStringLiteral("baker returned no SPIR-V payload");
            return false;
        }

        QShaderBaker invalid;
        invalid.setSourceString(QByteArrayLiteral("this is not GLSL"),
                                QShader::FragmentStage);
        invalid.setGeneratedShaders({
            { QShader::SpirvShader, QShaderVersion(100) }
        });
        const QShader badShader = invalid.bake();
        if (badShader.isValid() || invalid.errorMessage().isEmpty()) {
            d = QStringLiteral("invalid shader was accepted without a diagnostic");
            return false;
        }
        return true;
#else
        r.skip(d, QStringLiteral("QtShaderTools is not in this SDK"));
        return false;
#endif
    });
}
