/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * rvGEOptions.m — tools/guied/GEOptions.cpp, ported (its defaults, and
 * SnapRectToGrid).
 */

#import "rvGEOptions.h"

@implementation rvGEOptions

- (instancetype)init {
    self = [super init];
    if (self) {
        _gridColor = idVec4_Make( 0.2f, 0.2f, 1.0f, 1.0f );
        _gridWidth = 10;
        _gridHeight = 10;
        _gridSnap = NO;
        _gridVisible = NO;
        _ignoreDesktopSelect = YES;
        _workspaceColor = idVec4_Make( 0.0f, 0.0f, 0.0f, 1.0f );
        _selectionColor = idVec4_Make( 0.5f, 0.5f, 1.0f, 1.0f );
    }
    return self;
}

/*
================
rvGEOptions::SnapRectToGrid

Snap the rectangle to the grid
================
*/
- (void)snapRectToGrid:(idRectangle *)rect snapLeft:(BOOL)snapLeft snapTop:(BOOL)snapTop
             snapWidth:(BOOL)snapWidth snapHeight:(BOOL)snapHeight {
    int gridWidth = self.gridWidth, gridHeight = self.gridHeight;

    if ( snapLeft ) {
        float offset = (int)(rect->x + gridWidth / 2) / gridWidth * gridWidth;
        offset -= rect->x;
        rect->x += offset;
        rect->w -= offset;
    }

    if ( snapWidth ) {
        float offset = (int)(rect->x + rect->w + gridWidth / 2) / gridWidth * gridWidth;
        offset -= rect->x;
        offset -= rect->w;
        rect->w += offset;
    }

    if ( snapTop ) {
        float offset = (int)(rect->y + gridHeight / 2) / gridHeight * gridHeight;
        offset -= rect->y;
        rect->y += offset;
        rect->h -= offset;
    }

    if ( snapHeight ) {
        float offset = (int)(rect->y + rect->h + gridHeight / 2) / gridHeight * gridHeight;
        offset -= rect->y;
        offset -= rect->h;
        rect->h += offset;
    }
}

@end
