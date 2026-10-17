/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * rvGEOptions.m — tools/guied/GEOptions.cpp, ported (its defaults, and
 * SnapRectToGrid).
 */

#import "rvGEOptions.h"

static NSArray<NSNumber *> *rvGEOptions_FromVec4( idVec4 v ) {
    return @[ @(v.x), @(v.y), @(v.z), @(v.w) ];
}

static BOOL rvGEOptions_ToVec4( id value, idVec4 *v ) {
    if ( ![value isKindOfClass:[NSArray class]] || [value count] != 4 ) {
        return NO;
    }
    *v = idVec4_Make( [value[0] floatValue], [value[1] floatValue], [value[2] floatValue], [value[3] floatValue] );
    return YES;
}

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
        _statusBarVisible = YES;
    }
    return self;
}

/*
================
rvGEOptions::Save

Writes the options to the registry so they can later be read using Load
================
*/
- (NSDictionary *)registry {
    return @{
        @"lastOptionsPage": @(self.lastOptionsPage),
        @"gridColor": rvGEOptions_FromVec4( idVec4_Make( self.gridColor.x, self.gridColor.y, self.gridColor.z, 1.0f ) ),
        @"gridWidth": @(self.gridWidth),
        @"gridHeight": @(self.gridHeight),
        @"gridSnap": @(self.gridSnap),
        @"gridVisible": @(self.gridVisible),
        @"statusBarVisible": @(self.statusBarVisible),
        @"selectionColor": rvGEOptions_FromVec4( self.selectionColor ),
        @"ignoreDesktopSelect": @(self.ignoreDesktopSelect),
    };
}

/*
================
rvGEOptions::Load

Loads the options from the registry
================
*/
- (void)loadRegistry:(NSDictionary *)registry {
    if ( ![registry isKindOfClass:[NSDictionary class]] ) {
        return;
    }
    idVec4 v;
    if ( registry[@"lastOptionsPage"] ) self.lastOptionsPage = [registry[@"lastOptionsPage"] intValue];
    if ( rvGEOptions_ToVec4( registry[@"gridColor"], &v ) ) self.gridColor = v;
    if ( registry[@"gridWidth"] ) self.gridWidth = [registry[@"gridWidth"] intValue];
    if ( registry[@"gridHeight"] ) self.gridHeight = [registry[@"gridHeight"] intValue];
    if ( registry[@"gridSnap"] ) self.gridSnap = [registry[@"gridSnap"] boolValue];
    if ( registry[@"gridVisible"] ) self.gridVisible = [registry[@"gridVisible"] boolValue];
    if ( registry[@"statusBarVisible"] ) self.statusBarVisible = [registry[@"statusBarVisible"] boolValue];
    if ( rvGEOptions_ToVec4( registry[@"selectionColor"], &v ) ) self.selectionColor = v;
    if ( registry[@"ignoreDesktopSelect"] ) self.ignoreDesktopSelect = [registry[@"ignoreDesktopSelect"] boolValue];
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
