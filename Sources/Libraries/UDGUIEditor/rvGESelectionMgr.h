/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * rvGESelectionMgr.h — the GUI editor's selection (tools/guied/
 * GESelectionMgr.h, GESelectionMgr.cpp), ported: the windows selected, the
 * rectangle around them in the workspace's window, what a point over it
 * is (inside, one of its eight sizing handles), and how it is drawn.
 *
 * Where the engine told its navigator, transformer and properties window
 * of a change, this posts rvGESelectionDidChangeNotification.
 */

#import <Foundation/Foundation.h>
#import "idMath.h"

@class idWindow, rvGEWorkspace, UDOverlay;

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const rvGESelectionDidChangeNotification;

/// rvGESelectionMgr::EHitTest
typedef NS_ENUM(int, rvGEHitTest) {
    HT_NONE,
    HT_SELECT,
    HT_MOVE,
    HT_SIZE_TOPLEFT,
    HT_SIZE_TOP,
    HT_SIZE_TOPRIGHT,
    HT_SIZE_RIGHT,
    HT_SIZE_BOTTOMRIGHT,
    HT_SIZE_BOTTOM,
    HT_SIZE_BOTTOMLEFT,
    HT_SIZE_LEFT
};

/// GUIED_GRABSIZE, GUIED_CENTERSIZE: a handle's size, the centre mark's, in
/// the window's pixels.
#define GUIED_GRABSIZE      7
#define GUIED_CENTERSIZE    5

@interface rvGESelectionMgr : NSObject

@property (nonatomic, weak, nullable) rvGEWorkspace *workspace;

- (void)set:(idWindow *)window;
- (void)add:(idWindow *)window expand:(BOOL)expand;
- (void)add:(idWindow *)window;
- (void)remove:(idWindow *)window;
- (void)clear;
- (int)num;
- (idWindow *)objectAtIndexedSubscript:(NSUInteger)index;
@property (nonatomic, copy, readonly) NSArray<idWindow *> *windows;

/// Render: the selections, the rectangle around them and its handles.
- (void)renderInto:(UDOverlay *)overlay;
/// What ( @a x, @a y ), in the window, is over.
- (rvGEHitTest)hitTestX:(float)x y:(float)y;
- (BOOL)isSelected:(idWindow *)window;
/// IsExpression: one of them has a rect that is an expression (it can be
/// selected, not moved or sized).
- (BOOL)isExpression;
/// GetRect: around them all, in the window.
- (idRectangle)rect;
- (nullable idWindow *)bottomMost;

@end

NS_ASSUME_NONNULL_END
