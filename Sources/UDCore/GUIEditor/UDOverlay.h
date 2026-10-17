/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDOverlay.h — what the GUI editor draws over a GUI (its grid, its
 * selections: rvGEWorkspace::RenderGrid, rvGESelectionMgr::Render), as the
 * engine draws it with GL's immediate mode: lines and filled triangles in
 * the window's coordinates (y down), each of a color, blended
 * (GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA). A view draws the list with GL or
 * in software.
 */

#import <Foundation/Foundation.h>
#import "idMath.h"

NS_ASSUME_NONNULL_BEGIN

/// A vertex of the list: where, and its color.
typedef struct {
    float x, y;
    float r, g, b, a;
} UDOverlayVertex;

@interface UDOverlay : NSObject

/// GL_LINES' pairs and GL_TRIANGLES' threes, in the order added.
@property (nonatomic, readonly) NSUInteger lineVertexCount;
@property (nonatomic, readonly) const UDOverlayVertex *lineVertices;
@property (nonatomic, readonly) NSUInteger triangleVertexCount;
@property (nonatomic, readonly) const UDOverlayVertex *triangleVertices;

- (void)clear;
- (void)addLineFromX:(float)x0 y:(float)y0 toX:(float)x1 y:(float)y1 color:(idVec4)color;
/// GL_LINE_LOOP of four corners; GL_POLYGON_MODE GL_LINE's quad.
- (void)addLineLoopX0:(float)x0 y0:(float)y0 x1:(float)x1 y1:(float)y1 x2:(float)x2 y2:(float)y2 x3:(float)x3 y3:(float)y3 color:(idVec4)color;
- (void)addTriangleX0:(float)x0 y0:(float)y0 x1:(float)x1 y1:(float)y1 x2:(float)x2 y2:(float)y2 color:(idVec4)color;
/// GL_QUADS filled: two triangles.
- (void)addQuadX0:(float)x0 y0:(float)y0 x1:(float)x1 y1:(float)y1 x2:(float)x2 y2:(float)y2 x3:(float)x3 y3:(float)y3 color:(idVec4)color;

@end

NS_ASSUME_NONNULL_END
