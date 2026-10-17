/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDOverlay.m — the GUI editor's lines and triangles over a GUI.
 */

#import "UDOverlay.h"

@implementation UDOverlay {
    NSMutableData *_lines;
    NSMutableData *_triangles;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _lines = [NSMutableData data];
        _triangles = [NSMutableData data];
    }
    return self;
}

- (NSUInteger)lineVertexCount {
    return _lines.length / sizeof(UDOverlayVertex);
}

- (const UDOverlayVertex *)lineVertices {
    return _lines.bytes;
}

- (NSUInteger)triangleVertexCount {
    return _triangles.length / sizeof(UDOverlayVertex);
}

- (const UDOverlayVertex *)triangleVertices {
    return _triangles.bytes;
}

- (void)clear {
    _lines.length = 0;
    _triangles.length = 0;
}

static void UDAddVertex(NSMutableData *data, float x, float y, idVec4 color) {
    UDOverlayVertex v = { x, y, color.x, color.y, color.z, color.w };
    [data appendBytes:&v length:sizeof(v)];
}

- (void)addLineFromX:(float)x0 y:(float)y0 toX:(float)x1 y:(float)y1 color:(idVec4)color {
    UDAddVertex(_lines, x0, y0, color);
    UDAddVertex(_lines, x1, y1, color);
}

- (void)addLineLoopX0:(float)x0 y0:(float)y0 x1:(float)x1 y1:(float)y1 x2:(float)x2 y2:(float)y2 x3:(float)x3 y3:(float)y3 color:(idVec4)color {
    [self addLineFromX:x0 y:y0 toX:x1 y:y1 color:color];
    [self addLineFromX:x1 y:y1 toX:x2 y:y2 color:color];
    [self addLineFromX:x2 y:y2 toX:x3 y:y3 color:color];
    [self addLineFromX:x3 y:y3 toX:x0 y:y0 color:color];
}

- (void)addTriangleX0:(float)x0 y0:(float)y0 x1:(float)x1 y1:(float)y1 x2:(float)x2 y2:(float)y2 color:(idVec4)color {
    UDAddVertex(_triangles, x0, y0, color);
    UDAddVertex(_triangles, x1, y1, color);
    UDAddVertex(_triangles, x2, y2, color);
}

- (void)addQuadX0:(float)x0 y0:(float)y0 x1:(float)x1 y1:(float)y1 x2:(float)x2 y2:(float)y2 x3:(float)x3 y3:(float)y3 color:(idVec4)color {
    [self addTriangleX0:x0 y0:y0 x1:x1 y1:y1 x2:x2 y2:y2 color:color];
    [self addTriangleX0:x0 y0:y0 x1:x2 y1:y2 x2:x3 y2:y3 color:color];
}

@end
