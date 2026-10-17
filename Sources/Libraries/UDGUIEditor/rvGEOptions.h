/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * rvGEOptions.h — the GUI editor's options (tools/guied/GEOptions.h,
 * GEOptions.cpp), ported: the grid, snapping to it, the colors the
 * workspace draws with, the status bar shown. The engine kept them in the
 * registry (Software\id Software\DOOM3\Tools\GUIEditor); here, a
 * dictionary by the registry's names, which the workspace they are used in
 * keeps (UDWorkspace's toolSettings).
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
@property (nonatomic) BOOL statusBarVisible;     // YES
/// The options dialog's page last shown.
@property (nonatomic) int lastOptionsPage;       // 0

/// Load: the options from @a registry (each one not in it as it was).
- (void)loadRegistry:(nullable NSDictionary *)registry;
/// Save: the options as a registry to keep.
- (NSDictionary *)registry;

/// SnapRectToGrid: the sides asked for moved to the nearest grid line.
- (void)snapRectToGrid:(idRectangle *)rect snapLeft:(BOOL)snapLeft snapTop:(BOOL)snapTop
             snapWidth:(BOOL)snapWidth snapHeight:(BOOL)snapHeight;

@end

NS_ASSUME_NONNULL_END
