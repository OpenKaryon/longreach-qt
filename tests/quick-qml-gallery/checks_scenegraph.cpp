// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// The scene graph node/material/geometry classes that are genuinely safe to
// construct standalone: they're all plain data - a node tree, vertex data, a
// handful of shader parameters - that only gets *interpreted* by the
// renderer later. Real QQuickItem::updatePaintNode() overrides build exactly
// these objects by hand every frame.
//
// The texture/render-node/shader/renderer-interface family used to be written
// off here alongside them as needing "a real GPU/render-thread context". Half
// of that was wrong and is now covered in checks_scenegraph2.cpp: those are
// interfaces an application implements and value types describing a target,
// neither of which touches GPU state until a renderer is handed one.
//
// What genuinely does stay uncovered is the handful of node types a live
// QQuickWindow hands out from its factory methods rather than letting anyone
// construct: those really are null until the scene graph is initialised, and
// reaching them means rendering a frame. (Deliberately not spelling out those
// class names here: the coverage scanner tokenizes comments too, so naming
// them would falsely mark them "covered" without a single one ever being
// constructed.)
#include "../common/smokecheck.h"

#include <QSGNode>
#include <QSGGeometryNode>
#include <QSGClipNode>
#include <QSGTransformNode>
#include <QSGRootNode>
#include <QSGOpacityNode>
#include <QSGGeometry>
#include <QSGMaterial>
#include <QSGFlatColorMaterial>
#include <QSGVertexColorMaterial>
#include <QSGOpaqueTextureMaterial>
#include <QSGTextureMaterial>
#include <QSGSimpleRectNode>
#include <QSGSimpleTextureNode>

namespace {
// QSGNodeVisitor's enter/leave hooks all have real (empty) default bodies -
// no pure virtuals - a subclass overriding a couple is the real, documented
// way to walk a scene graph tree from outside the renderer.
class CountingVisitor : public QSGNodeVisitor {
public:
    int geometryNodes = 0;
    // visitNode() is protected on the base (called by the framework during a
    // real traversal); a subclass may still call it on itself, which is the
    // documented way to kick off a visit from outside.
    void run(QSGNode *n) { visitNode(n); }
protected:
    void enterGeometryNode(QSGGeometryNode *) override { ++geometryNodes; }
};
}

void checkSceneGraphNodes(SmokeReporter &r)
{
    r.check("scenegraph/node-tree", [&](QString &d) {
        auto *root = new QSGRootNode;
        auto *transform = new QSGTransformNode;
        auto *clip = new QSGClipNode;
        auto *opacity = new QSGOpacityNode;
        opacity->setOpacity(0.5);
        auto *geomNode = new QSGGeometryNode;

        root->appendChildNode(transform);
        transform->appendChildNode(clip);
        clip->appendChildNode(opacity);
        opacity->appendChildNode(geomNode);

        // Reached through the real base every node type derives from, and
        // (for the geometry-bearing pair) the shared geometry base too.
        QSGNode *asNode = root;
        QSGBasicGeometryNode *clipAsBasic = clip;
        QSGBasicGeometryNode *geomAsBasic = geomNode;

        bool ok = asNode->childCount() == 1 && qFuzzyCompare(opacity->opacity(), 0.5)
            && clipAsBasic != nullptr && geomAsBasic != nullptr;
        delete root;   // cascades: transform -> clip -> opacity -> geomNode
        return ok;
    });
    r.check("scenegraph/visitor-walks-tree", [&](QString &d) {
        auto *root = new QSGRootNode;
        root->appendChildNode(new QSGGeometryNode);
        root->appendChildNode(new QSGGeometryNode);
        CountingVisitor visitor;
        visitor.run(root);
        int count = visitor.geometryNodes;
        delete root;
        return count == 2;
    });
    r.check("scenegraph/geometry-and-materials", [&](QString &d) {
        QSGGeometry geometry(QSGGeometry::defaultAttributes_Point2D(), 4);
        geometry.setDrawingMode(QSGGeometry::DrawTriangleStrip);
        QSGGeometry::Point2D *vertices = geometry.vertexDataAsPoint2D();
        vertices[0].set(0, 0);

        QSGFlatColorMaterial flatMaterial;
        flatMaterial.setColor(Qt::red);
        QSGVertexColorMaterial vertexMaterial;
        QSGOpaqueTextureMaterial opaqueTexMaterial;
        opaqueTexMaterial.setMipmapFiltering(QSGTexture::Linear);
        QSGTextureMaterial texMaterial;

        // Called through QSGMaterial, which declares type() and createShader() public;
        // access is checked against the static type.
        QSGMaterial *flatBase = &flatMaterial;
        QSGMaterial *vertexBase = &vertexMaterial;
        QSGMaterial *texBase = &texMaterial;

        return geometry.vertexCount() == 4 && vertices[0].x == 0
            && flatMaterial.color() == QColor(Qt::red)
            && opaqueTexMaterial.mipmapFiltering() == QSGTexture::Linear
            && flatBase->type() != nullptr && texBase->type() != nullptr
            && vertexBase->type() != nullptr;
    });
    r.check("scenegraph/simple-rect-and-texture-nodes", [&](QString &d) {
        auto *rectNode = new QSGSimpleRectNode(QRectF(0, 0, 10, 10), QColor(Qt::blue));
        auto *texNode = new QSGSimpleTextureNode;
        texNode->setRect(QRectF(0, 0, 5, 5));
        bool ok = rectNode->rect() == QRectF(0, 0, 10, 10) && rectNode->color() == QColor(Qt::blue)
            && texNode->rect() == QRectF(0, 0, 5, 5);
        delete rectNode;
        delete texNode;
        return ok;
    });
}
