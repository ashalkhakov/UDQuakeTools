/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * rvGEOptions.h — the GUI editor's options (tools/guied/GEOptions.h,
 * GEOptions.cpp), ported: the grid, snapping to it, the colors the
 * workspace draws with. The engine kept them in the registry; here the
 * application keeps them (its defaults are the engine's).
 */

#import <Foundation/Foundation.h>
#import "idMath.h"

NS_ASSUME_NONNULL_BEGIN

@interface rvGEOptions : NSObject

@property (nonatomic) idVec4 gridColor;          // 0.2 0.2 1 1
@property (nonatomic) int gridWidth;             // 10
@property (nonatomic) int gridHeight;            // 10
@property (nonatomic) BOOL gridSnap;             // NO
@property (nonatomic) BOOL gridVisible;          // NO
@property (nonatomic) BOOL ignoreDesktopSelect;  // YES
@property (nonatomic) idVec4 workspaceColor;     // 0 0 0 1
@property (nonatomic) idVec4 selectionColor;     // 0.5 0.5 1 1

/// SnapRectToGrid: the sides asked for moved to the nearest grid line.
- (void)snapRectToGrid:(idRectangle *)rect snapLeft:(BOOL)snapLeft snapTop:(BOOL)snapTop
             snapWidth:(BOOL)snapWidth snapHeight:(BOOL)snapHeight;

@end

NS_ASSUME_NONNULL_END
